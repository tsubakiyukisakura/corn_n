#!/bin/bash

# 测试nginx版本获取和分类功能
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 引入安装脚本中的函数
source "$SCRIPT_DIR/install/install-nginx.sh"

echo "测试nginx版本获取功能..."
echo "================================"

# 测试版本获取
get_nginx_versions

echo ""
echo "测试版本选择菜单..."
echo "================================"

# 测试版本选择菜单
show_version_menu 