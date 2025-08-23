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
  if [ -n "$match" ]; then found_log="$match"; break; fi
  match=$(ls "$log_dir"/access-${site}-*.log 2>/dev/null | head -1)
  if [ -n "$match" ]; then found_log="$match"; break; fi
  match=$(ls "$log_dir"/access.${site}*.log 2>/dev/null | head -1)
  if [ -n "$match" ]; then found_log="$match"; break; fi
  match=$(ls "$log_dir"/*$site*.log 2>/dev/null | head -1)
  if [ -n "$match" ]; then found_log="$match"; break; fi
  if [ -f "$log_dir/access.log" ]; then found_log="$log_dir/access.log"; fi
done
if [ -z "$found_log" ]; then
  echo "未找到该站点日志文件"; exit 1
fi
echo "按Ctrl+C退出实时查看"
tail -f "$found_log" 