#!/bin/bash

# 清理重复的nginx配置脚本
# 作者：AI助手
# 功能：检测并清理nginx配置中的重复server块

CONFIG_DIR="/usr/local/nginx/conf"
VHOST_DIR="$CONFIG_DIR/vhost"
BACKUP_DIR="$CONFIG_DIR/backup"

echo "========= 清理重复nginx配置 ========="

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份当前配置
echo "1. 备份当前配置..."
cp -r "$VHOST_DIR" "$BACKUP_DIR/vhost_$(date +%Y%m%d_%H%M%S)"

# 查找所有配置文件
echo "2. 扫描配置文件..."
find "$VHOST_DIR" -name "*.conf" -type f | while read -r config_file; do
    echo "处理文件: $config_file"
    
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 使用awk去重server块
    awk '
    BEGIN {
        in_server = 0
        server_content = ""
        server_name = ""
        seen_servers[""] = 0
    }
    
    /^[[:space:]]*server[[:space:]]*{/ {
        in_server = 1
        server_content = $0 "\n"
        server_name = ""
        next
    }
    
    in_server {
        server_content = server_content $0 "\n"
        
        # 提取server_name
        if ($0 ~ /server_name/) {
            gsub(/[[:space:]]*server_name[[:space:]]*/, "", $0)
            gsub(/;/, "", $0)
            server_name = $0
        }
        
        # 检查server块结束
        if ($0 ~ /^[[:space:]]*}/) {
            in_server = 0
            
            # 如果server_name为空，使用整个内容作为key
            if (server_name == "") {
                server_name = server_content
            }
            
            # 检查是否已存在相同的server
            if (!(server_name in seen_servers)) {
                seen_servers[server_name] = 1
                printf "%s", server_content
            } else {
                print "// 删除重复的server块: " server_name > "/dev/stderr"
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
    
    echo "完成处理: $config_file"
done

# 检查配置语法
echo "3. 检查nginx配置语法..."
if nginx -t; then
    echo "✓ 配置语法正确"
else
    echo "✗ 配置语法错误，请检查"
    exit 1
fi

# 统计重复的server块
echo "4. 统计重复配置..."
echo "检查HTTP端口重复:"
grep -r "server_name.*on.*0\.0\.0\.0:80" "$VHOST_DIR" | wc -l

echo "检查HTTPS端口重复:"
grep -r "server_name.*on.*0\.0\.0\.0:443" "$VHOST_DIR" | wc -l

# 显示清理后的配置
echo "5. 显示清理后的配置结构..."
echo "当前配置文件:"
ls -la "$VHOST_DIR"/*.conf 2>/dev/null

echo "6. 建议重启nginx..."
echo "运行以下命令重启nginx:"
echo "systemctl restart nginx"
echo "或"
echo "/usr/local/nginx/sbin/nginx -s reload"

echo "========= 清理完成 ========="
echo "注意：如果配置有语法错误，请检查备份文件: $BACKUP_DIR" 