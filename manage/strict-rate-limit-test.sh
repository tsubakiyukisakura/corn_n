#!/bin/bash

# 严格的流量限制测试脚本

CONF_FILE="/usr/local/nginx/conf/vhost/mm.1107211.xyz.conf"

echo "========= 严格流量限制测试 ========="

# 备份原配置
cp "$CONF_FILE" "$CONF_FILE.backup.$(date +%Y%m%d%H%M%S)"

echo "正在应用更严格的流量限制配置..."

# 修改主配置文件中的rate
sed -i 's/rate=2r\/s/rate=1r\/s/' /usr/local/nginx/conf/nginx.conf

# 修改站点配置文件，使用更严格的参数
sed -i 's/burst=3/burst=1/' "$CONF_FILE"
sed -i 's/limit_conn conn_limit_per_ip 1/limit_conn conn_limit_per_ip 1;/' "$CONF_FILE"

# 添加更多限制
cat >> "$CONF_FILE" << 'EOL'
    # 额外限制
    limit_rate 1024;  # 限制每个连接的速度为1KB/s
    limit_rate_after 1k;  # 1KB后开始限制速度
EOL

# 验证配置
if nginx -t; then
    echo "✅ 配置验证通过"
    nginx -s reload
    echo "✅ 配置已重新加载"
    
    echo ""
    echo "现在测试更严格的限制..."
    echo "等待2秒后开始测试..."
    sleep 2
    
    # 测试
    for i in {1..5}; do
        response=$(curl -s -w "%{http_code}" -o /dev/null https://mm.1107211.xyz/ 2>/dev/null)
        echo "请求 $i: HTTP状态码 $response"
        sleep 0.1
    done
    
    echo ""
    echo "如果看到429状态码，说明限制生效了！"
    echo "如果还是200，可能需要检查其他配置。"
    
else
    echo "❌ 配置验证失败，恢复备份..."
    cp "$CONF_FILE.backup."* "$CONF_FILE"
    nginx -s reload
fi 