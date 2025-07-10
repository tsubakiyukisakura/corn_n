#!/bin/bash
log_dir="/usr/local/nginx/logs"
site="$1"
if [ ! -d "$log_dir" ]; then
  echo "未找到日志目录 $log_dir"; exit 1
fi
if [ -z "$site" ]; then
  echo "未指定站点名"; exit 1
fi
log_files=("$log_dir/access_$site.log" "$log_dir/access-$site.log" "$log_dir/access.log")
found_log=""
for f in "${log_files[@]}"; do
  if [ -f "$f" ]; then found_log="$f"; break; fi
  match=$(ls "$log_dir"/access_${site}_*.log 2>/dev/null | head -1)
  [ -n "$match" ] && found_log="$match" && break
  match=$(ls "$log_dir"/access-${site}-*.log 2>/dev/null | head -1)
  [ -n "$match" ] && found_log="$match" && break
  match=$(ls "$log_dir"/access.${site}*.log 2>/dev/null | head -1)
  [ -n "$match" ] && found_log="$match" && break
  match=$(ls "$log_dir"/*$site*.log 2>/dev/null | head -1)
  [ -n "$match" ] && found_log="$match" && break
  [ -f "$log_dir/access.log" ] && found_log="$log_dir/access.log"
done
[ -z "$found_log" ] && echo "未找到该站点日志文件" && exit 1
# 只统计近1天
today=$(date +%d/%b/%Y)
awk -v d="$today" '$4 ~ d {print $7}' "$found_log" | sort | uniq -c | sort -rn | head -20 > /tmp/${site}_hoturl.tmp
max=$(awk '{if($1>max)max=$1}END{print max+0}' /tmp/${site}_hoturl.tmp)
[ "$max" -eq 0 ] && max=1
n=1
while read c u; do
  bar_len=$((c*50/max))
  bar=""
  for ((j=0;j<bar_len;j++)); do bar="$bar*"; done
  printf "%2d. %-40s %6d |%s\n" "$n" "$u" "$c" "$bar"
  n=$((n+1))
done < /tmp/${site}_hoturl.tmp
echo "===================================="
rm -f /tmp/${site}_hoturl.tmp 