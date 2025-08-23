#!/bin/bash

# 精确流量限制测试脚本
# 作者：AI助手
# 功能：准确测试nginx流量限制是否生效

DOMAIN="mm.1107211.xyz"
TEST_URL="http://$DOMAIN"

echo "========= 精确流量限制测试 ========="

# 检查nginx配置
echo "1. 检查nginx配置..."
nginx -t 2>&1 | grep -E "(conflicting server name|syntax is ok)"

# 显示当前流量限制配置
echo "2. 显示当前流量限制配置..."
echo "主配置文件中的区域定义:"
grep -E "limit_req_zone|limit_conn_zone" /usr/local/nginx/conf/nginx.conf

echo "站点配置中的限制规则:"
grep -A 10 -B 2 "limit_req\|limit_conn" /usr/local/nginx/conf/vhost/*.conf

# 测试函数
test_rate_limit() {
    local test_name="$1"
    local delay="$2"
    local count="$3"
    
    echo "3. $test_name..."
    echo "发送 $count 个请求，间隔 $delay 秒..."
    
    for i in $(seq 1 $count); do
        # 使用curl发送请求，禁用缓存
        response=$(curl -s -w "%{http_code}" -o /dev/null \
            -H "Cache-Control: no-cache" \
            -H "Pragma: no-cache" \
            --max-time 5 \
            "$TEST_URL" 2>/dev/null)
        
        echo "请求 $i: HTTP状态码 $response"
        
        # 如果不是最后一个请求，则等待
        if [ $i -lt $count ]; then
            sleep $delay
        fi
    done
}

# 测试1：快速连续请求
test_rate_limit "测试1: 快速连续请求（模拟DDoS）" 0.1 10

echo ""
echo "等待3秒..."
sleep 3

# 测试2：正常间隔请求
test_rate_limit "测试2: 正常间隔请求" 1 5

echo ""
echo "等待5秒..."
sleep 5

# 测试3：使用不同User-Agent
echo "3. 测试3: 使用不同User-Agent..."
for i in {1..5}; do
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "User-Agent: TestBot-$i" \
        -H "Cache-Control: no-cache" \
        --max-time 5 \
        "$TEST_URL" 2>/dev/null)
    
    echo "User-Agent TestBot-$i: HTTP状态码 $response"
    sleep 0.2
done

# 测试4：使用wget
echo ""
echo "4. 测试4: 使用wget..."
for i in {1..5}; do
    response=$(wget --server-response --spider --timeout=5 \
        --user-agent="WgetTest-$i" \
        "$TEST_URL" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}')
    
    echo "wget请求 $i: HTTP状态码 $response"
    sleep 0.3
done

# 检查nginx日志
echo ""
echo "5. 检查nginx错误日志中的限制记录..."
echo "最近的流量限制记录:"
tail -20 /usr/local/nginx/logs/error.log | grep -E "limiting requests|limiting connections"

echo ""
echo "6. 检查访问日志..."
echo "最近的访问记录:"
tail -10 /usr/local/nginx/logs/access.log | grep "$DOMAIN"

# 显示统计信息
echo ""
echo "7. 测试结果分析..."
echo "如果看到429状态码，说明流量限制生效"
echo "如果看到limiting requests错误日志，说明限制正在工作"
echo "如果所有请求都返回200，可能的原因："
echo "  - 请求间隔过长，未触发限制"
echo "  - 浏览器或CDN缓存"
echo "  - 网络延迟导致请求分散"

echo ""
echo "========= 测试完成 =========" 