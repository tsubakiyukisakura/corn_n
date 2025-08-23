#!/bin/bash

# 快速修复重复server配置脚本
# 作者：AI助手

CONFIG_DIR="/usr/local/nginx/conf"
VHOST_DIR="$CONFIG_DIR/vhost"

echo "========= 快速修复重复server配置 ========="

# 备份配置
echo "1. 备份当前配置..."
mkdir -p "$CONFIG_DIR/backup"
cp -r "$VHOST_DIR" "$CONFIG_DIR/backup/vhost_backup_$(date +%Y%m%d_%H%M%S)"

# 显示当前重复的server
echo "2. 检查重复的server配置..."
echo "HTTP端口重复:"
grep -r "server_name.*on.*0\.0\.0\.0:80" "$VHOST_DIR" 2>/dev/null | head -10

echo "HTTPS端口重复:"
grep -r "server_name.*on.*0\.0\.0\.0:443" "$VHOST_DIR" 2>/dev/null | head -10

# 查找所有配置文件
echo "3. 清理重复配置..."
find "$VHOST_DIR" -name "*.conf" -type f | while read -r config_file; do
    echo "处理: $config_file"
    
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 简单的去重方法：保留第一个出现的server块
    awk '
    BEGIN {
        in_server = 0
        server_count = 0
        seen_names[""] = 0
    }
    
    /^[[:space:]]*server[[:space:]]*{/ {
        in_server = 1
        server_count++
        current_server = ""
        next
    }
    
    in_server {
        current_server = current_server $0 "\n"
        
        # 提取server_name
        if ($0 ~ /server_name/) {
            gsub(/[[:space:]]*server_name[[:space:]]*/, "", $0)
            gsub(/;/, "", $0)
            server_name = $0
        }
        
        # 检查server块结束
        if ($0 ~ /^[[:space:]]*}/) {
            in_server = 0
            
            # 如果是第一个server块或server_name未见过，则保留
            if (server_count == 1 || !(server_name in seen_names)) {
                seen_names[server_name] = 1
                printf "%s", current_server
            } else {
                print "// 删除重复server块: " server_name > "/dev/stderr"
            }
        }
        next
    }
    
    !in_server {
        print
    }
    ' "$config_file" > "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$config_file"
done

# 检查配置
echo "4. 检查nginx配置..."
if nginx -t; then
    echo "✓ 配置语法正确"
    echo "5. 重启nginx..."
    systemctl restart nginx 2>/dev/null || /usr/local/nginx/sbin/nginx -s reload
    echo "✓ nginx已重启"
else
    echo "✗ 配置语法错误，请检查备份文件"
    exit 1
fi

echo "========= 修复完成 ========="
echo "现在应该没有重复的server警告了" 