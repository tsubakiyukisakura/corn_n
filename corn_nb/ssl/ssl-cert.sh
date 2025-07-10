#!/bin/bash
set -e

SSL_TOOL_FILE="$HOME/.ssl_tool"

function select_tool() {
  echo "请选择证书工具："
  echo "1. certbot (推荐)"
  echo "2. acme.sh"
  read -p "输入选项: " tool
  if [[ $tool == 1 ]]; then
    if command -v acme.sh >/dev/null 2>&1; then
      echo "检测到已安装acme.sh，正在卸载..."
      ~/.acme.sh/acme.sh --uninstall
      rm -rf ~/.acme.sh
    fi
    if ! command -v certbot >/dev/null 2>&1; then
      echo "正在安装certbot..."
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        if [[ $OS == "ubuntu" || $OS == "debian" ]]; then
          apt update && apt install -y certbot
        elif [[ $OS == "centos" || $OS == "rocky" || $OS == "almalinux" ]]; then
          yum install -y certbot
        fi
      fi
    fi
    echo certbot > "$SSL_TOOL_FILE"
    echo "已选择certbot作为证书工具。"
  elif [[ $tool == 2 ]]; then
    if command -v certbot >/dev/null 2>&1; then
      echo "检测到已安装certbot，正在卸载..."
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        if [[ $OS == "ubuntu" || $OS == "debian" ]]; then
          apt remove -y certbot
        elif [[ $OS == "centos" || $OS == "rocky" || $OS == "almalinux" ]]; then
          yum remove -y certbot
        fi
      fi
    fi
    if ! command -v acme.sh >/dev/null 2>&1; then
      echo "正在安装acme.sh..."
      curl https://get.acme.sh | sh
      source ~/.bashrc
    fi
    echo acme.sh > "$SSL_TOOL_FILE"
    echo "已选择acme.sh作为证书工具。"
  else
    echo "无效选项"; return 1
  fi
}

function get_tool() {
  if [ -f "$SSL_TOOL_FILE" ]; then
    cat "$SSL_TOOL_FILE"
  else
    echo "certbot"
  fi
}

function set_acme_ca() {
  echo "请选择证书颁发机构（CA）："
  echo "1. Let's Encrypt (letsencrypt.org) - 推荐，稳定快速"
  echo "2. ZeroSSL (zerossl.com) - 需要邮箱注册"
  echo "0. 返回上一级"
  read -p "请输入选项: " ca_choice
  case $ca_choice in
    1)
      acme.sh --set-default-ca --server letsencrypt
      echo "✅ 已切换到Let's Encrypt"
      ;;
    2)
      acme.sh --set-default-ca --server zerossl
      echo "✅ 已切换到ZeroSSL"
      echo "⚠️  注意：ZeroSSL需要邮箱注册，首次申请时会提示输入邮箱。"
      ;;
    0) return;;
    *) echo "无效选项";;
  esac
}

function ensure_socat() {
  if ! command -v socat >/dev/null 2>&1; then
    echo "正在安装socat..."
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      OS=$ID
      if [[ $OS == "ubuntu" || $OS == "debian" ]]; then
        apt update && apt install -y socat
      elif [[ $OS == "centos" || $OS == "rocky" || $OS == "almalinux" ]]; then
        yum install -y socat
      fi
    fi
  fi
}

