#!/bin/bash

# 流量限制测试脚本

echo "========= 流量限制测试 ========="

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <域名或IP> [端口]"
    echo "示例: $0 example.com"
    echo "示例: $0 192.168.1.100 80"
    exit 1
fi

TARGET=$1
PORT=${2:-80}

echo "测试目标: $TARGET:$PORT"
echo "测试类型: 快速连续请求测试"
echo ""

# 测试1: 快速连续请求
echo "测试1: 快速连续请求（模拟DDoS攻击）"
echo "发送10个快速请求..."

for i in {1..10}; do
    response=$(curl -s -w "%{http_code}" -o /dev/null "http://$TARGET:$PORT/" 2>/dev/null)
    echo "请求 $i: HTTP状态码 $response"
    
    if [ "$response" = "429" ]; then
        echo "✅ 流量限制生效！请求被限制（HTTP 429）"
        break
    fi
    
    sleep 0.1  # 100ms间隔
done

echo ""

# 测试2: 并发连接测试
echo "测试2: 并发连接测试"
echo "尝试建立多个并发连接..."

# 使用curl的并发选项
response=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 --parallel 5 --parallel-max 5 "http://$TARGET:$PORT/" 2>/dev/null)

if [ "$response" = "429" ]; then
    echo "✅ 并发连接限制生效！"
else
    echo "⚠️  并发连接限制可能未生效，状态码: $response"
fi

echo ""

# 测试3: 大文件上传测试
echo "测试3: 大文件上传测试"
echo "尝试上传一个超过限制大小的文件..."

# 创建一个测试文件
dd if=/dev/zero of=/tmp/test_large_file bs=1M count=1 2>/dev/null

response=$(curl -s -w "%{http_code}" -o /dev/null --connect-timeout 5 --max-time 10 -F "file=@/tmp/test_large_file" "http://$TARGET:$PORT/" 2>/dev/null)

if [ "$response" = "413" ]; then
    echo "✅ 请求大小限制生效！文件过大被拒绝（HTTP 413）"
elif [ "$response" = "429" ]; then
    echo "✅ 流量限制生效！请求被限制（HTTP 429）"
else
    echo "⚠️  限制可能未生效，状态码: $response"
fi

# 清理测试文件
rm -f /tmp/test_large_file

echo ""

# 测试4: 正常访问测试
echo "测试4: 正常访问测试"
echo "等待2秒后进行正常访问..."

sleep 2

response=$(curl -s -w "%{http_code}" -o /dev/null "http://$TARGET:$PORT/" 2>/dev/null)

if [ "$response" = "200" ]; then
    echo "✅ 正常访问成功！流量限制允许正常请求"
else
    echo "⚠️  正常访问失败，状态码: $response"
fi

echo ""
echo "========= 测试完成 ========="
echo ""
echo "说明："
echo "- HTTP 429: 请求频率超限"
echo "- HTTP 413: 请求体过大"
echo "- HTTP 200: 正常访问"
echo ""
echo "如果看到429状态码，说明流量限制正常工作"
echo "如果所有请求都返回200，可能需要检查配置是否正确应用" 