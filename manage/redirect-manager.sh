#!/bin/bash
# 用法: redirect-manager.sh /path/to/site.conf
set -e

CONF_FILE="$1"
if [ -z "$CONF_FILE" ] || [ ! -f "$CONF_FILE" ]; then
  echo "用法: $0 /path/to/site.conf"
  exit 1
fi

# 交互式选择重定向类型
PS3="请选择重定向类型: "
select redirect_type in \
  "整站 301 永久重定向" \
  "整站 302 临时重定向" \
  "仅根目录重定向" \
  "自定义 location 重定向" \
  "删除重定向" \
  "退出"; do
  case $REPLY in
    1|2|3|4|5|6) break;;
    *) echo "无效选项，请重新选择。";;
  esac
done

if [[ $REPLY == 6 ]]; then
  echo "已取消。"
  exit 0
fi

# 选择作用端口
PS3="请选择要设置重定向的端口: "
select port_mode in \
  "仅80（http）" \
  "仅443（https）" \
  "80和443都处理"; do
  case $REPLY in
    1|2|3) break;;
    *) echo "无效选项，请重新选择。";;
  esac
done

# 端口选择变量
case $REPLY in
  1) port_list="80";;
  2) port_list="443";;
  3) port_list="80 443";;
  *) echo "未知端口类型，已取消。"; exit 1;;
esac

if [[ $redirect_type == "删除重定向" ]]; then
  # 删除重定向（恢复server块原始内容）
  awk -v ports="$port_list" '
  BEGIN{srv=0;inport=0}
  /server[ \t]*{/ {srv=1;inport=0;print $0;next}
  srv && match($0, /listen[ \t]+([0-9]+)/, arr) {
    port=arr[1];
    if(index(ports, port)>0) inport=1; else inport=0
  }
  srv && inport && /return 30[12] / {next}
  {print $0}
  /}/ && srv {srv=0;inport=0}
  ' "$CONF_FILE" > "$CONF_FILE.tmp" && mv "$CONF_FILE.tmp" "$CONF_FILE"
  echo "已删除所选端口server块中的重定向。"
  exit 0
fi

read -p "请输入重定向目标URL（如 https://newdomain.com 或 https://newdomain.com/）: " target_url
if [[ -z "$target_url" ]]; then
  echo "未输入目标，已取消。"
  exit 1
fi

case $redirect_type in
  "整站 301 永久重定向")
    redirect_line="return 301 $target_url\$request_uri;"
    location_block="location / {\n        $redirect_line\n    }"
    ;;
  "整站 302 临时重定向")
    redirect_line="return 302 $target_url\$request_uri;"
    location_block="location / {\n        $redirect_line\n    }"
    ;;
  "仅根目录重定向")
    redirect_line="return 301 $target_url;"
    location_block="location = / {\n        $redirect_line\n    }"
    ;;
  "自定义 location 重定向")
    read -p "请输入自定义 location 路径（如 /oldpath）: " custom_loc
    if [[ -z "$custom_loc" ]]; then
      echo "未输入路径，已取消。"; exit 1
    fi
    redirect_line="return 301 $target_url;"
    location_block="location $custom_loc {\n        $redirect_line\n    }"
    ;;
  *)
    echo "未知类型，已取消。"; exit 1
    ;;
esac

# 用awk精准替换指定端口server块内容，兼容各种awk
awk -v loc_block="$location_block" -v ports="$port_list" '
BEGIN{srv=0;inport=0;brace=0;printed=0}
/server[ \t]*{/ {srv=1;inport=0;brace=1;buf=$0"\n";next}
srv && /listen[ \t]+[0-9]+/ {
  line=$0;
  port="";
  # 提取listen后的端口号
  n=split(line, arr, /[ \t]+/);
  for(i=1;i<=n;i++) {
    if(arr[i]=="listen") {
      if((i+1)<=n) {
        port=arr[i+1];
        sub(/;.*/,"",port); # 去掉分号
        if(index(ports, port)>0) inport=1; else inport=0;
        break;
      }
    }
  }
}
srv && inport && /location[ \t]*\// {next}
srv && inport && /return 30[12] / {next}
srv && inport && /}/ {
  if (!printed) {
    n=split(loc_block, arr2, "\\n");
    for(j=1;j<=n;j++) print "    "arr2[j];
    printed=1;
  }
  print $0; srv=0; inport=0; brace=0; printed=0; next
}
srv && brace>0 {buf=buf $0"\n"; next}
{print $0}
' "$CONF_FILE" > "$CONF_FILE.tmp" && mv "$CONF_FILE.tmp" "$CONF_FILE"
echo "已为所选端口server块设置重定向。" 