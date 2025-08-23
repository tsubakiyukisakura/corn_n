#!/bin/bash
set -e

# 检测系统类型
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "无法检测系统类型，仅支持常见Linux发行版。"
  exit 1
fi

# 获取nginx版本列表（只列出大于1.20.1的所有版本，不分类型）
function get_nginx_versions() {
  echo "正在获取nginx版本列表..."
  local html=$(curl -s https://nginx.org/en/download.html)
  # 提取所有1.20.1及以上的版本，去重
  local all_versions=$(echo "$html" | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | sed 's/nginx-\(.*\)\.tar\.gz/\1/' | sort -Vu)
  for ver in $all_versions; do
    v_major=$(echo $ver | cut -d. -f1)
    v_minor=$(echo $ver | cut -d. -f2)
    v_patch=$(echo $ver | cut -d. -f3)
    # 只保留1.20.1及以上
    if (( v_major > 1 )) || (( v_major == 1 && v_minor > 20 )) || (( v_major == 1 && v_minor == 20 && v_patch >= 1 )); then
      echo "$ver"
    fi
  done
}

# 显示版本选择菜单（只显示序号和版本号）
function show_version_menu() {
  local version_list=()
  while IFS= read -r line; do
    version_list+=("$line")
  done < <(get_nginx_versions)

  echo "========= Nginx 版本选择 ========="
  echo "（数据来源：https://nginx.org/en/download.html）"
  echo ""
  local counter=1
  for ver in "${version_list[@]}"; do
    printf "%3d. %s\n" "$counter" "$ver"
    counter=$((counter+1))
  done
  echo "0. 返回上一级"
  echo "=================================="

  read -p "请选择版本序号: " choice
  if [ "$choice" = "0" ]; then
    return 1
  fi
  if [ "$choice" -ge 1 ] && [ "$choice" -le ${#version_list[@]} ]; then
    local selected_version="${version_list[$((choice-1))]}"
    echo "已选择版本: $selected_version"
    install_nginx_from_source "$selected_version"
  else
    echo "无效的版本序号"
    return 1
  fi
}

# 从源码编译安装nginx
function install_nginx_from_source() {
  local version="$1"
  
  echo "========= 安装 Nginx $version (源码编译) ========="
  
  # 检查是否已安装
  if command -v nginx >/dev/null 2>&1; then
    echo "检测到已安装的nginx，版本信息："
    nginx -v
    read -p "是否继续安装？这将覆盖现有安装 (y/N): " continue_install
    if [[ ! $continue_install =~ ^[Yy]$ ]]; then
      echo "安装已取消"
      return
    fi
  fi
  
  # 安装依赖
  echo "正在安装依赖包..."
  if [[ $OS == "ubuntu" || $OS == "debian" ]]; then
    apt update && apt install -y curl wget gnupg2 ca-certificates lsb-release build-essential gcc make libpcre3 libpcre3-dev zlib1g-dev libssl-dev
  elif [[ $OS == "centos" || $OS == "rocky" || $OS == "almalinux" ]]; then
    yum install -y epel-release
    yum install -y curl wget ca-certificates lsb-release gcc make pcre pcre-devel zlib-devel openssl-devel
  else
    echo "暂不支持该系统: $OS"
    return 1
  fi
  
  # 下载nginx源码
  echo "正在下载nginx $version..."
  cd /tmp
  if [ -f "nginx-$version.tar.gz" ]; then
    echo "发现已存在的源码包，跳过下载"
  else
    wget "https://nginx.org/download/nginx-$version.tar.gz"
  fi
  
  if [ ! -f "nginx-$version.tar.gz" ]; then
    echo "下载失败，请检查网络连接"
    return 1
  fi
  
  # 解压并编译
  echo "正在编译nginx..."
  tar zxvf "nginx-$version.tar.gz"
  cd "nginx-$version"
  
  # 配置编译选项
  ./configure \
    --prefix=/usr/local/nginx \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-file-aio \
    --with-http_secure_link_module
  
  # 编译
  make -j$(nproc)
  
  # 安装
  echo "正在安装nginx..."
  make install
  
  # 创建软链接
  ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx
  
  # 创建必要的目录
  mkdir -p /usr/local/nginx/conf/vhost
  mkdir -p /usr/local/nginx/logs
  
  # 显示安装结果
  echo ""
  echo "✅ Nginx $version 安装完成！"
  echo "安装路径: /usr/local/nginx"
  echo "配置文件: /usr/local/nginx/conf/nginx.conf"
  echo "可执行文件: /usr/local/nginx/sbin/nginx"
  echo ""
  nginx -v
}

# 仓库源安装（仅菜单）
function install_nginx_from_repo() {
  echo "========= 仓库源安装 ========="
  echo "此功能正在开发中..."
  echo "请选择源码编译安装以获得更好的控制。"
  read -p "按任意键继续..."
}

# Docker安装（仅菜单）
function install_nginx_from_docker() {
  echo "========= Docker安装 ========="
  echo "此功能正在开发中..."
  echo "请选择源码编译安装以获得更好的控制。"
  read -p "按任意键继续..."
}

function uninstall_nginx() {
  echo "========= 卸载 Nginx ========="
  
  # 检查是否安装了源码编译的nginx
  if [ ! -f "/usr/local/nginx/sbin/nginx" ]; then
    echo "未检测到源码编译安装的nginx"
    return 1
  fi
  
  # 停止nginx服务
  if pgrep -x nginx >/dev/null 2>&1; then
    echo "正在停止Nginx服务..."
    /usr/local/nginx/sbin/nginx -s stop
  fi
  
  # 删除nginx文件
  echo "正在删除Nginx文件..."
  rm -rf /usr/local/nginx
  rm -f /usr/bin/nginx
  
  # 删除配置文件（可选）
  read -p "是否删除Nginx配置文件？(y/N): " delete_conf
  if [[ $delete_conf =~ ^[Yy]$ ]]; then
    rm -rf /usr/local/nginx/conf
    echo "已删除Nginx配置文件。"
  fi
  
  echo "✅ Nginx卸载完成！"
}

function install_uninstall_menu() {
  while true; do
    clear
    echo "========= Nginx 安装/卸载 ========="
    echo "1. 安装 Nginx"
    echo "2. 卸载 Nginx"
    echo "0. 返回主菜单"
    echo "=================================="
    read -p "请输入选项: " choice
    case $choice in
      1)
        # 检查curl
        if ! command -v curl >/dev/null 2>&1; then
          echo "未检测到curl，正在安装curl..."
          if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_FAMILY=$ID
          else
            OS_FAMILY="unknown"
          fi
          case $OS_FAMILY in
            ubuntu|debian)
              apt update && apt install -y curl
              ;;
            centos|rocky|almalinux)
              yum install -y curl
              ;;
            fedora)
              dnf install -y curl
              ;;
            opensuse*|suse)
              zypper install -y curl
              ;;
            arch)
              pacman -Sy --noconfirm curl
              ;;
            *)
              echo "暂不支持该系统: $OS_FAMILY，请手动安装curl后重试。"; return 1;
              ;;
          esac
        fi
        show_version_menu
        echo "按任意键返回安装/卸载菜单..."; read -n 1
        ;;
      2)
        uninstall_nginx
        echo "按任意键返回安装/卸载菜单..."; read -n 1
        ;;
      0) break;;
      *) echo "无效选项"; sleep 1;;
    esac
  done
}

install_uninstall_menu 