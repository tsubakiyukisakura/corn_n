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
report_file="$HOME/${site}_traffic_report.txt"
now=$(date +%s)
one_day_ago=$((now-86400))
one_week_ago=$((now-86400*7))
one_month_ago=$((now-86400*30))
get_traffic() {
  since_ts=$1
  total=0
  while read line; do
    ts=$(echo "$line" | awk '{gsub(/\[/, "", $4); split($4, t, ":"); split(t[1], d, "/"); m["Jan"]=1;m["Feb"]=2;m["Mar"]=3;m["Apr"]=4;m["May"]=5;m["Jun"]=6;m["Jul"]=7;m["Aug"]=8;m["Sep"]=9;m["Oct"]=10;m["Nov"]=11;m["Dec"]=12; mon=m[d[2]]; printf "%d", mktime(d[3]" "mon" "d[1]" "t[2]" "t[3]" "t[4])}')
    [ "$ts" -ge "$since_ts" ] && total=$((total+${#line}+1))
  done < "$found_log"
  echo "$total"
}
traffic_day=$(get_traffic $one_day_ago)
traffic_week=$(get_traffic $one_week_ago)
traffic_month=$(get_traffic $one_month_ago)
mb_day=$(awk -v b="$traffic_day" 'BEGIN{printf "%.2f", b/1024/1024}')
mb_week=$(awk -v b="$traffic_week" 'BEGIN{printf "%.2f", b/1024/1024}')
mb_month=$(awk -v b="$traffic_month" 'BEGIN{printf "%.2f", b/1024/1024}')
echo "========= $site 流量统计 =========" > "$report_file"
echo "1天: $mb_day MB" >> "$report_file"
echo "1周: $mb_week MB" >> "$report_file"
echo "1月: $mb_month MB" >> "$report_file"
echo "日志文件: $found_log" >> "$report_file"
echo "================================" >> "$report_file"
if ! command -v zip >/dev/null 2>&1; then
  echo "未检测到zip命令，正在尝试自动安装..."
  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y zip
  elif command -v yum >/dev/null 2>&1; then
    yum install -y zip
  else
    echo "无法自动安装zip，请手动安装后重试。"
    echo "仅生成了txt报表：$report_file"
    echo "日志文件路径：$found_log"
    exit 1
  fi
fi
if command -v zip >/dev/null 2>&1; then
  zip_file="$HOME/${site}_report_$(date +%Y%m%d%H%M%S).zip"
  zip -j "$zip_file" "$found_log" "$report_file" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "报表已打包：$zip_file"
  else
    echo "打包失败"
  fi
else
  echo "未检测到zip命令，仅生成了txt报表：$report_file"
  echo "日志文件路径：$found_log"
fi 