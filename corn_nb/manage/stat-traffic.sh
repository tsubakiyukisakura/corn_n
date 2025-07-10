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
# 自动检测并安装bc
if ! command -v bc >/dev/null 2>&1; then
  echo "未检测到bc，正在自动安装..."
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case $ID in
      ubuntu|debian) apt update && apt install -y bc;;
      centos|rocky|almalinux) yum install -y bc;;
      fedora) dnf install -y bc;;
      opensuse*|suse) zypper install -y bc;;
      arch) pacman -Sy --noconfirm bc;;
      *) echo "请手动安装bc后重试。"; exit 1;;
    esac
  else
    echo "未知系统，请手动安装bc后重试。"; exit 1;
  fi
fi
# 统计1天、1周、1月流量
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
max=$traffic_day
[ "$traffic_week" -gt "$max" ] && max=$traffic_week
[ "$traffic_month" -gt "$max" ] && max=$traffic_month
[ "$max" -eq 0 ] && max=1
bar_max=50
show_bar() {
  val=$1; label=$2
  bar_len=$((val*bar_max/max))
  bar=""
  for ((i=0;i<bar_len;i++)); do bar="$bar#"; done
  printf "%-8s %8.2f MB |%s\n" "$label" "$(echo "scale=2; $val/1024/1024" | bc)" "$bar"
}
echo "========= $site 流量统计 ========="
show_bar $traffic_day "1天"
show_bar $traffic_week "1周"
show_bar $traffic_month "1月"
echo "================================" 