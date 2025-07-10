#!/bin/bash

# 流量限制调试脚本

echo "========= 流量限制调试 ========="

# 1. 检查nginx配置
echo "1. 检查nginx配置..."
nginx -t

echo ""
echo "2. 检查主配置文件中的区域定义..."
grep -A 2 "limit_req_zone" /usr/local/nginx/conf/nginx.conf

echo ""
echo "3. 检查站点配置文件..."
cat /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf

echo ""
echo "4. 检查nginx进程..."
ps aux | grep nginx

echo ""
echo "5. 检查nginx错误日志..."
tail -5 /usr/local/nginx/logs/error.log

echo ""
echo "6. 测试流量限制..."

# 测试1: 快速连续请求
echo "测试1: 快速连续请求（模拟DDoS）"
for i in {1..10}; do
    response=$(curl -s -w "%{http_code}" -o /dev/null https://mm.1107211.xyz/ 2>/dev/null)
    echo "请求 $i: HTTP状态码 $response"
    sleep 0.05  # 50ms间隔
done

echo ""
echo "7. 检查访问日志..."
tail -10 /usr/local/nginx/logs/access.log | grep mm.1107211.xyz

echo ""
echo "8. 测试更严格的限制..."

# 临时应用更严格的限制
cp /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf.backup

# 修改为更严格的限制
sed -i 's/rate=2r\/s/rate=1r\/s/' /usr/local/nginx/conf/nginx.conf
sed -i 's/burst=3/burst=1/' /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf

# 重新加载配置
nginx -s reload

echo "已应用更严格的限制：rate=1r/s, burst=1"
echo "等待2秒后测试..."

sleep 2

# 再次测试
for i in {1..5}; do
    response=$(curl -s -w "%{http_code}" -o /dev/null https://mm.1107211.xyz/ 2>/dev/null)
    echo "严格测试 $i: HTTP状态码 $response"
    sleep 0.1
done

# 恢复原配置
cp /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf.backup /usr/local/nginx/conf/vhost/mm.1107211.xyz.conf
sed -i 's/rate=1r\/s/rate=2r\/s/' /usr/local/nginx/conf/nginx.conf
nginx -s reload

echo ""
echo "========= 调试完成 ========="
echo ""
echo "如果看到429状态码，说明流量限制生效"
echo "如果还是200，可能的原因："
echo "1. 浏览器缓存"
echo "2. CDN缓存"
echo "3. 本地网络延迟"
echo "4. nginx配置未正确加载" 