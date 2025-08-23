#!/bin/bash
set -e

NGINX_DIR="/usr/local/nginx"
BACKUP_DIR="$HOME/nginx-backup-$(date +%Y%m%d%H%M%S)"

function backup_nginx() {
  echo "正在备份Nginx..."
  mkdir -p "$BACKUP_DIR"
  cp -a $NGINX_DIR "$BACKUP_DIR/"
  if [ -d /etc/letsencrypt ]; then
    cp -a /etc/letsencrypt "$BACKUP_DIR/"
  fi
  if [ -d ~/.acme.sh ]; then
    cp -a ~/.acme.sh "$BACKUP_DIR/"
  fi
  tar czvf "$BACKUP_DIR.tar.gz" -C "$HOME" $(basename "$BACKUP_DIR")
  rm -rf "$BACKUP_DIR"
  echo "备份完成: $BACKUP_DIR.tar.gz"
}

function restore_nginx() {
  backup_file="$1"
  if [ -z "$backup_file" ]; then
    echo "用法: $0 restore <备份文件路径>"
    exit 1
  fi
  if [ ! -f "$backup_file" ]; then
    echo "备份文件不存在"; exit 1
  fi
  tar xzvf "$backup_file" -C "$HOME"
  RESTORED_DIR=$(tar tzf "$backup_file" | head -1 | cut -f1 -d"/")
  sudo cp -a "$HOME/$RESTORED_DIR/nginx" /usr/local/
  if [ -d "$HOME/$RESTORED_DIR/letsencrypt" ]; then
    sudo cp -a "$HOME/$RESTORED_DIR/letsencrypt" /etc/
  fi
  if [ -d "$HOME/$RESTORED_DIR/.acme.sh" ]; then
    cp -a "$HOME/$RESTORED_DIR/.acme.sh" ~/
  fi
  echo "恢复完成，请检查nginx配置并手动启动nginx。"
}

case "$1" in
  backup) backup_nginx;;
  restore) restore_nginx "$2";;
  *) echo "用法: $0 backup|restore [备份文件]"; exit 1;;
esac 