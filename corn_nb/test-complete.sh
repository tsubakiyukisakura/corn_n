#!/bin/bash

# 完整测试nginx安装菜单功能
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========= Nginx 安装菜单完整测试 ========="
echo ""

# 测试主菜单
echo "1. 测试主菜单..."
echo "选择 1 进入安装/卸载菜单"
echo "选择 2 进入管理菜单"
echo "选择 3 退出"
echo ""

# 测试安装菜单
echo "2. 测试安装菜单..."
echo "选择 1 进入源码编译安装"
echo "选择 2 进入仓库源安装（仅菜单）"
echo "选择 3 进入Docker安装（仅菜单）"
echo "选择 0 返回上一级"
echo ""

# 测试版本选择
echo "3. 测试版本选择菜单..."
echo "应该显示："
echo "- 📦 Mainline Versions (开发版本): 1.25+"
echo "- 🔒 Stable Versions (稳定版本): 1.20-1.24"
echo "- 📚 Legacy Versions (旧版本): 1.19及以下"
echo ""

# 测试安装流程
echo "4. 测试安装流程..."
echo "选择版本后应该："
echo "- 检查是否已安装nginx"
echo "- 安装依赖包"
echo "- 下载指定版本的源码"
echo "- 编译安装"
echo "- 创建必要的目录"
echo "- 显示安装结果"
echo ""

echo "========= 测试完成 ========="
echo "现在可以运行主菜单进行实际测试："
echo "bash nginx-main.sh" 