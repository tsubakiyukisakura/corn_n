#!/bin/bash
set -e

# 引入SSL证书相关函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_SSL="$SCRIPT_DIR/lib/ssl.sh"
[ -f "$LIB_SSL" ] && source "$LIB_SSL"

NGINX_CONF_DIR="/usr/local/nginx/conf"
PROXY_CONF="$NGINX_CONF_DIR/vhost"
SSL_CONF="$NGINX_CONF_DIR/ssl"
mkdir -p "$PROXY_CONF" "$SSL_CONF"

# 自动修复nginx配置函数
auto_fix_nginx_config() {
  echo "========= 自动修复nginx配置 ========="
  
  # 自动修复重复的server配置
  script_dir="$(dirname "$0")"
  if [ -f "$script_dir/config-fix-utils.py" ]; then
    echo "正在检查并修复重复的server配置..."
    python3 "$script_dir/config-fix-utils.py" fix >/dev/null 2>&1
  fi
  
  # 检查nginx是否安装
  if ! command -v nginx >/dev/null 2>&1; then
    echo "❌ nginx未安装，请先安装nginx"
    return 1
  fi
  
  echo "✅ nginx已安装"
  
  # 检查nginx配置文件
  local nginx_conf="/usr/local/nginx/conf/nginx.conf"
  if [ ! -f "$nginx_conf" ]; then
    nginx_conf="/etc/nginx/nginx.conf"
  fi
  
  if [ ! -f "$nginx_conf" ]; then
    echo "❌ 未找到nginx主配置文件"
    return 1
  fi
  
  echo "✅ 找到nginx配置文件: $nginx_conf"
  
  # 备份配置文件
  local backup_file="$nginx_conf.bak.$(date +%Y%m%d%H%M%S)"
  cp "$nginx_conf" "$backup_file"
  echo "已备份配置文件到: $backup_file"
  
  # 1. 检查并修复PID文件
  if pgrep -x nginx >/dev/null 2>&1; then
    local nginx_pid=$(pgrep -x nginx | head -1)
    if [ -n "$nginx_pid" ]; then
      echo "$nginx_pid" > /usr/local/nginx/logs/nginx.pid 2>/dev/null || true
      echo "✅ 已修复nginx PID文件: $nginx_pid"
    fi
  else
    # 如果nginx未运行，清理PID文件
    if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
      rm -f /usr/local/nginx/logs/nginx.pid
      echo "✅ 已清理无效的nginx PID文件"
    fi
  fi
  
  # 2. 检查并创建必要的目录
  local pid_dir="/usr/local/nginx/logs"
  local vhost_dir="/usr/local/nginx/conf/vhost"
  local log_dir="/usr/local/nginx/logs"
  
  if [ ! -d "$pid_dir" ]; then
    mkdir -p "$pid_dir"
    echo "✅ 已创建PID文件目录: $pid_dir"
  fi
  
  if [ ! -d "$vhost_dir" ]; then
    mkdir -p "$vhost_dir"
    echo "✅ 已创建vhost目录: $vhost_dir"
  fi
  
  if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    echo "✅ 已创建日志目录: $log_dir"
  fi
  
  # 3. 检查并修复配置文件
  local needs_fix=0
  
  # 检查是否需要添加include语句
  if ! grep -q "include.*vhost.*\.conf" "$nginx_conf"; then
    needs_fix=1
    echo "⚠️  检测到缺少vhost include语句"
  fi
  
  # 检查是否需要注释默认server块
  if grep -q "server_name.*localhost" "$nginx_conf"; then
    needs_fix=1
    echo "⚠️  检测到默认server块需要注释"
  fi
  
  if [ $needs_fix -eq 1 ]; then
    echo "正在修复nginx配置文件..."
    
    # 创建临时文件
    local temp_file="$nginx_conf.tmp"
    
    # 使用更安全的awk脚本修复配置
    awk '
    BEGIN { http=0; inc=0; inserver=0; in_default_server=0 }
    
    /^[[:space:]]*http[[:space:]]*{/ { 
      http=1; 
      print; 
      next 
    }
    
    /^[[:space:]]*http[[:space:]]*}/ { 
      if (!inc) {
        print "    include /usr/local/nginx/conf/vhost/*.conf;";
        inc=1;
      }
      http=0; 
      print; 
      next 
    }
    
    /^[[:space:]]*server[[:space:]]*{/ && http {
      if (!inc) {
        print "    include /usr/local/nginx/conf/vhost/*.conf;";
        inc=1;
      }
      # 检查是否是默认server块
      in_default_server=1;
      print "#server {";
      next;
    }
    
    /^[[:space:]]*}/ && in_default_server {
      print "#}";
      in_default_server=0;
      next;
    }
    
    { 
      if (in_default_server) {
        print "#" $0;
      } else {
        print $0;
      }
    }
    ' "$nginx_conf" > "$temp_file"
    
    if [ $? -eq 0 ]; then
      mv "$temp_file" "$nginx_conf"
      echo "✅ 已修复nginx配置文件"
    else
      echo "❌ 配置文件修复失败"
      rm -f "$temp_file"
      return 1
    fi
  else
    echo "✅ nginx配置文件无需修复"
  fi
  
  # 4. 检查并修复SSL证书路径问题
  echo "检查SSL证书路径..."
  local cert_errors=$(nginx -t 2>&1 | grep -E "(certificate|key)" || true)
  if [ -n "$cert_errors" ]; then
    echo "⚠️  检测到SSL证书路径问题，正在修复..."
    
    # 检查vhost配置文件中的证书路径
    local vhost_dir="/usr/local/nginx/conf/vhost"
    if [ -d "$vhost_dir" ]; then
      for conf_file in "$vhost_dir"/*.conf; do
        [ -f "$conf_file" ] || continue
        
        # 备份vhost配置文件
        local vhost_backup="$conf_file.bak.$(date +%Y%m%d%H%M%S)"
        cp "$conf_file" "$vhost_backup"
        
        # 检查并修复证书路径
        local domain=$(grep -m1 'server_name' "$conf_file" | awk '{print $2}' | sed 's/;//')
        if [ -n "$domain" ]; then
          echo "检查域名 $domain 的证书路径..."
          
          # 检查certbot证书
          if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
            echo "找到certbot证书，更新路径..."
            sed -i "/^[[:space:]]*ssl_certificate[[:space:]]/s|.*|    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;|g" "$conf_file"
            sed -i "/^[[:space:]]*ssl_certificate_key[[:space:]]/s|.*|    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;|g" "$conf_file"
          else
            # 检查acme.sh证书
            local acme_cert_path="$HOME/.acme.sh/$domain"
            if [ ! -d "$acme_cert_path" ]; then
              acme_cert_path="$HOME/.acme.sh/${domain}_ecc"
            fi
            
            if [ -d "$acme_cert_path" ] && [ -f "$acme_cert_path/fullchain.cer" ] && [ -f "$acme_cert_path/$domain.key" ]; then
              echo "找到acme.sh证书，更新路径..."
              sed -i "/^[[:space:]]*ssl_certificate[[:space:]]/s|.*|    ssl_certificate $acme_cert_path/fullchain.cer;|g" "$conf_file"
              sed -i "/^[[:space:]]*ssl_certificate_key[[:space:]]/s|.*|    ssl_certificate_key $acme_cert_path/$domain.key;|g" "$conf_file"
            else
              echo "⚠️  未找到域名 $domain 的有效证书，注释SSL配置..."
              # 注释掉SSL相关配置
              sed -i '/^[[:space:]]*ssl_certificate/s/^/#/' "$conf_file"
              sed -i '/^[[:space:]]*ssl_certificate_key/s/^/#/' "$conf_file"
              sed -i '/^[[:space:]]*ssl_protocols/s/^/#/' "$conf_file"
              sed -i '/^[[:space:]]*ssl_ciphers/s/^/#/' "$conf_file"
              sed -i '/^[[:space:]]*ssl_prefer_server_ciphers/s/^/#/' "$conf_file"
              # 将443端口改为80端口
              sed -i 's/listen 443 ssl/listen 80/' "$conf_file"
            fi
          fi
        fi
      done
    fi
  fi
  
  # 5. 测试配置
  echo "测试nginx配置..."
  if nginx -t 2>/dev/null; then
    echo "✅ nginx配置测试通过"
  else
    echo "❌ nginx配置测试失败"
    echo "错误详情："
    nginx -t 2>&1
    echo "正在恢复备份文件..."
    cp "$backup_file" "$nginx_conf"
    return 1
  fi
  
  echo "========= 修复完成 ========="
  return 0
}

# nginx重载函数
gentle_nginx_reload() {
  local nginx_bin="/usr/local/nginx/sbin/nginx"
  
  # 检查nginx是否运行
  if ! pgrep -x nginx >/dev/null 2>&1; then
    echo "Nginx未运行，正在启动..."
    # 先自动修复配置
    if auto_fix_nginx_config; then
      # 先清理可能存在的PID文件
      if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
        rm -f /usr/local/nginx/logs/nginx.pid
      fi
      # 测试配置
      if [ -x "$nginx_bin" ]; then
        $nginx_bin -t 2>/dev/null || nginx -t 2>/dev/null
        if [ $? -eq 0 ]; then
          $nginx_bin
        else
          nginx
        fi
      else
        nginx -t 2>/dev/null && nginx
      fi
      echo "Nginx已启动。"
    else
      echo "❌ 自动修复失败，无法启动nginx"
      return 1
    fi
  else
    echo "正在重载nginx配置..."
    # 先测试配置
    if [ -x "$nginx_bin" ]; then
      $nginx_bin -t 2>/dev/null || nginx -t 2>/dev/null
    else
      nginx -t 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
      # 配置测试通过，尝试重载
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reload nginx 2>/dev/null || $nginx_bin -s reload 2>/dev/null || nginx -s reload 2>/dev/null
      else
        $nginx_bin -s reload 2>/dev/null || nginx -s reload 2>/dev/null
      fi
      
      if [ $? -eq 0 ]; then
        echo "Nginx配置重载成功。"
        return 0
      fi
    fi
    
    echo "重载失败，尝试重启nginx..."
    # 停止nginx
    nginx -s quit 2>/dev/null || nginx -s stop 2>/dev/null || systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null
    sleep 3
    # 如果还有进程，强制停止
    if pgrep -x nginx >/dev/null 2>&1; then
      echo "强制停止剩余的nginx进程..."
      pkill -9 nginx 2>/dev/null || true
      sleep 2
    fi
    # 清理PID文件
    if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
      rm -f /usr/local/nginx/logs/nginx.pid
    fi
    # 重新启动
    if [ -x "$nginx_bin" ]; then
      $nginx_bin
    else
      nginx
    fi
    echo "Nginx已重启。"
  fi
}

function list_sites() {
  echo "========= 已有站点 ========="
  for conf in $PROXY_CONF/*.conf; do
    [ -e "$conf" ] || continue
    server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
    listen_port=$(grep -m1 'listen' "$conf" | awk '{print $2}' | sed 's/;//')
    echo "站点: $server_name | 端口: $listen_port | 配置文件: $(basename $conf)"
  done
  echo "============================"
}

function list_sites_array() {
  site_list=()
  i=1
  for conf in $PROXY_CONF/*.conf; do
    [ -e "$conf" ] || continue
    server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//' | sed 's/(.*)//')
    existing_proxy_pass=$(grep -m1 'proxy_pass' "$conf" | awk '{print $2}' | sed 's/;//')
    # 提取目标端口
    if [[ $existing_proxy_pass =~ ([0-9]+)$ ]]; then
      target_port="${BASH_REMATCH[1]}"
    else
      target_port="-"
    fi
    site_list+=("$server_name|$target_port|$conf")
    printf "%2d. %-25s 目标端口: %-8s\n" "$i" "$server_name" "$target_port"
    i=$((i+1))
  done
}

function show_sites() {
  NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
  if [ ! -d "$NGINX_CONF_DIR" ]; then
    echo "当前无已配置站点。"
    return
  fi
  printf "%-25s %-10s %-8s %-8s\n" "站点" "目标端口" "类型" "状态"
  printf '%0.s-' {1..60}; echo
  for conf in $NGINX_CONF_DIR/*.conf; do
    [ -e "$conf" ] || continue
    server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//' | sed 's/(.*)//')
    existing_proxy_pass=$(grep -m1 'proxy_pass' "$conf" | awk '{print $2}' | sed 's/;//')
    # 提取目标端口
    if [[ $existing_proxy_pass =~ ([0-9]+)$ ]]; then
      target_port="${BASH_REMATCH[1]}"
    else
      target_port="-"
    fi
    if [[ $existing_proxy_pass == http://127.0.0.1* ]]; then
      type="本机端口"
    elif [[ $existing_proxy_pass =~ ^http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
      type="公网IP"
    else
      type="域名"
    fi
    # 检查目标端口运行情况
    if [[ $target_port != "-" ]] && ss -lnt | grep -q ":$target_port "; then
      status="运行中"
    else
      status="未监听"
    fi
    printf "%-25s %-10s %-8s %-8s\n" "$server_name" "$target_port" "$type" "$status"
  done
  printf '%0.s-' {1..60}; echo
}

function force_https_menu() {
  echo "========= 强制HTTPS菜单 ========="
  echo "1. 全部开启强制HTTPS"
  echo "2. 全部关闭强制HTTPS"
  echo "3. 选择域名开启强制HTTPS"
  echo "4. 选择域名关闭强制HTTPS"
  echo "0. 返回上一级"
  read -p "请输入选项: " choice
  case $choice in
    1)
      for conf in $PROXY_CONF/*.conf; do
        [ -e "$conf" ] || continue
        awk 'BEGIN{s=0} /listen 80/ {s=1; print; getline; print; getline; print "    return 301 https://$host$request_uri;\n}"; while(getline && $0!~/^}/); next} {print}' "$conf" > "$conf.tmp"
        mv "$conf.tmp" "$conf"
      done
      echo "已为全部站点开启强制HTTPS。"
      ;;
    2)
      for conf in $PROXY_CONF/*.conf; do
        [ -e "$conf" ] || continue
        # 恢复80端口server块为原始反代内容
        awk 'BEGIN{s=0} /listen 80/ {s=1; print; getline; print; getline; while(getline && $0!~/^}/); print "}"; next} {print}' "$conf" > "$conf.tmp"
        mv "$conf.tmp" "$conf"
      done
      echo "已为全部站点关闭强制HTTPS。"
      ;;
    3)
      list_sites_array
      read -p "请输入要开启强制HTTPS的站点序号: " idx
      idx=$((idx-1))
      if [[ -z "${site_list[$idx]}" ]]; then
        echo "无效序号。"
        return
      fi
      conf_file=$(echo "${site_list[$idx]}" | awk -F'|' '{print $3}')
      awk 'BEGIN{s=0} /listen 80/ {s=1; print; getline; print; getline; print "    return 301 https://$host$request_uri;\n}"; while(getline && $0!~/^}/); next} {print}' "$conf_file" > "$conf_file.tmp"
      mv "$conf_file.tmp" "$conf_file"
      echo "已为该站点开启强制HTTPS。"
      ;;
    4)
      list_sites_array
      read -p "请输入要关闭强制HTTPS的站点序号: " idx
      idx=$((idx-1))
      if [[ -z "${site_list[$idx]}" ]]; then
        echo "无效序号。"
        return
      fi
      conf_file=$(echo "${site_list[$idx]}" | awk -F'|' '{print $3}')
      awk 'BEGIN{s=0} /listen 80/ {s=1; print; getline; print; getline; while(getline && $0!~/^}/); print "}"; next} {print}' "$conf_file" > "$conf_file.tmp"
      mv "$conf_file.tmp" "$conf_file"
      echo "已为该站点关闭强制HTTPS。"
      ;;
    0) return;;
    *) echo "无效选项";;
      esac
  # 重载nginx
  gentle_nginx_reload
}

function get_ssl_tool() {
  if [ -f "$HOME/.ssl_tool" ]; then
    cat "$HOME/.ssl_tool"
  else
    echo "certbot"
  fi
}

function add_proxy() {
  echo "1. 本机端口"
  echo "2. 公网IP+端口"
  echo "3. 域名"
  echo "4. 静态网页"
  echo "5. 访问加密"
  echo "6. 防盗链设置"
  echo "7. 流量限制"
  echo "0. 返回上一级"
  read -p "输入选项: " mode
  if [[ $mode == 0 ]]; then
    return
  fi
  if [[ $mode == 5 ]]; then
    echo "1. 密码访问"
    echo "2. 黑白名单访问"
    echo "3. 关闭/重置密码访问"
    echo "4. 关闭/重置黑白名单访问"
    read -p "请选择加密方式: " enc_mode
    if [[ $enc_mode == 1 || $enc_mode == 2 ]]; then
      idx=1
      for conf in $PROXY_CONF/*.conf; do
        [ -e "$conf" ] || continue
        server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
        printf "%2d. %s\n" "$idx" "$server_name"
        idx=$((idx+1))
      done
      read -p "请输入要设置的域名序号: " site_idx
      conf_file=$(get_conf_by_index "$site_idx")
      if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
        echo "无效序号。"
        return
      fi
      server_name=$(grep -m1 'server_name' "$conf_file" | awk '{print $2}' | sed 's/;//')
      htpasswd_file="$PROXY_CONF/$server_name.htpasswd"
      htpasswd_file_abs=$(readlink -f "$htpasswd_file")
      if [[ $enc_mode == 1 ]]; then
        # 自动安装htpasswd工具
        if ! command -v htpasswd >/dev/null 2>&1; then
          echo "未检测到htpasswd命令，正在尝试自动安装..."
          if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y apache2-utils
          elif command -v yum >/dev/null 2>&1; then
            yum install -y httpd-tools
          else
            echo "请手动安装htpasswd工具（apt install apache2-utils 或 yum install httpd-tools）后重试。"
            return 1
          fi
        fi
        if ! command -v htpasswd >/dev/null 2>&1; then
          echo "自动安装htpasswd失败，请手动安装后重试。"
          return 1
        fi
        while true; do
          read -p "请输入用户名（留空结束）: " auth_user
          [ -z "$auth_user" ] && break
          read -s -p "请输入密码: " auth_pass; echo
          if [ -f "$htpasswd_file" ]; then
            htpasswd -b "$htpasswd_file" "$auth_user" "$auth_pass"
          else
            htpasswd -bc "$htpasswd_file" "$auth_user" "$auth_pass"
          fi
        done
        chmod 644 "$htpasswd_file"
        # 只在443的server/location块插入auth_basic，80端口server块不插入
        awk -v f="$htpasswd_file_abs" '
        BEGIN{in443=0; inloc=0}
        /server[[:space:]]*{/{srv++}
        /listen[[:space:]]+443/ {in443=1}
        /listen[[:space:]]+80/ {in443=0}
        /server_name/ {if (in443==1) sn=1}
        /location[[:space:]]*\/[[:space:]]*{/ {
          print;
          if (in443==1 && sn==1 && !inloc) {
            print "        auth_basic \"Protected\";\n        auth_basic_user_file " f ";"
          }
          inloc=1;
          next
        }
        /auth_basic/ {if (in443==1 && inloc==1) next}
        /^}/ {inloc=0}
        {print}
        ' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
        echo "已为 $server_name 启用多用户密码访问保护（仅限443端口）。"
      else
        # 黑白名单访问
        echo "1. 白名单（只允许这些IP访问）"
        echo "2. 黑名单（拒绝这些IP访问）"
        read -p "请选择模式: " list_mode
        read -p "请输入IP（多个用逗号分隔）: " ip_list
        ip_rules=""
        IFS=',' read -ra ips <<< "$ip_list"
        for ip in "${ips[@]}"; do
          ip=$(echo "$ip" | xargs)
          if [[ $list_mode == 1 ]]; then
            ip_rules+="        allow $ip;\n"
          else
            ip_rules+="        deny $ip;\n"
          fi
        done
        if [[ $list_mode == 1 ]]; then
          ip_rules+="        deny all;\n"
        else
          ip_rules+="        allow all;\n"
        fi
        # 先清理 location / 内所有 allow/deny/satisfy，再插入新规则
        awk -v rules="$ip_rules" '
        BEGIN{inloc=0}
        /location[[:space:]]*\/[[:space:]]*{/ {
          print; print rules; inloc=1; next
        }
        inloc && (/^[[:space:]]*allow[[:space:]]/ || /^[[:space:]]*deny[[:space:]]/ || /^[[:space:]]*satisfy[[:space:]]/) { next }
        /^}/ {inloc=0}
        {print}
        ' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
        echo "已为 $server_name 启用IP访问控制。"
      fi
      auto_fix_nginx
      gentle_nginx_reload
    elif [[ $enc_mode == 3 ]]; then
      idx=1
      for conf in $PROXY_CONF/*.conf; do
        [ -e "$conf" ] || continue
        server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
        printf "%2d. %s\n" "$idx" "$server_name"
        idx=$((idx+1))
      done
      read -p "请输入要操作的域名序号: " site_idx
      conf_file=$(get_conf_by_index "$site_idx")
      if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
        echo "无效序号。"
        return
      fi
      server_name=$(grep -m1 'server_name' "$conf_file" | awk '{print $2}' | sed 's/;//')
      htpasswd_file="$PROXY_CONF/$server_name.htpasswd"
      echo "1. 关闭密码访问"
      echo "2. 重置密码访问（清除所有访问控制）"
      echo "3. 返回上一级"
      read -p "请选择操作: " sub_choice
      if [[ $sub_choice == 1 ]]; then
        # 删除auth_basic相关配置
        awk '/server[[:space:]]*{/{srv++} /listen[[:space:]]+443/ {in443=1} /listen[[:space:]]+80/ {in443=0} /server_name/ {if (in443==1) sn=1} /location[[:space:]]*\/[[:space:]]*{/ {print; inloc=1; next} /auth_basic/ {if (in443==1 && inloc==1) next} /^}/ {inloc=0} {print}' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
        [ -f "$htpasswd_file" ] && rm -f "$htpasswd_file"
        echo "已关闭 $server_name 的密码访问保护。"
      elif [[ $sub_choice == 2 ]]; then
        awk 'BEGIN{inloc=0} /location[[:space:]]*\/[[:space:]]*{/ {print; inloc=1; next} inloc && (/^[[:space:]]*auth_basic/ || /^[[:space:]]*auth_basic_user_file/ || /^[[:space:]]*allow[[:space:]]/ || /^[[:space:]]*deny[[:space:]]/ || /^[[:space:]]*satisfy[[:space:]]/) {next} /^}/ {inloc=0} {print}' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
        [ -f "$htpasswd_file" ] && rm -f "$htpasswd_file"
        echo "已重置 $server_name 的所有访问控制。"
      else
        echo "返回上一级。"
        return
      fi
      auto_fix_nginx
      gentle_nginx_reload
      return
    elif [[ $enc_mode == 4 ]]; then
      idx=1
      for conf in $PROXY_CONF/*.conf; do
        [ -e "$conf" ] || continue
        server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
        printf "%2d. %s\n" "$idx" "$server_name"
        idx=$((idx+1))
      done
      read -p "请输入要操作的域名序号: " site_idx
      conf_file=$(get_conf_by_index "$site_idx")
      if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
        echo "无效序号。"
        return
      fi
      server_name=$(grep -m1 'server_name' "$conf_file" | awk '{print $2}' | sed 's/;//')
      echo "1. 关闭黑白名单访问"
      echo "2. 重置黑白名单访问（清除所有访问控制）"
      echo "3. 返回上一级"
      read -p "请选择操作: " sub_choice
      if [[ $sub_choice == 1 ]]; then
        sed -i '/^[[:space:]]*allow[[:space:]]/d;/^[[:space:]]*deny[[:space:]]/d;/^[[:space:]]*satisfy[[:space:]]/d' "$conf_file"
        echo "已关闭 $server_name 的黑白名单访问控制。"
      elif [[ $sub_choice == 2 ]]; then
        awk 'BEGIN{inloc=0} /location[[:space:]]*\/[[:space:]]*{/ {print; inloc=1; next} inloc && (/^[[:space:]]*auth_basic/ || /^[[:space:]]*auth_basic_user_file/ || /^[[:space:]]*allow[[:space:]]/ || /^[[:space:]]*deny[[:space:]]/ || /^[[:space:]]*satisfy[[:space:]]/) {next} /^}/ {inloc=0} {print}' "$conf_file" > "$conf_file.tmp" && mv "$conf_file.tmp" "$conf_file"
        htpasswd_file="$PROXY_CONF/$server_name.htpasswd"
        [ -f "$htpasswd_file" ] && rm -f "$htpasswd_file"
        echo "已重置 $server_name 的所有访问控制。"
      else
        echo "返回上一级。"
        return
      fi
      auto_fix_nginx
      gentle_nginx_reload
      return
    else
      echo "无效选项。"
    fi
    return
  fi
  if [[ $mode == 4 ]]; then
    # 静态网页反代流程
    read -p "请输入要绑定的域名: " server_name
    static_dir="/usr/local/nginx/html/$server_name"
    mkdir -p "$static_dir"
    echo "[信息] 已为你创建静态网页目录: $static_dir"
    echo "请将你的静态网页文件（如index.html等）放入该目录。"
    read -p "是否已经放入静态文件？(y/N): " static_ready
    if [[ $static_ready == "y" || $static_ready == "Y" ]]; then
      conf_file="$PROXY_CONF/$server_name.conf"
      read -p "请输入本地监听端口: " listen_port
      read -p "是否开启SSL(https)? (y/N): " enable_ssl
      force_https="n"
      # 自动检测所有 index*.html 文件，生成 index 指令
      index_files=$(ls "$static_dir"/index*.html 2>/dev/null | xargs -n1 basename | tr '\n' ' ')
      [ -z "$index_files" ] && index_files="index.html index.htm"
      index_line="index $index_files;"
      if [[ $enable_ssl == "y" || $enable_ssl == "Y" ]]; then
        read -p "是否开启强制https? (y/N): " force_https
        # 检测已有SSL证书用于开启HTTPS
        if ensure_ssl_cert "$server_name"; then
          ssl_cert="/etc/nginx/ssl/$server_name.crt"
          ssl_key="/etc/nginx/ssl/$server_name.key"
          if [[ -f "$ssl_cert" && -f "$ssl_key" ]]; then
            echo "[信息] 使用标准安装路径的证书。"
          elif cert_dir=$(detect_certbot_cert "$server_name"); then
            ssl_cert="$cert_dir/fullchain.pem"
            ssl_key="$cert_dir/privkey.pem"
            echo "[信息] 使用certbot证书。"
          elif cert_dir=$(detect_acme_cert "$server_name"); then
            if [ -f "$cert_dir/fullchain.cer" ] && [ -f "$cert_dir/$server_name.key" ]; then
              ssl_cert="$cert_dir/fullchain.cer"
              ssl_key="$cert_dir/$server_name.key"
              echo "[信息] 使用acme.sh原始证书。"
            else
              echo "[错误] 未找到acme.sh证书文件。"
              return 1
            fi
          else
            echo "[错误] 未能检测到有效证书。"
            return 1
          fi
          if [[ $force_https == "y" || $force_https == "Y" ]]; then
            cat > "$conf_file" <<EOF
server {
    listen $listen_port;
    server_name $server_name;
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl;
    server_name $server_name;
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    root $static_dir;
    $index_line
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
          else
            cat > "$conf_file" <<EOF
server {
    listen $listen_port;
    server_name $server_name;
    root $static_dir;
    $index_line
    location / {
        try_files \$uri \$uri/ =404;
    }
}
server {
    listen 443 ssl;
    server_name $server_name;
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    root $static_dir;
    $index_line
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
          fi
          echo "已生成带SSL的静态网页反代配置: $conf_file"
        else
          echo "未能成功检测或申请SSL证书，已中止SSL配置。"
          return 1
        fi
      else
        cat > "$conf_file" <<EOF
server {
    listen $listen_port;
    server_name $server_name;
    root $static_dir;
    $index_line
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        echo "已生成静态网页反代配置: $conf_file"
      fi
      auto_fix_nginx
      gentle_nginx_reload
      echo "[完成] 你的静态网页已可通过 http://$server_name:$listen_port 访问。"
    else
      echo "请先将静态文件放入 $static_dir 后再配置反代。"
      return
    fi
    return
  fi
  if [[ $mode == 6 ]]; then
    # 防盗链设置
    idx=1
    for conf in $PROXY_CONF/*.conf; do
      [ -e "$conf" ] || continue
      server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
      printf "%2d. %s\n" "$idx" "$server_name"
      idx=$((idx+1))
    done
    read -p "请选择要设置防盗链的站点序号: " site_idx
    conf_file=$(get_conf_by_index "$site_idx")
    if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
      echo "无效序号。"; return
    fi
    echo "1. 添加防盗链规则"
    echo "2. 删除防盗链规则"
    echo "3. 返回上一级"
    read -p "请选择操作: " hotlink_op
    if [[ $hotlink_op == 1 ]]; then
      read -p "请输入允许的域名（空格分隔，留空仅允许本站）: " allowed_domains
      if [ -n "$allowed_domains" ]; then
        referers="none blocked server_names $allowed_domains"
      else
        referers="none blocked server_names"
      fi
      # 使用新的防盗链管理器
      script_dir="$(dirname "$0")"
      if python3 "$script_dir/hotlink-manager.py" "$conf_file" "add" "$referers"; then
        echo "✅ 防盗链规则添加成功"
      else
        echo "❌ 防盗链规则添加失败"
        return 1
      fi
    elif [[ $hotlink_op == 2 ]]; then
      # 使用新的防盗链管理器
      script_dir="$(dirname "$0")"
      if python3 "$script_dir/hotlink-manager.py" "$conf_file" "remove"; then
        echo "✅ 防盗链规则删除成功"
      else
        echo "❌ 防盗链规则删除失败"
        return 1
      fi
    else
      echo "返回上一级。"; return
    fi
    auto_fix_nginx; gentle_nginx_reload; return
  fi
  if [[ $mode == 7 ]]; then
    # 流量限制
    idx=1
    for conf in $PROXY_CONF/*.conf; do
      [ -e "$conf" ] || continue
      server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
      printf "%2d. %s\n" "$idx" "$server_name"
      idx=$((idx+1))
    done
    read -p "请选择要设置流量限制的站点序号: " site_idx
    conf_file=$(get_conf_by_index "$site_idx")
    if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
      echo "无效序号。"; return
    fi
    echo "1. 添加流量限制"
    echo "2. 删除流量限制"
    echo "3. 返回上一级"
    read -p "请选择操作: " limit_op
    if [[ $limit_op == 1 ]]; then
      echo "请选择流量限制类型："
      echo "1. 基础限制（每秒10请求，并发5连接，1MB请求大小）"
      echo "2. 中等限制（每秒5请求，并发3连接，512KB请求大小）"
      echo "3. 严格限制（每秒2请求，并发1连接，256KB请求大小）"
      echo "4. 自定义限制"
      read -p "请选择: " limit_type
      
      case $limit_type in
        1)
          req_limit=10
          conn_limit=5
          body_size_limit=1024
          ;;
        2)
          req_limit=5
          conn_limit=3
          body_size_limit=512
          ;;
        3)
          req_limit=2
          conn_limit=1
          body_size_limit=256
          ;;
        4)
          read -p "请输入每秒请求限制数: " req_limit
          read -p "请输入每个IP的并发连接数限制: " conn_limit
          read -p "请输入请求大小限制(KB，默认1024): " body_size_limit
          body_size_limit=${body_size_limit:-1024}
          ;;
        *)
          echo "无效选择，使用基础限制"
          req_limit=10
          conn_limit=5
          body_size_limit=1024
          ;;
      esac
      
      # 使用新的流量限制管理器（自动修复重复配置）
      script_dir="$(dirname "$0")"
      echo "正在添加流量限制规则..."
      if python3 "$script_dir/rate-limit-manager.py" "$conf_file" "add" "$req_limit" "$conn_limit" "$body_size_limit"; then
        echo "✅ 流量限制规则添加成功"
      else
        echo "❌ 流量限制规则添加失败"
        return 1
      fi
    elif [[ $limit_op == 2 ]]; then
      # 使用新的流量限制管理器（自动修复重复配置）
      script_dir="$(dirname "$0")"
      echo "正在删除流量限制规则..."
      if python3 "$script_dir/rate-limit-manager.py" "$conf_file" "remove"; then
        echo "✅ 流量限制规则删除成功"
      else
        echo "❌ 流量限制规则删除失败"
        return 1
      fi
    else
      echo "返回上一级。"; return
    fi
    auto_fix_nginx; gentle_nginx_reload; return
  fi
  read -p "请输入本地监听端口: " listen_port
  case $mode in
    1)
      read -p "请输入本机目标端口: " target_port
      proxy_pass="http://127.0.0.1:$target_port";;
    2)
      read -p "请输入目标公网IP: " target_ip
      read -p "请输入目标端口: " target_port
      proxy_pass="http://$target_ip:$target_port";;
    3)
      read -p "请输入目标域名: " target_domain
      # 验证域名是否可解析
      if ! nslookup "$target_domain" >/dev/null 2>&1; then
        echo "⚠️  警告：无法解析域名 $target_domain，但将继续配置。"
        read -p "是否继续？(y/N): " continue_anyway
        if [[ $continue_anyway != "y" && $continue_anyway != "Y" ]]; then
          return 1
        fi
      else
        echo "✅ 域名解析正常：$target_domain"
      fi
      # 询问是否使用HTTPS
      read -p "目标是否使用HTTPS？(y/N): " use_https
      if [[ $use_https == "y" || $use_https == "Y" ]]; then
        proxy_pass="https://$target_domain"
      else
        proxy_pass="http://$target_domain"
      fi
      ;;
    *)
      echo "无效选项"; return;;
  esac
  read -p "请输入域名: " server_name
  conf_file="$PROXY_CONF/$server_name.conf"
  read -p "是否开启SSL(https)? (y/N): " enable_ssl
  force_https="n"
  if [[ $enable_ssl == "y" || $enable_ssl == "Y" ]]; then
    read -p "是否开启强制https? (y/N): " force_https
    # 检测已有SSL证书用于开启HTTPS
    if ensure_ssl_cert "$server_name"; then
      # 优先使用标准安装路径
      ssl_cert="/etc/nginx/ssl/$server_name.crt"
      ssl_key="/etc/nginx/ssl/$server_name.key"
      if [[ -f "$ssl_cert" && -f "$ssl_key" ]]; then
        echo "[信息] 使用标准安装路径的证书。"
      elif cert_dir=$(detect_certbot_cert "$server_name"); then
        ssl_cert="$cert_dir/fullchain.pem"
        ssl_key="$cert_dir/privkey.pem"
        echo "[信息] 使用certbot证书。"
      elif cert_dir=$(detect_acme_cert "$server_name"); then
        if [ -f "$cert_dir/fullchain.cer" ] && [ -f "$cert_dir/$server_name.key" ]; then
          ssl_cert="$cert_dir/fullchain.cer"
          ssl_key="$cert_dir/$server_name.key"
          echo "[信息] 使用acme.sh原始证书。"
        else
          echo "[错误] 未找到acme.sh证书文件。"
          return 1
        fi
      else
        echo "[错误] 未能检测到有效证书。"
        return 1
      fi
      # 生成配置
      if [[ $force_https == "y" || $force_https == "Y" ]]; then
        cat > "$conf_file" <<EOF
server {
    listen $listen_port;
    server_name $server_name;
    location / {
        return 301 https://\$host\$request_uri;
    }
}
server {
    listen 443 ssl;
    server_name $server_name;
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    location / {
        proxy_pass $proxy_pass;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
      else
        cat > "$conf_file" <<EOF
server {
    listen $listen_port;
    server_name $server_name;
    location / {
        proxy_pass $proxy_pass;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
server {
    listen 443 ssl;
    server_name $server_name;
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    location / {
        proxy_pass $proxy_pass;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
      fi
      echo "已生成带SSL的配置: $conf_file"
    else
      echo "未能成功检测或申请SSL证书，已中止SSL配置。"
      return 1
    fi
  else
    cat > "$conf_file" <<EOF
server {
    listen $listen_port;
    server_name $server_name;
    location / {
        proxy_pass $proxy_pass;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    echo "已生成普通配置: $conf_file"
  fi
  # 自动修复并重载nginx
  auto_fix_nginx
  echo ""
  echo "========= 配置信息 ========="
  echo "域名: $server_name"
  echo "监听端口: $listen_port"
  echo "反代目标: $proxy_pass"
  echo "配置文件: $conf_file"
  echo "============================"
  # 自动修复并重载nginx
  auto_fix_nginx
  gentle_nginx_reload
}

function get_conf_by_index() {
  # $1为序号，返回配置文件路径
  local idx=$1
  local i=1
  for conf in $PROXY_CONF/*.conf; do
    [ -e "$conf" ] || continue
    if [[ $i -eq $idx ]]; then
      echo "$conf"
      return 0
    fi
    i=$((i+1))
  done
  return 1
}

function edit_proxy() {
  read -p "请输入要管理的站点序号: " idx
  conf_file=$(get_conf_by_index "$idx")
  if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
    echo "无效序号。"
    return
  fi
  server_name=$(grep -m1 'server_name' "$conf_file" | awk '{print $2}' | sed 's/;//' | sed 's/(.*)//')
  while true; do
    echo "========= 反向代理高级管理 ========="
    echo "1. 修改脚本定义配置"
    echo "2. 手动编辑配置"
    echo "0. 返回上一级菜单"
    read -p "请选择操作: " subchoice
    case $subchoice in
      1)
        echo "当前配置如下："
        cat "$conf_file"
        echo "--- 开始修改 ---"
        rm -f "$conf_file"
        add_proxy
        echo "如需恢复原配置，请重新添加。"
        auto_fix_nginx
        gentle_nginx_reload
        ;;
      2)
        echo "请选择编辑器："
        echo "1. nano"
        echo "2. vim"
        read -p "请输入选项: " editor_choice
        if [[ $editor_choice == 1 ]]; then
          nano "$conf_file"
        else
          if ! command -v vim >/dev/null 2>&1; then
            echo "未检测到vim，正在尝试自动安装..."
            if command -v apt >/dev/null 2>&1; then
              apt update && apt install -y vim
            elif command -v yum >/dev/null 2>&1; then
              yum install -y vim
            else
              echo "请手动安装vim（apt install vim 或 yum install vim）后重试。"
              return 1
            fi
          fi
          if ! command -v vim >/dev/null 2>&1; then
            echo "自动安装vim失败，请手动安装后重试。"
            return 1
          fi
          vim "$conf_file"
        fi
        auto_fix_nginx
        gentle_nginx_reload
        ;;
      0) break;;
      *) echo "无效选项";;
    esac
  done
}

function delete_proxy() {
  read -p "请输入要删除的站点序号: " idx
  conf_file=$(get_conf_by_index "$idx")
  if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
    echo "无效序号。"
    return
  fi
  # 判断是否为静态站点
  if ! grep -q 'proxy_pass' "$conf_file"; then
    # 更智能地查找root目录，支持多空格、tab、单双引号、等号等
    root_dir=$(grep -E '^[[:space:]]*root[[:space:]]+' "$conf_file" | head -n1 | sed -E "s/^[[:space:]]*root[[:space:]]+([=]*)[[:space:]]*[\"'']?([^;\"'']+)[\"'']?;.*/\\2/" | tr -d "\"'")
    echo "调试信息：配置文件=$conf_file，提取到的root目录=$root_dir"
    if [ -n "$root_dir" ] && [ -d "$root_dir" ]; then
      read -p "检测到该站点为静态站点，是否同时删除静态网页目录 $root_dir ? (y/N): " yn
      if [[ $yn == "y" || $yn == "Y" ]]; then
        rm -rf "$root_dir"
        echo "已删除静态网页目录: $root_dir"
      else
        echo "已保留静态网页目录: $root_dir"
      fi
    fi
  fi
  rm -f "$conf_file"
  echo "已删除: $conf_file"
  auto_fix_nginx
  gentle_nginx_reload
}

