#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

function nginx_status() {
  if pgrep -x nginx >/dev/null 2>&1; then
    echo -e "\033[32mNginx状态：运行中\033[0m"
  else
    echo -e "\033[31mNginx状态：未运行\033[0m"
  fi
}

function show_sites() {
  NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
  if [ ! -d "$NGINX_CONF_DIR" ]; then
    echo "当前无已配置站点。"
    return
  fi
  local line_len=90
  local line
  line=$(printf '%.0s=' $(seq 1 $line_len))
  printf "%-4s %-25s %-10s %-8s %-8s %-8s %-18s %-8s\n" "序号" "站点" "目标端口" "类型" "状态" "HTTPS" "证书颁发机构" "剩余天数"
  echo "$line"
  idx=1
  for conf in $NGINX_CONF_DIR/*.conf; do
    [ -e "$conf" ] || continue
    server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
    proxy_pass=$(grep -m1 'proxy_pass' "$conf" | awk '{print $2}' | sed 's/;//')
    # 判断类型
    if ! grep -q 'proxy_pass' "$conf"; then
      type="静态网页"
      target_port="-"
    else
      # 提取目标端口
      if [[ $proxy_pass =~ ([0-9]+)$ ]]; then
        target_port="${BASH_REMATCH[1]}"
      else
        target_port="-"
      fi
      if [[ $proxy_pass == http://127.0.0.1* ]]; then
        type="本机端口"
      elif [[ $proxy_pass =~ ^http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        type="公网IP"
      else
        type="域名"
      fi
    fi
    # 检查目标端口运行情况
    if [[ $target_port != "-" ]] && ss -lnt | grep -q ":$target_port "; then
      status="运行中"
    else
      status="未监听"
    fi
    # 检查HTTPS及证书
    https="否"
    ca="-"
    days="-"
    ssl_cert=$(grep -m1 'ssl_certificate' "$conf" | awk '{print $2}' | sed 's/;//')
    if [[ -n "$ssl_cert" && ! "$ssl_cert" =~ ^# && -f "$ssl_cert" ]]; then
      https="是"
      # 优先取CN，没有CN取O，没有O取issuer全部
      issuer=$(openssl x509 -in "$ssl_cert" -noout -issuer 2>/dev/null)
      ca=$(echo "$issuer" | sed -n 's/.*CN=\([^,]*\).*/\1/p')
      if [ -z "$ca" ]; then
        ca=$(echo "$issuer" | sed -n 's/.*O=\([^,]*\).*/\1/p')
      fi
      [ -z "$ca" ] && ca="$issuer"
      [ -z "$ca" ] && ca="-"
      # 获取剩余天数
      end_date=$(openssl x509 -in "$ssl_cert" -noout -enddate 2>/dev/null | cut -d= -f2)
      if [[ -n "$end_date" ]]; then
        end_ts=$(date -d "$end_date" +%s 2>/dev/null)
        now_ts=$(date +%s)
        if [[ -n "$end_ts" && $end_ts -gt $now_ts ]]; then
          days=$(( (end_ts-now_ts)/86400 ))
        else
          days="过期"
        fi
      fi
    fi
    printf "%-4s %-25s %-10s %-8s %-8s %-8s %-18s %-8s\n" "$idx" "$server_name" "$target_port" "$type" "$status" "$https" "$ca" "$days"
    idx=$((idx+1))
  done
  echo "$line"
}