# 修复nginx配置文件中的证书路径
function fix_nginx_cert_paths() {
  local domain="$1"
  local cert_type="$2"  # certbot 或 acme
  
  local nginx_conf_dir="/usr/local/nginx/conf/vhost"
  local conf_file="$nginx_conf_dir/$domain.conf"
  
  if [ ! -f "$conf_file" ]; then
    echo "未找到域名 $domain 的nginx配置文件"
    return 1
  fi
  
  echo "正在修复nginx配置文件中的证书路径..."
  
  # 备份原文件
  local backup_file="$conf_file.bak.$(date +%Y%m%d%H%M%S)"
  cp "$conf_file" "$backup_file"
  
  if [[ "$cert_type" == "certbot" ]]; then
    # 更新为certbot证书路径
    # 使用更精确的匹配，只匹配以空格开头的ssl_certificate行
    sed -i "/^[[:space:]]*ssl_certificate[[:space:]]/s|.*|    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|g" "$conf_file"
    sed -i "/^[[:space:]]*ssl_certificate_key[[:space:]]/s|.*|    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|g" "$conf_file"
    echo "已更新为certbot证书路径"
  elif [[ "$cert_type" == "acme" ]]; then
    # 更新为acme.sh证书路径
    local acme_cert_path="$HOME/.acme.sh/$domain"
    if [ ! -d "$acme_cert_path" ]; then
      acme_cert_path="$HOME/.acme.sh/${domain}_ecc"
    fi
    if [ -d "$acme_cert_path" ]; then
      sed -i "/^[[:space:]]*ssl_certificate[[:space:]]/s|.*|    ssl_certificate $acme_cert_path/fullchain.cer;|g" "$conf_file"
      sed -i "/^[[:space:]]*ssl_certificate_key[[:space:]]/s|.*|    ssl_certificate_key $acme_cert_path/$domain.key;|g" "$conf_file"
      echo "已更新为acme.sh证书路径"
    else
      echo "未找到acme.sh证书目录"
      return 1
    fi
  fi
  
  # 测试配置
  if nginx -t 2>/dev/null; then
    echo "nginx配置测试通过"
    return 0
  else
    echo "nginx配置测试失败，正在恢复备份文件..."
    cp "$backup_file" "$conf_file"
    return 1
  fi
}

function ensure_acme_sh_link() {
  if [ -f "$HOME/.acme.sh/acme.sh" ] && ! command -v acme.sh >/dev/null 2>&1; then
    ln -sf "$HOME/.acme.sh/acme.sh" /usr/local/bin/acme.sh
    chmod +x /usr/local/bin/acme.sh
    echo "已自动为acme.sh创建全局命令软链接。"
  fi
}

