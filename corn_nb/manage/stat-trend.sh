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
# 生成近30天日期列表
date_list=()
for i in $(seq 0 29); do
  date_list+=("$(date -d "-$i day" +%d/%b/%Y)")
done
awk '{gsub(/\[/,"",$4); split($4, t, ":"); print t[1]}' "$found_log" > /tmp/${site}_trend_dates.tmp
echo "========= $site 近30天访问趋势 ========="
max=0
declare -A day_count
for d in "${date_list[@]}"; do
  c=$(grep -c "$d" /tmp/${site}_trend_dates.tmp)
  day_count["$d"]=$c
  [ "$c" -gt "$max" ] && max=$c
done
[ "$max" -eq 0 ] && max=1
for ((i=29;i>=0;i--)); do
  d="${date_list[$i]}"
  c=${day_count["$d"]}
  bar_len=$((c*50/max))
  bar=""
  for ((j=0;j<bar_len;j++)); do bar="$bar*"; done
  printf "%s %6d |%s\n" "$d" "$c" "$bar"
done
echo "===================================="
rm -f /tmp/${site}_trend_dates.tmp 