function auto_fix_nginx() {
  echo "========= 自动修复nginx配置 ========="
  
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
    # 使用awk修复配置，确保只保留一行include
    awk '
    BEGIN { http=0; inc=0; in_default_server=0; level=0 }
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
    /^[[:space:]]*include[[:space:]]+\/usr\/local\/nginx\/conf\/vhost\/\*\.conf;/ {
      if (!inc && http) {
        print;
        inc=1;
      }
      next;
    }
    /^[[:space:]]*server[[:space:]]*{/ && http && !in_default_server {
      if (!inc) {
        print "    include /usr/local/nginx/conf/vhost/*.conf;";
        inc=1;
      }
      in_default_server=1;
      level=1;
      print "#server {";
      next;
    }
    in_default_server {
      n_open = gsub(/{/, "{");
      n_close = gsub(/}/, "}");
      level += n_open - n_close;
      print "#" $0;
      if (level == 0) {
        in_default_server=0;
      }
      next;
    }
    {
      print $0;
    }
    ' "$nginx_conf" > "$temp_file"
    if [ $? -eq 0 ]; then
      mv "$temp_file" "$nginx_conf"
      echo "✅ 已修复nginx配置文件（去除多余include）"
    else
      echo "❌ 配置文件修复失败"
      rm -f "$temp_file"
      return 1
    fi
  else
    echo "✅ nginx配置文件无需修复"
  fi
  
  # 4. 检查端口占用
  echo "检查端口占用情况..."
  if ss -lnt | grep -q ':80 '; then
    echo "⚠️  80端口被占用，尝试停止占用进程..."
    local port_pid=$(ss -lntp | grep ':80 ' | awk '{print $6}' | sed 's/.*pid=\([0-9]*\).*/\1/' | head -1)
    if [ -n "$port_pid" ]; then
      echo "停止进程 $port_pid..."
      kill "$port_pid" 2>/dev/null || true
      sleep 2
    fi
  else
    echo "✅ 80端口空闲"
  fi
  
  # 5. 检查并修复SSL证书路径问题
  echo "检查SSL证书路径..."
  local cert_errors=$(nginx -t 2>&1 | grep -E "(certificate|key)" || true)
  if [ -n "$cert_errors" ]; then
    echo "⚠️  检测到SSL证书路径问题，正在修复..."
    
    # 检查vhost配置文件中的证书路径
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
  
  # 6. 测试配置
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
  
  # === 强制去重 include 语句 ===
  local temp_file="$nginx_conf.tmp"
  awk '
  BEGIN { http=0; inc=0 }
  /^[[:space:]]*http[[:space:]]*{/ { http=1; print; next }
  /^[[:space:]]*http[[:space:]]*}/ {
    if (!inc) {
      print "    include /usr/local/nginx/conf/vhost/*.conf;";
      inc=1;
    }
    http=0; print; next
  }
  /^[[:space:]]*include[[:space:]]+\/usr\/local\/nginx\/conf\/vhost\/\*\.conf;/ {
    if (!inc && http) { print; inc=1 }
    next
  }
  { print }
  ' "$nginx_conf" > "$temp_file" && mv "$temp_file" "$nginx_conf"
  echo "✅ 已强制去重 include 语句"
  
  echo "========= 修复完成 ========="
  return 0
}

function toggle_nginx() {
  if pgrep -x nginx >/dev/null 2>&1; then
    echo "Nginx当前正在运行，是否停止？(y/N): "
    read -r stopit
    if [[ $stopit =~ ^[Yy]$ ]]; then
      echo "正在停止nginx..."
      # 先尝试优雅停止
      nginx -s quit 2>/dev/null || nginx -s stop 2>/dev/null || systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null
      # 等待进程完全退出
      sleep 3
      # 如果还有进程，再强制停止
      if pgrep -x nginx >/dev/null 2>&1; then
        echo "强制停止剩余的nginx进程..."
        pkill -9 nginx 2>/dev/null || true
        sleep 2
      fi
      # 清理PID文件
      if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
        echo "清理nginx PID文件..."
        rm -f /usr/local/nginx/logs/nginx.pid
      fi
      echo "Nginx已停止。"
    else
      echo "操作已取消。"
    fi
  else
    echo "Nginx当前未运行，是否启动？(y/N): "
    read -r startit
    if [[ $startit =~ ^[Yy]$ ]]; then
      # 启动前自动修复
      if auto_fix_nginx; then
        echo "正在启动nginx..."
        if [ -x /usr/local/nginx/sbin/nginx ]; then
          /usr/local/nginx/sbin/nginx
        else
          nginx
        fi
        
        # 检查启动结果
        sleep 2
        if pgrep -x nginx >/dev/null 2>&1; then
          echo "✅ Nginx启动成功"
          echo "进程ID: $(pgrep -x nginx)"
        else
          echo "❌ Nginx启动失败"
          echo "请检查错误日志获取详细信息"
        fi
      else
        echo "❌ 自动修复失败，无法启动nginx"
      fi
    else
      echo "操作已取消。"
    fi
  fi
}

function list_backups() {
  BACKUP_DIR="$HOME"
  backups=( $(ls -1t $BACKUP_DIR/nginx-backup-*.tar.gz 2>/dev/null) )
  if [ ${#backups[@]} -eq 0 ]; then
    echo "当前无备份文件。"
    return 1
  fi
  echo "========= 现有备份 ========="
  for i in "${!backups[@]}"; do
    fname=$(basename "${backups[$i]}")
    printf "%2d. %s\n" "$((i+1))" "$fname"
  done
  echo "==========================="
  return 0
}

function manage_backups() {
  while true; do
    echo "========= 管理nginx备份 ========="
    echo "1. 查看备份"
    echo "2. 删除备份"
    echo "0. 返回上一级"
    read -p "请输入选项: " choice
    case $choice in
      1)
        list_backups
        ;;
      2)
        if ! list_backups; then return; fi
        read -p "请输入要删除的备份序号: " idx
        idx=$((idx-1))
        backups=( $(ls -1t $HOME/nginx-backup-*.tar.gz 2>/dev/null) )
        if [[ -z "${backups[$idx]}" ]]; then
          echo "无效序号。"
        else
          rm -f "${backups[$idx]}"
          echo "已删除: $(basename "${backups[$idx]}")"
        fi
        ;;
      0) break;;
      *) echo "无效选项";;
    esac
  done
}