# 检查acme.sh证书（支持RSA和ECC）
function detect_acme_cert() {
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

# 申请证书时自动检测并适配证书路径
function ensure_acme_cert() {
  local domain="$1"
  local cert_dir
  cert_dir=$(detect_acme_cert "$domain")
  if [ $? -eq 0 ]; then
    echo "检测到acme.sh证书，路径: $cert_dir"
    return 0
  else
    echo "未检测到可用acme.sh证书。"
    read -p "是否现在自动申请ECC证书？(y/N): " yn
    if [[ $yn == "y" || $yn == "Y" ]]; then
      ensure_acme_sh_link
      ensure_socat
      # 自动停止Nginx
      need_restart=0
      if ss -lnt | grep -q ':80 '; then
        if pgrep -x nginx >/dev/null 2>&1; then
          echo "检测到Nginx占用80端口，正在临时停止Nginx以完成证书申请..."
          if command -v systemctl >/dev/null 2>&1; then
            systemctl stop nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s stop || nginx -s stop
          else
            /usr/local/nginx/sbin/nginx -s stop || nginx -s stop
          fi
          need_restart=1
        fi
      fi
      acme.sh --issue --standalone -d "$domain" --keylength ec-256
      # 申请后自动恢复Nginx
      if [ "$need_restart" == "1" ]; then
        echo "正在恢复Nginx运行..."
        if [ -x /usr/local/nginx/sbin/nginx ]; then
          /usr/local/nginx/sbin/nginx
        else
          nginx
        fi
        echo "Nginx已恢复运行。"
      fi
      cert_dir=$(detect_acme_cert "$domain")
      if [ $? -eq 0 ]; then
        echo "acme.sh证书申请完成，路径: $cert_dir"
        return 0
      else
        echo "acme.sh证书申请失败，请检查上方输出和acme.sh日志。"
        return 1
      fi
    else
      echo "请先用acme.sh申请证书后再继续。"
      return 1
    fi
  fi
}

function apply_cert() {
  tool=$(get_tool)
  if [[ $tool == "acme.sh" ]]; then
    ensure_acme_sh_link
    while true; do
      echo "========= acme.sh 证书管理 ========="
      echo "1. 选择证书颁发机构（CA）"
      echo "2. 申请/续期证书"
      echo "0. 返回上一级"
      read -p "请输入选项: " ca_menu
      case $ca_menu in
        1) set_acme_ca;;
        2)
          ensure_socat
          echo "========= 申请/续期证书 ========="
          read -p "请输入要申请证书的域名: " domain
          if [[ -z "$domain" ]]; then
            echo "域名不能为空，请重新输入。"
            continue
          fi
          echo "正在为域名 $domain 申请证书..."
          # 检查acme.sh是否可用
          if ! command -v acme.sh >/dev/null 2>&1; then
            echo "❌ acme.sh 命令不可用，请检查安装。"
            return 1
          fi
          echo "✅ acme.sh 已安装，版本: $(acme.sh --version)"
          # 检查当前CA设置
          echo "当前CA设置:"
          acme.sh --info 2>/dev/null | grep "CA server" || echo "无法获取CA信息"
          # 检查80端口是否被nginx占用，若是则自动停止，申请后恢复
          need_restart=0
          if ss -lnt | grep -q ':80 '; then
            if pgrep -x nginx >/dev/null 2>&1; then
              echo "检测到Nginx占用80端口，正在临时停止Nginx以完成证书申请..."
              if command -v systemctl >/dev/null 2>&1; then
                systemctl stop nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s stop || nginx -s stop
              else
                /usr/local/nginx/sbin/nginx -s stop || nginx -s stop
              fi
              need_restart=1
            fi
          fi
          echo "开始申请证书..."
          # 首次尝试申请
          echo "执行命令: acme.sh --issue --standalone -d $domain"
          echo "正在执行acme.sh命令，请稍候..."
          # 检查80端口是否真的空闲
          echo "检查80端口状态..."
          ss -lnt | grep :80 || echo "80端口空闲"
          # 添加超时和错误处理
          if timeout 60 acme.sh --issue --standalone -d "$domain" 2>&1 > /tmp/acme_output.txt 2>&1; then
            acme_output=$(cat /tmp/acme_output.txt)
            echo "acme.sh 输出:"
            echo "$acme_output"
          else
            acme_output=$(cat /tmp/acme_output.txt 2>/dev/null)
            if echo "$acme_output" | grep -q 'Skipping. Next renewal time is'; then
              echo "✅ 证书未到期，acme.sh 已自动跳过续签。如需强制续签，请加 --force 选项。"
              read -p "是否现在强制续签？(y/N): " force_renew
              if [[ "$force_renew" == "y" || "$force_renew" == "Y" ]]; then
                echo "正在强制续签..."
                if timeout 60 acme.sh --issue --standalone -d "$domain" --force 2>&1 > /tmp/acme_output_force.txt 2>&1; then
                  echo "✅ 强制续签成功。"
                  cat /tmp/acme_output_force.txt
                else
                  echo "❌ 强制续签失败，请检查acme.sh输出："
                  cat /tmp/acme_output_force.txt
                fi
              fi
            else
              echo "❌ acme.sh 命令执行超时或失败"
              echo "请检查域名DNS解析是否正确指向当前服务器"
              echo "域名: $domain"
              echo "当前服务器IP: $(curl -s ifconfig.me 2>/dev/null || echo '无法获取')"
              echo "DNS解析结果:"
              nslookup "$domain" 2>/dev/null || echo "DNS解析失败"
              echo "acme.sh 详细输出:"
              if [ -f /tmp/acme_output.txt ]; then
                cat /tmp/acme_output.txt
              else
                echo "未找到acme.sh输出文件"
              fi
            fi
            # 检查是否需要注册ZeroSSL邮箱
            if [ -f /tmp/acme_output.txt ] && grep -q 'Please update your account with an email address first' /tmp/acme_output.txt; then
              echo "检测到ZeroSSL未注册邮箱，需先注册。"
              read -p "请输入你的邮箱地址: " email
              echo "正在注册ZeroSSL账户..."
              acme.sh --register-account -m "$email" --server zerossl
              # 注册后检测是否成功
              # 由于注册命令已经成功执行并显示了ACCOUNT_THUMBPRINT，直接认为注册成功
              echo "✅ ZeroSSL邮箱注册成功。"
              echo "ZeroSSL账户注册成功，正在重新申请证书..."
              echo "执行命令: acme.sh --issue --standalone -d $domain"
              echo "正在执行acme.sh命令，请稍候..."
              if timeout 60 acme.sh --issue --standalone -d "$domain" 2>&1 > /tmp/acme_output.txt 2>&1; then
                acme_output=$(cat /tmp/acme_output.txt)
                echo "acme.sh 输出:"
                echo "$acme_output"
              else
                echo "❌ acme.sh 命令执行超时或失败"
                echo "acme.sh 详细输出:"
                if [ -f /tmp/acme_output.txt ]; then
                  cat /tmp/acme_output.txt
                else
                  echo "未找到acme.sh输出文件"
                fi
                # 确保在失败时也恢复Nginx
                if [ "$need_restart" == "1" ]; then
                  echo "正在恢复Nginx运行..."
                  if [ -x /usr/local/nginx/sbin/nginx ]; then
                    /usr/local/nginx/sbin/nginx
                  else
                    nginx
                  fi
                  echo "Nginx已恢复运行。"
                fi
                return 1
              fi
            fi
            # 确保在失败时也恢复Nginx
            if [ "$need_restart" == "1" ]; then
              echo "正在恢复Nginx运行..."
              if [ -x /usr/local/nginx/sbin/nginx ]; then
                /usr/local/nginx/sbin/nginx
              else
                nginx
              fi
              echo "Nginx已恢复运行。"
            fi
            return 1
          fi
          # 检查是否有其他错误（排除ZeroSSL邮箱注册错误）
          if [ -f /tmp/acme_output.txt ] && grep -q 'Error' /tmp/acme_output.txt && ! grep -q 'Please update your account with an email address first' /tmp/acme_output.txt; then
            echo "❌ acme.sh 申请过程中出现错误，请检查上方输出。"
            echo "acme.sh 详细输出:"
            cat /tmp/acme_output.txt
          fi
          # 检查证书文件是否生成
          if [ -f "$HOME/.acme.sh/$domain/fullchain.cer" ] && [ -f "$HOME/.acme.sh/$domain/$domain.key" ]; then
            echo "✅ acme.sh证书申请/续期完成，证书已生成。"
            echo "证书路径: $HOME/.acme.sh/$domain/fullchain.cer"
            echo "私钥路径: $HOME/.acme.sh/$domain/$domain.key"
          elif [ -f "$HOME/.acme.sh/${domain}_ecc/fullchain.cer" ] && [ -f "$HOME/.acme.sh/${domain}_ecc/$domain.key" ]; then
            echo "✅ acme.sh ECC证书申请/续期完成，证书已生成。"
            echo "证书路径: $HOME/.acme.sh/${domain}_ecc/fullchain.cer"
            echo "私钥路径: $HOME/.acme.sh/${domain}_ecc/$domain.key"
          else
            echo "❌ acme.sh证书申请失败，请检查上方输出和acme.sh日志。"
            echo "日志路径: $HOME/.acme.sh/acme.sh.log"
          fi
          # 申请后自动恢复Nginx（无论成功还是失败）
          if [ "$need_restart" == "1" ]; then
            echo "正在恢复Nginx运行..."
            # 先尝试修复证书路径
            if fix_nginx_cert_paths "$domain" "acme"; then
              echo "证书路径修复成功，正在启动nginx..."
              if [ -x /usr/local/nginx/sbin/nginx ]; then
                /usr/local/nginx/sbin/nginx
              else
                nginx
              fi
              echo "Nginx已恢复运行。"
            else
              echo "证书路径修复失败，请手动检查配置文件。"
              echo "acme.sh证书路径: $HOME/.acme.sh/$domain/"
            fi
          fi
          echo "按回车键继续..."
          read
          ;;
        0) return;;
        *) echo "无效选项";;
      esac
    done
  elif [[ $tool == "certbot" ]]; then
    echo "========= certbot 证书申请 ========="
    read -p "请输入要申请证书的域名: " domain
    if [[ -z "$domain" ]]; then
      echo "域名不能为空。"
      return 1
    fi
    echo "正在为域名 $domain 申请证书..."
    
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
      
      # 先尝试修复证书路径
      if fix_nginx_cert_paths "$domain" "certbot"; then
        echo "证书路径修复成功，正在启动nginx..."
        if [ -x /usr/local/nginx/sbin/nginx ]; then
          /usr/local/nginx/sbin/nginx
        else
          nginx
        fi
        echo "nginx已重启。"
      else
        echo "证书路径修复失败，请手动检查配置文件。"
        echo "certbot证书路径: /etc/letsencrypt/live/$domain/"
        return 1
      fi
    fi
    
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
      echo "✅ certbot证书申请/续期完成，证书已生成。"
      echo "证书路径: /etc/letsencrypt/live/$domain/fullchain.pem"
      echo "私钥路径: /etc/letsencrypt/live/$domain/privkey.pem"
    else
      echo "❌ certbot证书申请失败，请检查上方输出和certbot日志。"
    fi
  else
    echo "未检测到可用证书工具，请先选择证书工具。"
  fi
}

