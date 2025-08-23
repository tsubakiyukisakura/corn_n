#!/bin/bash

# Nginx全量备份与还原脚本
# 备份内容：配置、证书、静态文件
# 适用目录：/usr/local/nginx/conf /usr/local/nginx/html /usr/local/nginx/ssl /etc/nginx/ssl
# 用法：
#   ./backup-nginx.sh backup   # 备份
#   ./backup-nginx.sh restore  # 还原

BACKUP_DIR="$(pwd)/nginx-backup-$(date +%Y%m%d%H%M%S)"
RESTORE_SRC=""

function list_backups() {
  echo "========= 现有备份 ========="
  local backups=()
  local counter=1
  
  # 查找所有备份目录
  for backup in nginx-backup-*; do
    if [ -d "$backup" ]; then
      backups+=("$backup")
      printf "%3d. %s\n" "$counter" "$backup"
      counter=$((counter+1))
    fi
  done
  
  if [ ${#backups[@]} -eq 0 ]; then
    echo "当前无备份文件。"
    return 1
  fi
  
  echo "============================"
  return 0
}

function do_backup() {
  echo "[备份] 目标目录: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  # 配置
  if [ -d /usr/local/nginx/conf ]; then
    cp -a /usr/local/nginx/conf "$BACKUP_DIR/"
    echo "已备份: /usr/local/nginx/conf"
  fi
  # 静态文件
  if [ -d /usr/local/nginx/html ]; then
    cp -a /usr/local/nginx/html "$BACKUP_DIR/"
    echo "已备份: /usr/local/nginx/html"
  fi
  # 证书
  if [ -d /usr/local/nginx/ssl ]; then
    cp -a /usr/local/nginx/ssl "$BACKUP_DIR/"
    echo "已备份: /usr/local/nginx/ssl"
  fi
  if [ -d /etc/nginx/ssl ]; then
    cp -a /etc/nginx/ssl "$BACKUP_DIR/"
    echo "已备份: /etc/nginx/ssl"
  fi
  echo "[完成] 备份已保存到: $BACKUP_DIR"
}

function do_restore() {
  # 显示备份列表
  if ! list_backups; then
    return 1
  fi
  
  # 获取备份列表
  local backups=()
  for backup in nginx-backup-*; do
    if [ -d "$backup" ]; then
      backups+=("$backup")
    fi
  done
  
  read -p "请选择要还原的备份序号: " choice
  if [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
    local selected_backup="${backups[$((choice-1))]}"
    echo "已选择备份: $selected_backup"
    
    # 恢复配置
    if [ -d "$selected_backup/conf" ]; then
      cp -a "$selected_backup/conf"/* /usr/local/nginx/conf/
      echo "已还原: /usr/local/nginx/conf"
    fi
    # 恢复静态
    if [ -d "$selected_backup/html" ]; then
      cp -a "$selected_backup/html"/* /usr/local/nginx/html/
      echo "已还原: /usr/local/nginx/html"
    fi
    # 恢复证书
    if [ -d "$selected_backup/ssl" ]; then
      if [ -d /usr/local/nginx/ssl ]; then
        cp -a "$selected_backup/ssl"/* /usr/local/nginx/ssl/
        echo "已还原: /usr/local/nginx/ssl"
      fi
      if [ -d /etc/nginx/ssl ]; then
        cp -a "$selected_backup/ssl"/* /etc/nginx/ssl/
        echo "已还原: /etc/nginx/ssl"
      fi
    fi
    echo "[完成] 还原完毕，正在重载nginx..."
    if command -v nginx >/dev/null 2>&1; then
      nginx -s reload || nginx -t && systemctl reload nginx
      echo "nginx已重载"
    fi
  else
    echo "无效的备份序号"
    return 1
  fi
}

case "$1" in
  backup)
    do_backup
    ;;
  restore)
    do_restore
    ;;
  *)
    echo "用法: $0 backup|restore"
    ;;
esac 