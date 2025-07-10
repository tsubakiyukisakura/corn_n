#!/bin/bash

# 快速修复重复指令脚本
# 作者：AI助手
# 功能：修复nginx配置中的重复指令问题

CONFIG_DIR="/usr/local/nginx/conf"
VHOST_DIR="$CONFIG_DIR/vhost"

echo "========= 修复重复指令 ========="

# 备份配置
echo "1. 备份当前配置..."
mkdir -p "$CONFIG_DIR/backup"
cp -r "$VHOST_DIR" "$CONFIG_DIR/backup/vhost_backup_$(date +%Y%m%d_%H%M%S)"

# 查找并修复重复的流量限制相关指令
# 支持：client_max_body_size、limit_req、limit_conn、limit_req_status、limit_conn_status

echo "2. 修复重复的流量限制相关指令..."
find "$VHOST_DIR" -name "*.conf" -type f | while read -r config_file; do
    echo "处理文件: $config_file"
    
    temp_file=$(mktemp)
    
    awk '
    BEGIN {
        in_server = 0
        seen_body_size = 0
        seen_limit_req = 0
        seen_limit_conn = 0
        seen_limit_req_status = 0
        seen_limit_conn_status = 0
    }
    
    /^[[:space:]]*server[[:space:]]*{/ {
        in_server = 1
        seen_body_size = 0
        seen_limit_req = 0
        seen_limit_conn = 0
        seen_limit_req_status = 0
        seen_limit_conn_status = 0
        print
        next
    }
    
    /^[[:space:]]*}/ {
        in_server = 0
        print
        next
    }
    
    in_server {
        if ($0 ~ /client_max_body_size/) {
            if (!seen_body_size) {
                print
                seen_body_size = 1
            } else {
                print "// 删除重复的client_max_body_size指令"
            }
        } else if ($0 ~ /limit_req zone=/) {
            if (!seen_limit_req) {
                print
                seen_limit_req = 1
            } else {
                print "// 删除重复的limit_req指令"
            }
        } else if ($0 ~ /limit_conn conn_limit_per_ip/) {
            if (!seen_limit_conn) {
                print
                seen_limit_conn = 1
            } else {
                print "// 删除重复的limit_conn指令"
            }
        } else if ($0 ~ /limit_req_status/) {
            if (!seen_limit_req_status) {
                print
                seen_limit_req_status = 1
            } else {
                print "// 删除重复的limit_req_status指令"
            }
        } else if ($0 ~ /limit_conn_status/) {
            if (!seen_limit_conn_status) {
                print
                seen_limit_conn_status = 1
            } else {
                print "// 删除重复的limit_conn_status指令"
            }
        } else {
            print
        }
        next
    }
    
    {
        print
    }
    ' "$config_file" > "$temp_file"
    
    mv "$temp_file" "$config_file"
    echo "完成处理: $config_file"
done

# 检查配置语法
echo "3. 检查nginx配置语法..."
if nginx -t; then
    echo "✅ 配置语法正确"
    echo "4. 重启nginx..."
    systemctl restart nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s reload
    echo "✅ nginx已重启"
else
    echo "❌ 配置语法错误，请检查备份文件"
    exit 1
fi

echo "========= 修复完成 ========="
echo "重复指令问题已解决" 