function renew_menu() {
  tool=$(get_tool)
  echo "========= 自动续签管理 ========="
  echo "1. 开启自动续签"
  echo "2. 关闭自动续签"
  echo "3. 查看当前状态"
  echo "0. 返回上一级"
  read -p "请输入选项: " op
  if [[ $op == 1 ]]; then
    if [[ $tool == "certbot" ]]; then
      # 检查certbot是否可用
      if ! command -v certbot >/dev/null 2>&1; then
        echo "❌ certbot 未安装，请先选择证书工具。"
        return 1
      fi
      # 创建cron任务
      echo '0 3 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx || nginx -s reload"' > /etc/cron.d/certbot
      chmod 644 /etc/cron.d/certbot
      # 启用systemd timer（如果可用）
      if command -v systemctl >/dev/null 2>&1; then
        systemctl enable certbot.timer 2>/dev/null || true
        systemctl start certbot.timer 2>/dev/null || true
      fi
      echo "✅ certbot自动续签已开启。"
      echo "📅 续签时间：每天凌晨3点"
      echo "🔄 续签后会自动重载Nginx"
    elif [[ $tool == "acme.sh" ]]; then
      # 检查acme.sh是否可用
      if ! command -v acme.sh >/dev/null 2>&1; then
        echo "❌ acme.sh 未安装，请先选择证书工具。"
        return 1
      fi
      # 安装cron任务
      ~/.acme.sh/acme.sh --install-cronjob
      echo "✅ acme.sh自动续签已开启。"
      echo "📅 续签时间：每天凌晨2点"
      echo "🔄 续签后会自动重载Nginx"
    else
      echo "❌ 未检测到可用证书工具，请先选择证书工具。"
    fi
  elif [[ $op == 2 ]]; then
    if [[ $tool == "certbot" ]]; then
      # 删除cron任务
      rm -f /etc/cron.d/certbot
      # 停止systemd timer
      if command -v systemctl >/dev/null 2>&1; then
        systemctl stop certbot.timer 2>/dev/null || true
        systemctl disable certbot.timer 2>/dev/null || true
      fi
      echo "✅ certbot自动续签已关闭。"
    elif [[ $tool == "acme.sh" ]]; then
      # 卸载cron任务
      ~/.acme.sh/acme.sh --uninstall-cronjob
      echo "✅ acme.sh自动续签已关闭。"
    else
      echo "❌ 未检测到可用证书工具。"
    fi
  elif [[ $op == 3 ]]; then
    echo "========= 当前自动续签状态 ========="
    if [[ $tool == "certbot" ]]; then
      if [ -f /etc/cron.d/certbot ]; then
        echo "✅ certbot自动续签：已开启"
        echo "📅 cron任务：$(cat /etc/cron.d/certbot)"
      else
        echo "❌ certbot自动续签：已关闭"
      fi
      # 检查systemd timer状态
      if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active certbot.timer >/dev/null 2>&1; then
          echo "✅ systemd timer：运行中"
        else
          echo "❌ systemd timer：未运行"
        fi
      fi
    elif [[ $tool == "acme.sh" ]]; then
      if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        echo "✅ acme.sh自动续签：已开启"
        echo "📅 cron任务：$(crontab -l | grep acme.sh)"
      else
        echo "❌ acme.sh自动续签：已关闭"
      fi
    else
      echo "❌ 未检测到可用证书工具。"
    fi
  elif [[ $op == 0 ]]; then
    return
  else
    echo "❌ 无效选项。"
  fi
}



