 #!/bin/bash
# Nginx管理相关函数

stop_nginx_safe() {
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

reload_nginx_safe() {
  if pgrep -x nginx >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1; then
      systemctl reload nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s reload || nginx -s reload
    else
      /usr/local/nginx/sbin/nginx -s reload || nginx -s reload
    fi
  fi
}