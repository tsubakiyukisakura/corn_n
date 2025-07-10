#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function install_nginx() {
  echo "========= Nginx 安装/卸载 ========="
  bash "$SCRIPT_DIR/install/install-nginx.sh"
  echo "按任意键返回主菜单..."
  read -n 1
  main_menu
}

function manage_nginx() {
  bash "$SCRIPT_DIR/manage/nginx-manager.sh"
}



function main_menu() {
  clear
  echo "=========================================="
  echo "           Nginx 管理工具"
  echo "=========================================="
  echo "1. 安装/卸载"
  echo "2. 管理"
  echo "3. 退出"
  echo "=========================================="
  read -p "请输入选项: " choice
  case $choice in
    1) install_nginx;;
    2) manage_nginx;;
    3) 
      echo "感谢使用 Nginx 管理工具！"
      exit 0
      ;;
    *) 
      echo "无效选项，请重新选择"
      sleep 1
      main_menu
      ;;
  esac
}

# 启动主菜单
main_menu 