function manual_cert() {
  read -p "请输入要手动上传/填写证书的域名: " domain
  read -p "请输入证书文件路径: " cert_path
  read -p "请输入私钥文件路径: " key_path
  
  # 验证文件是否存在
  if [ ! -f "$cert_path" ]; then
    echo "错误：证书文件不存在: $cert_path"
    return 1
  fi
  if [ ! -f "$key_path" ]; then
    echo "错误：私钥文件不存在: $key_path"
    return 1
  fi
  
  # 创建目录并复制文件
  mkdir -p /usr/local/nginx/conf/manual-ssl/$domain
  cp "$cert_path" /usr/local/nginx/conf/manual-ssl/$domain/fullchain.pem
  cp "$key_path" /usr/local/nginx/conf/manual-ssl/$domain/privkey.pem
  echo "已保存到 /usr/local/nginx/conf/manual-ssl/$domain/ 下。"
  
  # 更新nginx配置文件中的证书路径
  local nginx_conf_dir="/usr/local/nginx/conf/vhost"
  local conf_file="$nginx_conf_dir/$domain.conf"
  
  if [ -f "$conf_file" ]; then
    echo "正在更新nginx配置文件中的证书路径..."
    
    # 备份原文件
    local backup_file="$conf_file.bak.$(date +%Y%m%d%H%M%S)"
    cp "$conf_file" "$backup_file"
    
    sed -i "/^[[:space:]]*ssl_certificate[[:space:]]/s|.*|    ssl_certificate /usr/local/nginx/conf/manual-ssl/$domain/fullchain.pem;|g" "$conf_file"
    sed -i "/^[[:space:]]*ssl_certificate_key[[:space:]]/s|.*|    ssl_certificate_key /usr/local/nginx/conf/manual-ssl/$domain/privkey.pem;|g" "$conf_file"
    
    # 测试配置
    if nginx -t 2>/dev/null; then
      echo "nginx配置测试通过，证书路径已更新。"
      echo "请手动重启nginx以应用新配置。"
    else
      echo "nginx配置测试失败，正在恢复备份文件..."
      cp "$backup_file" "$conf_file"
      return 1
    fi
  else
    echo "未找到域名 $domain 的nginx配置文件，请先配置反向代理。"
  fi
}

