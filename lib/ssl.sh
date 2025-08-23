#!/bin/bash
# SSL证书相关函数

# 检测acme.sh证书
# 返回证书目录或1
# 用于acme.sh: ~/.acme.sh/$domain 或 ~/.acme.sh/${domain}_ecc

detect_acme_cert() {
  local domain="$1"
  local cert_dir1="$HOME/.acme.sh/$domain"
  local cert_dir2="$HOME/.acme.sh/${domain}_ecc"
  if [ -f "$cert_dir1/fullchain.cer" ] && [ -f "$cert_dir1/$domain.key" ]; then
    echo "$cert_dir1"
    return 0
  elif [ -f "$cert_dir2/fullchain.cer" ] && [ -f "$cert_dir2/$domain.key" ]; then
    echo "$cert_dir2"
    return 0
  else
    return 1
  fi
}

# 检测certbot证书
# 返回证书目录或1
# certbot证书一般在 /etc/letsencrypt/live/$domain/

detect_certbot_cert() {
  local domain="$1"
  local cert_dir="/etc/letsencrypt/live/$domain"
  if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
    echo "$cert_dir"
    return 0
  else
    return 1
  fi
}

# 保证acme.sh全局可用
ensure_acme_sh_link() {
  if [ -f "$HOME/.acme.sh/acme.sh" ] && ! command -v acme.sh >/dev/null 2>&1; then
    ln -sf "$HOME/.acme.sh/acme.sh" /usr/local/bin/acme.sh
    chmod +x /usr/local/bin/acme.sh
    echo "已自动为acme.sh创建全局命令软链接。"
  fi
}

# 保证socat可用
ensure_socat() {
  if ! command -v socat >/dev/null 2>&1; then
    echo "检测到未安装socat，正在自动安装..."
    if command -v apt >/dev/null 2>&1; then
      apt update && apt install -y socat
    elif command -v yum >/dev/null 2>&1; then
      yum install -y socat
    else
      echo "请手动安装socat后重试。"
      return 1
    fi
  fi
}

# 自动检测/申请acme.sh证书
ensure_acme_cert() {
  local domain="$1"
  local cert_dir
  cert_dir=$(detect_acme_cert "$domain")
  if [ $? -eq 0 ]; then
    echo "检测到acme.sh证书，路径: $cert_dir"
    return 0
  else
    echo "未检测到可用acme.sh证书。"
    read -p "是否现在自动用acme.sh申请ECC证书？(y/N): " yn
    if [[ $yn == "y" || $yn == "Y" ]]; then
      ensure_acme_sh_link
      ensure_socat
      
      # 停止nginx服务
      need_restart=0
      if ss -lnt | grep -q ':80 '; then
        echo "检测到80端口被占用，正在停止nginx..."
        # 先尝试优雅停止
        if pgrep -x nginx >/dev/null 2>&1; then
          echo "优雅停止nginx服务..."
          nginx -s quit 2>/dev/null || nginx -s stop 2>/dev/null || systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null
          need_restart=1
          # 等待进程完全退出
          sleep 5
          # 如果还有进程，再强制停止
          if pgrep -x nginx >/dev/null 2>&1; then
            echo "强制停止剩余的nginx进程..."
            pkill -9 nginx 2>/dev/null || true
            sleep 2
          fi
        fi
        # 清理PID文件
        if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
          echo "清理nginx PID文件..."
          rm -f /usr/local/nginx/logs/nginx.pid
        fi
      fi
      
      # 确保80端口可用
      if ss -lnt | grep -q ':80 '; then
        echo "错误：80端口仍被占用，无法申请证书。"
        echo "请手动停止占用80端口的服务后重试。"
        return 1
      fi
      
      echo "80端口已释放，开始申请证书..."
      bash "$(dirname "$BASH_SOURCE")/../ssl/acme-apply.sh" -d "$domain" -t ecc
      
      # 申请完成后重启nginx
      if [ $need_restart -eq 1 ]; then
        echo "证书申请完成，正在重启nginx..."
        sleep 2
        if [ -x /usr/local/nginx/sbin/nginx ]; then
          /usr/local/nginx/sbin/nginx
        else
          nginx
        fi
        echo "nginx已重启。"
      fi
      
      cert_dir=$(detect_acme_cert "$domain")
      if [ $? -eq 0 ]; then
        echo "acme.sh证书申请成功，路径: $cert_dir"
        return 0
      else
        echo "acme.sh证书申请失败。"
        return 1
      fi
    else
      echo "用户取消acme.sh证书自动申请。"
      return 1
    fi
  fi
}