function restore_nginx_menu() {
  if ! list_backups; then return; fi
  read -p "请输入要恢复的备份序号: " idx
  idx=$((idx-1))
  backups=( $(ls -1t $HOME/nginx-backup-*.tar.gz 2>/dev/null) )
  if [[ -z "${backups[$idx]}" ]]; then
    echo "无效序号。"
    return
  fi
  bash "$SCRIPT_DIR/backup/backup-nginx.sh" restore "${backups[$idx]}"
}

function manage_ssl_menu() {
  while true; do
    echo "========= SSL证书管理 ========="
    echo "1. 选择证书工具（certbot 或 acme.sh）"
    echo "2. 申请或续期证书"
    echo "3. 撤销并删除证书"
    echo "4. 开启或关闭自动续签"
    echo "5. 手动上传/填写证书"
    echo "6. 返回上一级"
    read -p "请输入选项: " choice
    case $choice in
      1)
        bash "$SCRIPT_DIR/ssl/ssl-cert.sh" select
        ;;
      2)
        bash "$SCRIPT_DIR/ssl/ssl-cert.sh" apply
        ;;
      3)
        bash "$SCRIPT_DIR/ssl/ssl-cert.sh" revoke_delete
        ;;
      4)
        bash "$SCRIPT_DIR/ssl/ssl-cert.sh" renew
        ;;
      5)
        bash "$SCRIPT_DIR/ssl/ssl-cert.sh" manual
        ;;
      6|0) break;;
      *) echo "无效选项";;
    esac
  done
}

