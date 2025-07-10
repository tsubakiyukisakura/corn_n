#!/bin/bash
# Nginx 管理工具启动脚本

# 检查是否在正确的目录
if [ ! -f "nginx-main.sh" ]; then
    echo "错误：请在 nginx-easy 目录中运行此脚本"
    exit 1
fi

# 检查执行权限
if [ ! -x "nginx-main.sh" ]; then
    chmod +x nginx-main.sh
fi

# 启动主菜单
echo "正在启动 Nginx 管理工具..."
bash nginx-main.sh 