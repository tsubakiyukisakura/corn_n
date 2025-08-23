#!/bin/bash
conf_file="$1"
if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
  echo "未指定或未找到配置文件"; exit 1
fi
echo "========= 伪静态规则管理 ========="
echo "1. 添加伪静态规则"
echo "2. 删除伪静态规则"
echo "0. 返回上一级"
read -p "请选择操作: " op
if [[ $op == 1 ]]; then
  echo "请选择伪静态模板:"
  echo "1. WordPress"
  echo "2. Typecho"
  echo "3. Discuz"
  echo "4. Hexo"
  echo "5. ThinkPHP"
  echo "6. 自定义"
  read -p "请输入模板序号: " tpl_idx
  case $tpl_idx in
    1)
      cat >> "$conf_file" <<EOL
    # WordPress伪静态
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
EOL
      ;;
    2)
      cat >> "$conf_file" <<EOL
    # Typecho伪静态
    if (-f \$request_filename/index.php) {
        rewrite ^/(.*)$ /$1/index.php last;
    }
    if (!-f \$request_filename) {
        rewrite ^/(.*)$ /index.php last;
    }
EOL
      ;;
    3)
      cat >> "$conf_file" <<EOL
    # Discuz伪静态
    location / {
        if (!-e \$request_filename) {
            rewrite ^/(.*)$ /index.php last;
        }
    }
EOL
      ;;
    4)
      cat >> "$conf_file" <<EOL
    # Hexo伪静态
    location / {
        try_files \$uri \$uri/ /index.html;
    }
EOL
      ;;
    5)
      cat >> "$conf_file" <<EOL
    # ThinkPHP伪静态
    location / {
        if (!-e \$request_filename) {
            rewrite ^/(.*)$ /index.php?s=$1 last;
            break;
        }
    }
EOL
      ;;
    6)
      echo "请输入自定义rewrite规则（多行以;结尾，输入end结束）:"
      rules=""
      while true; do
        read line
        [ "$line" == "end" ] && break
        rules="$rules$line\n"
      done
      cat >> "$conf_file" <<EOL
    # 自定义伪静态
    location / {
$rules
    }
EOL
      ;;
    *)
      echo "无效模板。"; exit 1;;
  esac
  echo "已添加伪静态规则。"
elif [[ $op == 2 ]]; then
  sed -i '/# WordPress伪静态/,/}/d;/# Typecho伪静态/,/}/d;/# Discuz伪静态/,/}/d;/# Hexo伪静态/,/}/d;/# ThinkPHP伪静态/,/}/d;/# 自定义伪静态/,/}/d' "$conf_file"
  echo "已删除伪静态规则。"
else
  echo "返回上一级。"; exit 0
fi 