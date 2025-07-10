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
echo "========= $site 安全扫描与告警 ========="
# 检查SQL注入、XSS、目录遍历等特征
sql_count=$(grep -Ei "(select.+from|union.+select|\'--|\"--)" "$found_log" | wc -l)
xss_count=$(grep -Ei "(<script>|javascript:|onerror=|onload=)" "$found_log" | wc -l)
dir_count=$(grep -E "\.\./|/etc/passwd|/bin/sh" "$found_log" | wc -l)
if [ "$sql_count" -gt 0 ]; then
  echo "[告警] 检测到疑似SQL注入攻击 $sql_count 次"
fi
if [ "$xss_count" -gt 0 ]; then
  echo "[告警] 检测到疑似XSS攻击 $xss_count 次"
fi
if [ "$dir_count" -gt 0 ]; then
  echo "[告警] 检测到疑似目录遍历/敏感文件扫描 $dir_count 次"
fi
if [ "$sql_count" -eq 0 ] && [ "$xss_count" -eq 0 ] && [ "$dir_count" -eq 0 ]; then
  echo "未检测到常见攻击特征。"
fi
echo "====================================" 