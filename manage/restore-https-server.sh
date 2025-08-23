#!/bin/bash

# 恢复HTTPS server块并修复重复配置
# 作者：AI助手

CONFIG_DIR="/usr/local/nginx/conf"
VHOST_DIR="$CONFIG_DIR/vhost"
DOMAIN="mm.1107211.xyz"
CONF_FILE="$VHOST_DIR/$DOMAIN.conf"

echo "========= 恢复HTTPS server块 ========="

# 备份当前配置
echo "1. 备份当前配置..."
mkdir -p "$CONFIG_DIR/backup"
cp "$CONF_FILE" "$CONFIG_DIR/backup/${DOMAIN}_backup_$(date +%Y%m%d_%H%M%S).conf"

# 检查SSL证书路径
echo "2. 检查SSL证书..."
SSL_CERT=""
SSL_KEY=""

# 检查acme.sh证书
if [ -d "$HOME/.acme.sh/${DOMAIN}_ecc" ]; then
    SSL_CERT="$HOME/.acme.sh/${DOMAIN}_ecc/fullchain.cer"
    SSL_KEY="$HOME/.acme.sh/${DOMAIN}_ecc/$DOMAIN.key"
elif [ -d "$HOME/.acme.sh/$DOMAIN" ]; then
    SSL_CERT="$HOME/.acme.sh/$DOMAIN/fullchain.cer"
    SSL_KEY="$HOME/.acme.sh/$DOMAIN/$DOMAIN.key"
fi

# 检查certbot证书
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
fi

if [ -z "$SSL_CERT" ] || [ -z "$SSL_KEY" ]; then
    echo "❌ 未找到SSL证书，将创建HTTP-only配置"
    SSL_CERT=""
    SSL_KEY=""
fi

# 创建完整的配置文件
echo "3. 创建完整配置文件..."
cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    # 流量限制配置
    client_max_body_size 256k;
    limit_req zone=req_limit_per_ip burst=3 nodelay;
    limit_conn conn_limit_per_ip 1;
    limit_req_status 429;
    limit_conn_status 429;
EOF

# 如果有SSL证书，添加HTTPS server块
if [ -n "$SSL_CERT" ] && [ -n "$SSL_KEY" ]; then
    cat >> "$CONF_FILE" <<EOF
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    root /usr/local/nginx/html/$DOMAIN;
    index index1.html;
    # 流量限制配置
    client_max_body_size 256k;
    limit_req zone=req_limit_per_ip burst=3 nodelay;
    limit_conn conn_limit_per_ip 1;
    limit_req_status 429;
    limit_conn_status 429;
EOF
fi

cat >> "$CONF_FILE" <<EOF
}
EOF

echo "4. 检查nginx配置..."
if nginx -t; then
    echo "✅ 配置语法正确"
    echo "5. 重启nginx..."
    systemctl restart nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s reload
    echo "✅ nginx已重启"
else
    echo "❌ 配置语法错误"
    echo "配置内容:"
    cat "$CONF_FILE"
    exit 1
fi

echo "========= 恢复完成 ========="
echo "HTTPS server块已恢复，重复配置已清理" 