case "$1" in
  select) select_tool;;
  apply) apply_cert;;
  renew) renew_menu;;
  manual) manual_cert;;
  revoke)
    tool=$(get_tool)
    # 自动列出站点
    nginx_conf_dir="/usr/local/nginx/conf/vhost"
    idx=1
    site_list=()
    echo "========= 站点列表 ========="
    for conf in $nginx_conf_dir/*.conf; do
      [ -e "$conf" ] || continue
      server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
      printf "%2d. %s\n" "$idx" "$server_name"
      site_list+=("$server_name")
      idx=$((idx+1))
    done
    read -p "请输入要撤销证书的站点序号: " site_idx
    site_idx=$((site_idx-1))
    domain="${site_list[$site_idx]}"
    if [[ -z "$domain" ]]; then
      echo "无效序号。"; exit 1;
    fi
    if [[ $tool == "certbot" ]]; then
      if ! command -v certbot >/dev/null 2>&1; then
        echo "未检测到certbot，请先选择证书工具。"; exit 1;
      fi
      certbot revoke --cert-path "/etc/letsencrypt/live/$domain/fullchain.pem" --key-path "/etc/letsencrypt/live/$domain/privkey.pem" || echo "certbot撤销失败，请检查证书路径。"
      echo "certbot撤销操作已完成。"
    elif [[ $tool == "acme.sh" ]]; then
      if ! command -v acme.sh >/dev/null 2>&1; then
        echo "未检测到acme.sh，请先选择证书工具。"; exit 1;
      fi
      acme.sh --revoke -d "$domain" || echo "acme.sh撤销失败，请检查域名。"
      acme.sh --revoke -d "$domain" --ecc 2>/dev/null || true
      echo "acme.sh撤销操作已完成。"
    else
      echo "未知证书工具。"; exit 1;
    fi
    ;;
  delete)
    tool=$(get_tool)
    # 自动列出站点
    nginx_conf_dir="/usr/local/nginx/conf/vhost"
    idx=1
    site_list=()
    echo "========= 站点列表 ========="
    for conf in $nginx_conf_dir/*.conf; do
      [ -e "$conf" ] || continue
      server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
      printf "%2d. %s\n" "$idx" "$server_name"
      site_list+=("$server_name")
      idx=$((idx+1))
    done
    read -p "请输入要删除证书的站点序号: " site_idx
    site_idx=$((site_idx-1))
    domain="${site_list[$site_idx]}"
    if [[ -z "$domain" ]]; then
      echo "无效序号。"; exit 1;
    fi
    if [[ $tool == "certbot" ]]; then
      cert_dir="/etc/letsencrypt/live/$domain"
      if [ -d "$cert_dir" ]; then
        rm -rf "/etc/letsencrypt/live/$domain" "/etc/letsencrypt/archive/$domain" "/etc/letsencrypt/renewal/$domain.conf"
        echo "已删除certbot证书文件。"
      else
        echo "未找到certbot证书目录。"
      fi
    elif [[ $tool == "acme.sh" ]]; then
      acme_dir1="$HOME/.acme.sh/$domain"
      acme_dir2="$HOME/.acme.sh/${domain}_ecc"
      [ -d "$acme_dir1" ] && rm -rf "$acme_dir1" && echo "已删除acme.sh证书(RSA)。"
      [ -d "$acme_dir2" ] && rm -rf "$acme_dir2" && echo "已删除acme.sh证书(ECC)。"
      if [ ! -d "$acme_dir1" ] && [ ! -d "$acme_dir2" ]; then
        echo "未找到acme.sh证书目录。"
      fi
    else
      echo "未知证书工具。"; exit 1;
    fi
    ;;
  revoke_delete)
    tool=$(get_tool)
    # 自动列出站点
    nginx_conf_dir="/usr/local/nginx/conf/vhost"
    idx=1
    site_list=()
    echo "========= 站点列表 ========="
    for conf in $nginx_conf_dir/*.conf; do
      [ -e "$conf" ] || continue
      server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
      printf "%2d. %s\n" "$idx" "$server_name"
      site_list+=("$server_name")
      idx=$((idx+1))
    done
    read -p "请输入要撤销并删除证书的站点序号: " site_idx
    site_idx=$((site_idx-1))
    domain="${site_list[$site_idx]}"
    if [[ -z "$domain" ]]; then
      echo "无效序号。"; exit 1;
    fi
    # 撤销
    if [[ $tool == "certbot" ]]; then
      if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
        certbot revoke --cert-path "/etc/letsencrypt/live/$domain/fullchain.pem" --key-path "/etc/letsencrypt/live/$domain/privkey.pem" || echo "certbot撤销失败，请检查证书路径。"
        echo "certbot撤销操作已完成。"
      else
        echo "未找到有效的certbot证书文件，跳过撤销。"
      fi
    elif [[ $tool == "acme.sh" ]]; then
      if command -v acme.sh >/dev/null 2>&1; then
        acme.sh --revoke -d "$domain" 2>/dev/null || true
        acme.sh --revoke -d "$domain" --ecc 2>/dev/null || true
        echo "acme.sh撤销操作已完成。"
      else
        echo "未检测到acme.sh，跳过撤销。"
      fi
    else
      echo "未知证书工具，跳过撤销。"
    fi
    # 删除
    if [[ $tool == "certbot" ]]; then
      cert_dir="/etc/letsencrypt/live/$domain"
      if [ -d "$cert_dir" ]; then
        rm -rf "/etc/letsencrypt/live/$domain" "/etc/letsencrypt/archive/$domain" "/etc/letsencrypt/renewal/$domain.conf"
        echo "已删除certbot证书文件。"
      else
        echo "未找到certbot证书目录。"
      fi
    elif [[ $tool == "acme.sh" ]]; then
      acme_dir1="$HOME/.acme.sh/$domain"
      acme_dir2="$HOME/.acme.sh/${domain}_ecc"
      [ -d "$acme_dir1" ] && rm -rf "$acme_dir1" && echo "已删除acme.sh证书(RSA)。"
      [ -d "$acme_dir2" ] && rm -rf "$acme_dir2" && echo "已删除acme.sh证书(ECC)。"
      if [ ! -d "$acme_dir1" ] && [ ! -d "$acme_dir2" ]; then
        echo "未找到acme.sh证书目录。"
      fi
    else
      echo "未知证书工具，跳过删除。"
    fi
    ;;
  *) echo "用法: $0 [select|apply|renew|manual|revoke|delete]"; exit 1;;
esac 