function site_status_menu() {
  while true; do
    echo "========= 查看站点状态 ========="
    echo "1. 列出访问比较多的IP"
    echo "2. 统计站点流量"
    echo "3. 查看站点日志"
    echo "4. 访问趋势图（文本版）"
    echo "5. 热门请求URL/资源统计"
    echo "6. 安全扫描与告警"
    echo "7. 一键下载日志/流量报表"
    echo "0. 返回上一级"
    read -p "请输入选项: " subchoice
    case $subchoice in
      1)
        bash "$SCRIPT_DIR/manage/stat-top-ip.sh"
        ;;
      2)
        # 选择站点后统计流量
        NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
        idx=1
        site_list=()
        echo "========= 站点列表 ========="
        for conf in $NGINX_CONF_DIR/*.conf; do
          [ -e "$conf" ] || continue
          server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
          printf "%2d. %s\n" "$idx" "$server_name"
          site_list+=("$server_name")
          idx=$((idx+1))
        done
        read -p "请输入要统计流量的站点序号: " site_idx
        site_idx=$((site_idx-1))
        if [[ -z "${site_list[$site_idx]}" ]]; then
          echo "无效序号。"; continue
        fi
        bash "$SCRIPT_DIR/manage/stat-traffic.sh" "${site_list[$site_idx]}"
        ;;
      3)
        # 选择站点后实时查看日志
        NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
        idx=1
        site_list=()
        echo "========= 站点列表 ========="
        for conf in $NGINX_CONF_DIR/*.conf; do
          [ -e "$conf" ] || continue
          server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
          printf "%2d. %s\n" "$idx" "$server_name"
          site_list+=("$server_name")
          idx=$((idx+1))
        done
        read -p "请输入要实时查看日志的站点序号: " site_idx
        site_idx=$((site_idx-1))
        if [[ -z "${site_list[$site_idx]}" ]]; then
          echo "无效序号。"; continue
        fi
        bash "$SCRIPT_DIR/manage/realtime-log.sh" "${site_list[$site_idx]}"
        ;;
      4)
        # 访问趋势图
        NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
        idx=1
        site_list=()
        echo "========= 站点列表 ========="
        for conf in $NGINX_CONF_DIR/*.conf; do
          [ -e "$conf" ] || continue
          server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
          printf "%2d. %s\n" "$idx" "$server_name"
          site_list+=("$server_name")
          idx=$((idx+1))
        done
        read -p "请输入要查看趋势图的站点序号: " site_idx
        site_idx=$((site_idx-1))
        if [[ -z "${site_list[$site_idx]}" ]]; then
          echo "无效序号。"; continue
        fi
        bash "$SCRIPT_DIR/manage/stat-trend.sh" "${site_list[$site_idx]}"
        ;;
      5)
        # 热门请求URL/资源统计
        NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
        idx=1
        site_list=()
        echo "========= 站点列表 ========="
        for conf in $NGINX_CONF_DIR/*.conf; do
          [ -e "$conf" ] || continue
          server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
          printf "%2d. %s\n" "$idx" "$server_name"
          site_list+=("$server_name")
          idx=$((idx+1))
        done
        read -p "请输入要统计热门URL的站点序号: " site_idx
        site_idx=$((site_idx-1))
        if [[ -z "${site_list[$site_idx]}" ]]; then
          echo "无效序号。"; continue
        fi
        bash "$SCRIPT_DIR/manage/stat-hoturl.sh" "${site_list[$site_idx]}"
        ;;
      6)
        # 安全扫描与告警
        NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
        idx=1
        site_list=()
        echo "========= 站点列表 ========="
        for conf in $NGINX_CONF_DIR/*.conf; do
          [ -e "$conf" ] || continue
          server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
          printf "%2d. %s\n" "$idx" "$server_name"
          site_list+=("$server_name")
          idx=$((idx+1))
        done
        read -p "请输入要安全扫描的站点序号: " site_idx
        site_idx=$((site_idx-1))
        if [[ -z "${site_list[$site_idx]}" ]]; then
          echo "无效序号。"; continue
        fi
        bash "$SCRIPT_DIR/manage/security-scan.sh" "${site_list[$site_idx]}"
        ;;
      7)
        # 一键下载日志/流量报表
        NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
        idx=1
        site_list=()
        echo "========= 站点列表 ========="
        for conf in $NGINX_CONF_DIR/*.conf; do
          [ -e "$conf" ] || continue
          server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
          printf "%2d. %s\n" "$idx" "$server_name"
          site_list+=("$server_name")
          idx=$((idx+1))
        done
        read -p "请输入要下载报表的站点序号: " site_idx
        site_idx=$((site_idx-1))
        if [[ -z "${site_list[$site_idx]}" ]]; then
          echo "无效序号。"; continue
        fi
        bash "$SCRIPT_DIR/manage/download-report.sh" "${site_list[$site_idx]}"
        ;;
      0) break;;
      *) echo "无效选项";;
    esac
  done
}

function manage_menu() {
  while true; do
    clear
    nginx_status
    show_sites
    # 不再输出任何分割线
    echo "1. 运行/停止 Nginx"
    echo "2. 备份 Nginx"
    echo "3. 恢复 Nginx"
    echo "4. 配置反向代理"
    echo "5. 编辑反向代理"
    echo "6. 删除反向代理"
    echo "7. 管理SSL证书"
    echo "8. 管理Nginx备份"
    echo "9. 查看站点状态"
    echo "0. 退出"
    read -p "请输入选项: " choice
    case $choice in
      1) toggle_nginx;;
      2) bash "$SCRIPT_DIR/backup-nginx.sh" backup;;
      3) bash "$SCRIPT_DIR/backup-nginx.sh" restore;;
      4) bash "$SCRIPT_DIR/manage/proxy-config.sh" add;;
      5) manual_edit_proxy;;
      6) bash "$SCRIPT_DIR/manage/proxy-config.sh" delete;;
      7) manage_ssl_menu;;
      8) manage_backups;;
      9) site_status_menu;;
      0) exit 0;;
      *) echo "无效选项"; sleep 1;;
    esac
    echo "按任意键继续..."
    read -n 1
  done
}

function manual_edit_proxy() {
  NGINX_CONF_DIR="/usr/local/nginx/conf/vhost"
  idx=1
  site_list=()
  echo "========= 站点列表 ========="
  for conf in $NGINX_CONF_DIR/*.conf; do
    [ -e "$conf" ] || continue
    server_name=$(grep -m1 'server_name' "$conf" | awk '{print $2}' | sed 's/;//')
    printf "%2d. %s\n" "$idx" "$server_name"
    site_list+=("$conf")
    idx=$((idx+1))
  done
  read -p "请输入要手动编辑配置的站点序号: " site_idx
  site_idx=$((site_idx-1))
  conf_file="${site_list[$site_idx]}"
  if [[ -z "$conf_file" || ! -f "$conf_file" ]]; then
    echo "无效序号。"
    return
  fi
  echo "请选择编辑器："
  echo "1. nano"
  echo "2. vim"
  read -p "请输入选项: " editor_choice
  if [[ $editor_choice == 1 ]]; then
    if ! command -v nano >/dev/null 2>&1; then
      echo "未检测到nano，正在尝试自动安装..."
      if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y nano
      elif command -v yum >/dev/null 2>&1; then
        yum install -y nano
      else
        echo "请手动安装nano（apt install nano 或 yum install nano）后重试。"
        return 1
      fi
    fi
    if ! command -v nano >/dev/null 2>&1; then
      echo "自动安装nano失败，请手动安装后重试。"
      return 1
    fi
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
  # 自动修复并重载nginx
  if bash "$SCRIPT_DIR/manage/proxy-config.sh" auto_fix_nginx; then
    echo "已自动修复nginx配置。"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s reload || nginx -s reload
  else
    /usr/local/nginx/sbin/nginx -s reload || nginx -s reload
  fi
  echo "已重载nginx。"
}

# 启动管理菜单
manage_menu 