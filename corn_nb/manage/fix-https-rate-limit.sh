#!/bin/bash

# 修复HTTPS端口流量限制配置

if [ $# -lt 1 ]; then
    echo "用法: $0 <配置文件路径>"
    echo "示例: $0 /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf"
    exit 1
fi

CONF_FILE="$1"

if [ ! -f "$CONF_FILE" ]; then
    echo "配置文件不存在: $CONF_FILE"
    exit 1
fi

echo "正在修复HTTPS端口的流量限制配置..."
echo "配置文件: $CONF_FILE"

# 备份原文件
cp "$CONF_FILE" "$CONF_FILE.backup.$(date +%Y%m%d%H%M%S)"

# 检查是否已经有HTTP的流量限制配置
if grep -q "# 流量限制配置" "$CONF_FILE"; then
    echo "检测到现有流量限制配置，提取参数..."
    
    # 提取现有参数
    REQ_LIMIT=$(grep "limit_req_zone" /usr/local/nginx/conf/nginx.conf | grep -o "rate=[0-9]*" | cut -d= -f2)
    CONN_LIMIT=$(grep "limit_conn conn_limit_per_ip" "$CONF_FILE" | grep -o "[0-9]*" | head -1)
    BODY_SIZE=$(grep "client_max_body_size" "$CONF_FILE" | grep -o "[0-9]*" | head -1)
    
    echo "提取的参数:"
    echo "  请求限制: ${REQ_LIMIT:-2}/秒"
    echo "  连接限制: ${CONN_LIMIT:-1}个"
    echo "  请求大小: ${BODY_SIZE:-256}KB"
    
    # 为HTTPS server块添加流量限制配置
    sed -i '/listen 443 ssl;/a\
    # 流量限制配置\
    client_max_body_size '"${BODY_SIZE:-256}"'k;\
    limit_req zone=req_limit_per_ip burst=3 nodelay;\
    limit_conn conn_limit_per_ip '"${CONN_LIMIT:-1}"';\
    limit_req_status 429;\
    limit_conn_status 429;' "$CONF_FILE"
    
    echo "✅ 已为HTTPS端口添加流量限制配置"
else
    echo "未找到现有流量限制配置，使用默认严格限制..."
    
    # 使用默认的严格限制配置
    sed -i '/listen 443 ssl;/a\
    # 流量限制配置\
    client_max_body_size 256k;\
    limit_req zone=req_limit_per_ip burst=3 nodelay;\
    limit_conn conn_limit_per_ip 1;\
    limit_req_status 429;\
    limit_conn_status 429;' "$CONF_FILE"
    
    echo "✅ 已为HTTPS端口添加默认流量限制配置"
fi

# 验证配置
echo "验证nginx配置..."
if nginx -t; then
    echo "✅ 配置验证通过"
    echo "重新加载nginx配置..."
    nginx -s reload
    echo "✅ 配置已重新加载"
else
    echo "❌ 配置验证失败，正在恢复备份..."
    cp "$CONF_FILE.backup."* "$CONF_FILE"
    echo "已恢复备份文件"
    exit 1
fi

echo ""
echo "修复完成！现在HTTPS端口也应该有流量限制了。"
echo "您可以测试一下："
echo "  curl -s -w '%{http_code}' -o /dev/null https://mm.1107211.xyz/" 