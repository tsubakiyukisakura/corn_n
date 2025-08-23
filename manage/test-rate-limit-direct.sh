#!/bin/bash

# 直接流量限制测试脚本

echo "========= 直接流量限制测试 ========="

# 测试1: 使用不同的User-Agent和IP模拟
echo "测试1: 模拟不同客户端快速请求..."

for i in {1..10}; do
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "User-Agent: TestBot-$i" \
        -H "X-Forwarded-For: 192.168.1.$i" \
        https://mm.1107211.xyz/ 2>/dev/null)
    echo "请求 $i: HTTP状态码 $response"
    sleep 0.05
done

echo ""
echo "测试2: 使用wget测试..."

# 使用wget测试
for i in {1..5}; do
    response=$(wget --spider --server-response https://mm.1107211.xyz/ 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}')
    echo "wget请求 $i: HTTP状态码 $response"
    sleep 0.1
done

echo ""
echo "测试3: 检查nginx访问日志..."

# 检查最近的访问日志
echo "最近的访问记录："
tail -20 /usr/local/nginx/logs/access.log | grep mm.1107211.xyz

echo ""
echo "测试4: 检查nginx错误日志..."

# 检查错误日志
echo "最近的错误记录："
tail -10 /usr/local/nginx/logs/error.log

echo ""
echo "测试5: 使用ab工具进行压力测试..."

# 检查是否有ab工具
if command -v ab >/dev/null 2>&1; then
    echo "使用ab进行压力测试（10个请求，1个并发）..."
    ab -n 10 -c 1 https://mm.1107211.xyz/ 2>/dev/null | grep "Failed requests\|Complete requests"
else
    echo "ab工具未安装，跳过压力测试"
fi

echo ""
echo "========= 测试完成 ========="
echo ""
echo "如果所有请求都返回200，可能的原因："
echo "1. 流量限制配置未生效"
echo "2. 需要重启nginx而不是重载"
echo "3. 浏览器或CDN缓存"
echo "4. 网络延迟导致请求间隔过长" 