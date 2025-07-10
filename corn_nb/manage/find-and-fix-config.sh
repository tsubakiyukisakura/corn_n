#!/bin/bash

# 查找和修复nginx配置问题

echo "========= 查找nginx配置文件 ========="

# 查找所有nginx配置文件
echo "查找所有nginx配置文件..."
find /usr/local/nginx/conf/ -name "*.conf" 2>/dev/null

echo ""
echo "查找包含mm.1107211.xyz的配置文件..."
grep -r "mm.1107211.xyz" /usr/local/nginx/conf/ 2>/dev/null

echo ""
echo "查找所有443端口的配置..."
grep -r "listen 443" /usr/local/nginx/conf/vhost/ 2>/dev/null

echo ""
echo "检查nginx配置语法..."
nginx -t

echo ""
echo "检查nginx进程..."
ps aux | grep nginx

echo ""
echo "检查nginx配置文件位置..."
nginx -t 2>&1 | grep "nginx.conf"

echo ""
echo "查找vhost目录..."
find /usr/local/nginx/conf/ -name "vhost" -type d 2>/dev/null

echo ""
echo "列出vhost目录内容..."
ls -la /usr/local/nginx/conf/vhost/ 2>/dev/null || echo "vhost目录不存在"

echo ""
echo "========= 修复建议 ========="
echo "1. 如果找到多个相同域名的配置文件，请删除重复的"
echo "2. 确保只有一个mm.1107211.xyz的配置文件"
echo "3. 检查配置文件路径是否正确"
echo "4. 重新应用流量限制配置" 