# 自动检测/申请certbot证书
ensure_certbot_cert() {
  local domain="$1"
  local cert_dir
  cert_dir=$(detect_certbot_cert "$domain")
  if [ $? -eq 0 ]; then
    echo "检测到certbot证书，路径: $cert_dir"
    return 0
  else
    echo "未检测到可用certbot证书。"
    read -p "是否现在自动用certbot申请证书？(y/N): " yn
    if [[ $yn == "y" || $yn == "Y" ]]; then
      if ! command -v certbot >/dev/null 2>&1; then
        echo "未检测到certbot，正在自动安装..."
        if command -v apt >/dev/null 2>&1; then
          apt update && apt install -y certbot
        elif command -v yum >/dev/null 2>&1; then
          yum install -y certbot
        else
          echo "请手动安装certbot后重试。"
          return 1
        fi
      fi
      # 自动停止占用80端口的服务
      need_restart=0
      if ss -lnt | grep -q ':80 '; then
        echo "检测到80端口被占用，正在停止相关服务..."
        # 尝试停止nginx
        if pgrep -x nginx >/dev/null 2>&1; then
          echo "停止nginx服务..."
          nginx -s stop 2>/dev/null || systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null || pkill -9 nginx 2>/dev/null
          need_restart=1
        fi
        # 等待端口释放
        sleep 3
        # 再次检查端口
        if ss -lnt | grep -q ':80 '; then
          echo "警告：80端口仍被占用，尝试强制释放..."
          # 查找占用80端口的进程
          local port_pid=$(ss -lntp | grep ':80 ' | awk '{print $6}' | sed 's/.*pid=\([0-9]*\).*/\1/' | head -1)
          if [ -n "$port_pid" ]; then
            echo "强制停止进程 $port_pid..."
            kill -9 "$port_pid" 2>/dev/null || true
            sleep 2
          fi
        fi
      fi
      
      # 确保80端口可用
      if ss -lnt | grep -q ':80 '; then
        echo "错误：80端口仍被占用，无法申请证书。"
        echo "请手动停止占用80端口的服务后重试。"
        return 1
      fi
      
      echo "80端口已释放，开始申请证书..."
      certbot certonly --standalone -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email
      
      # 申请完成后重启nginx
      if [ $need_restart -eq 1 ]; then
        echo "证书申请完成，正在重启nginx..."
        sleep 2
        if [ -x /usr/local/nginx/sbin/nginx ]; then
          /usr/local/nginx/sbin/nginx
        else
          nginx
        fi
        echo "nginx已重启。"
      fi
      cert_dir=$(detect_certbot_cert "$domain")
      if [ $? -eq 0 ]; then
        echo "certbot证书申请成功，路径: $cert_dir"
        return 0
      else
        echo "certbot证书申请失败。"
        return 1
      fi
    else
      echo "用户取消certbot证书自动申请。"
      return 1
    fi
  fi
}

# 统一入口：自动检测SSL证书，优先certbot，再acme.sh
# 用法：ensure_ssl_cert 域名
# 检测顺序：certbot > acme.sh > 提示用户去管理SSL证书
ensure_ssl_cert() {
  local domain="$1"
  # 优先certbot
  if command -v certbot >/dev/null 2>&1; then
    if cert_dir=$(detect_certbot_cert "$domain"); then
      echo "检测到certbot证书，路径: $cert_dir"
      return 0
    fi
  fi
  # 再acme.sh
  if command -v acme.sh >/dev/null 2>&1; then
    if cert_dir=$(detect_acme_cert "$domain"); then
      echo "检测到acme.sh证书，路径: $cert_dir"
      return 0
    fi
  fi
  
  # 都没有则提示用户去管理SSL证书
  echo "未检测到 $domain 的SSL证书。"
  echo "请先到'7. 管理SSL证书'模块申请证书，然后再配置反向代理。"
  return 1
}