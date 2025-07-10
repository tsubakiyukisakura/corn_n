#!/bin/bash
log_dir="/usr/local/nginx/logs"
if [ ! -d "$log_dir" ]; then
  echo "未找到日志目录 $log_dir"; exit 1
fi
# 统计前20 IP及访问量
ip_counts=$(find "$log_dir" -name "access.log*" | xargs cat 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -rn | head -20)
max_count=$(echo "$ip_counts" | awk 'NR==1{print $1}')
[ -z "$max_count" ] && max_count=1
bar_max=50
printf "%-16s %-8s %s\n" "IP地址" "访问量" "访问量柱状图"
echo "-------------------------------------------------------------"
echo "$ip_counts" | while read count ip; do
  bar_len=$((count*bar_max/max_count))
  bar=""
  for ((i=0;i<bar_len;i++)); do bar+="*"; done
  printf "%-16s %-8s %s\n" "$ip" "$count" "$bar"
done
echo "-------------------------------------------------------------" 