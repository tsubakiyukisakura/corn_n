#!/bin/bash

echo "========= 测试nginx修复功能 ========="

# 测试nginx配置
echo "1. 测试当前nginx配置..."
if nginx -t 2>/dev/null; then
    echo "✅ nginx配置正常"
else
    echo "❌ nginx配置有问题，错误信息："
    nginx -t 2>&1
fi

# 检查SSL证书路径问题
echo ""
echo "2. 检查SSL证书路径问题..."
cert_errors=$(nginx -t 2>&1 | grep -E "(certificate|key)" || true)
if [ -n "$cert_errors" ]; then
    echo "⚠️  检测到SSL证书路径问题："
    echo "$cert_errors"
else
    echo "✅ 未检测到SSL证书路径问题"
fi

# 检查vhost配置文件
echo ""
echo "3. 检查vhost配置文件..."
vhost_dir="/usr/local/nginx/conf/vhost"
if [ -d "$vhost_dir" ]; then
    echo "vhost目录存在，配置文件列表："
    for conf_file in "$vhost_dir"/*.conf; do
        [ -f "$conf_file" ] || continue
        domain=$(grep -m1 'server_name' "$conf_file" | awk '{print $2}' | sed 's/;//')
        echo "  - $(basename "$conf_file"): $domain"
        
        # 检查证书路径
        ssl_cert=$(grep -m1 'ssl_certificate' "$conf_file" | awk '{print $2}' | sed 's/;//')
        if [ -n "$ssl_cert" ]; then
            if [ -f "$ssl_cert" ]; then
                echo "    ✅ SSL证书存在: $ssl_cert"
            else
                echo "    ❌ SSL证书不存在: $ssl_cert"
            fi
        fi
    done
else
    echo "❌ vhost目录不存在"
fi

echo ""
echo "========= 测试完成 =========" 
 