function toggle_ssl() {
  list_sites
  read -p "请输入要操作的server_name: " server_name
  conf_file="$PROXY_CONF/$server_name.conf"
  if [ ! -f "$conf_file" ]; then
    echo "未找到该站点配置。"
    exit 1
  fi
  if grep -q 'listen 443 ssl;' "$conf_file"; then
    # 取消SSL
    awk '/listen 443 ssl;/{flag=1} /server \/\/{if(flag){flag=0;next}} !flag' "$conf_file" > "$conf_file.tmp"
    mv "$conf_file.tmp" "$conf_file"
    echo "已取消SSL(https)配置。"
    # 自动修复并重载nginx
    auto_fix_nginx
    gentle_nginx_reload
  else
    # 开启SSL
    read -p "请输入SSL证书路径（如 /etc/letsencrypt/live/$server_name/fullchain.pem）: " ssl_cert
    read -p "请输入SSL私钥路径（如 /etc/letsencrypt/live/$server_name/privkey.pem）: " ssl_key
    if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
      echo "证书路径或私钥路径不能为空，已取消操作。"
      return 1
    fi
    cat >> "$conf_file" <<EOF

server {
    listen 443 ssl;
    server_name $server_name;
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    location / {
        proxy_pass http://127.0.0.1:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    echo "已开启SSL(https)配置。"
    # 自动修复并重载nginx
    auto_fix_nginx
    gentle_nginx_reload
  fi
}

# 自动修复nginx问题
function auto_fix_nginx() {
  # 检查并修复PID文件
  if pgrep -x nginx >/dev/null 2>&1; then
    local nginx_pid=$(pgrep -x nginx | head -1)
    if [ -n "$nginx_pid" ]; then
      echo "$nginx_pid" > /usr/local/nginx/logs/nginx.pid 2>/dev/null || true
      echo "已修复nginx PID文件: $nginx_pid"
    fi
  else
    # 如果nginx未运行，清理PID文件
    if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
      rm -f /usr/local/nginx/logs/nginx.pid
      echo "已清理无效的nginx PID文件"
    fi
  fi
  
  # 检查并修复配置文件
  local nginx_conf="/usr/local/nginx/conf/nginx.conf"
  local needs_fix=0
  
  # 检查是否需要添加include语句
  if [ -f "$nginx_conf" ] && ! grep -q "include /usr/local/nginx/conf/vhost/\*\.conf;" "$nginx_conf"; then
    needs_fix=1
  fi
  
  # 检查是否需要注释默认server块
  if [ -f "$nginx_conf" ] && grep -q "server_name.*localhost" "$nginx_conf"; then
    needs_fix=1
  fi
  
  if [ $needs_fix -eq 1 ]; then
    # 备份原配置
    cp "$nginx_conf" "$nginx_conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    
    # 修复配置文件：添加include语句并注释默认server块
    awk '
    /http[ \t]*{/ { http=1 }
    /http[ \t]*}/ { http=0 }
    /http[ \t]*{/ && !inc { print; print "    include /usr/local/nginx/conf/vhost/*.conf;"; inc=1; next }
    /http[ \t]*}/ && !inc { print "    include /usr/local/nginx/conf/vhost/*.conf;"; inc=1 }
    /http[ \t]*{/ { print; next }
    /http[ \t]*}/ { print; next }
    /http/ { print; next }
    /^\s*server\s*{/ && http {
      print "#server {"; inserver=1; next
    }
    /}/ && inserver {
      print "#}"; inserver=0; next
    }
    { if (inserver) print "#"$0; else print $0 }
    ' "$nginx_conf" > "$nginx_conf.tmp" 2>/dev/null && mv "$nginx_conf.tmp" "$nginx_conf" 2>/dev/null || true
    
    echo "已修复nginx配置文件：添加了vhost include语句并注释了默认server块"
  fi
  
  # 测试配置
  local nginx_bin="/usr/local/nginx/sbin/nginx"
  if [ -x "$nginx_bin" ]; then
    $nginx_bin -t 2>/dev/null || nginx -t 2>/dev/null
  else
    nginx -t 2>/dev/null
  fi
  
  if [ $? -eq 0 ]; then
    echo "nginx配置测试通过"
  else
    echo "警告：nginx配置测试失败，请检查配置文件"
  fi
}

# 优化Nginx停止逻辑
function stop_nginx_safe() {
  if pgrep -x nginx >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1; then
      systemctl stop nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s stop || nginx -s stop
    else
      /usr/local/nginx/sbin/nginx -s stop || nginx -s stop
    fi
    # 再次检测，若还在则kill
    if pgrep -x nginx >/dev/null 2>&1; then
      pkill -9 nginx
    fi
  fi
}

case "$1" in
  add|"") add_proxy;;
  delete) delete_proxy;;
  edit) edit_proxy;;
  ssl) toggle_ssl;;
  *) echo "用法: $0 [add|delete|edit|ssl]"; exit 1;;
esac 