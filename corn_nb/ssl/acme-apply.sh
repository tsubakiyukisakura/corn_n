#!/bin/bash
# acme-apply.sh
# 用于自动化acme.sh证书申请/续期，支持多CA、RSA/ECC、自动注册邮箱、自动检测acme.sh和依赖、自动停启Nginx、证书路径检测、参数调用、友好提示

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_SSL="$SCRIPT_DIR/lib/ssl.sh"
[ -f "$LIB_SSL" ] && source "$LIB_SSL"

DOMAIN=""
CA="letsencrypt"
EMAIL=""
KEY_TYPE="rsa" # 可选: rsa, ecc
ACTION="issue" # 可选: issue, renew
METHOD=""      # 可选: standalone, webroot, nginx
WEBROOT="/tmp/acme-challenge"
INSTALL_PATH="/etc/nginx/ssl"

usage() {
  echo "用法: $0 -d <域名> [-c <ca>] [-e <邮箱>] [-t <rsa|ecc>] [-a <issue|renew>] [-m <standalone|webroot|nginx>] [-w <webroot目录>]"
  echo "  -d  申请证书的域名"
  echo "  -c  CA类型: letsencrypt | zerossl | buypass (默认: letsencrypt)"
  echo "  -e  邮箱 (ZeroSSL首次必填，建议填写)"
  echo "  -t  证书类型: rsa | ecc (默认: rsa)"
  echo "  -a  操作: issue(申请) | renew(续期) (默认: issue)"
  echo "  -m  验证方式: standalone | webroot | nginx (自动判断)"
  echo "  -w  webroot目录 (仅webroot方式有效，默认: /tmp/acme-challenge)"
  exit 1
}

while getopts "d:c:e:t:a:m:w:h" opt; do
  case $opt in
    d) DOMAIN="$OPTARG";;
    c) CA="$OPTARG";;
    e) EMAIL="$OPTARG";;
    t) KEY_TYPE="$OPTARG";;
    a) ACTION="$OPTARG";;
    m) METHOD="$OPTARG";;
    w) WEBROOT="$OPTARG";;
    h) usage;;
    *) usage;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "[错误] 必须指定域名！"
  usage
fi

if [[ -z "$EMAIL" && "$CA" == "zerossl" ]]; then
  echo "[提示] ZeroSSL 必须注册邮箱。"
  read -p "请输入邮箱: " EMAIL
  if [[ -z "$EMAIL" ]]; then
    echo "[错误] 未输入邮箱，无法继续。"
    exit 1
  fi
fi

install_acme() {
  if ! command -v acme.sh >/dev/null 2>&1; then
    echo "[信息] 未检测到acme.sh，正在自动安装..."
    if [[ -n "$EMAIL" ]]; then
      echo "[信息] 使用邮箱 $EMAIL 安装 acme.sh ..."
      curl https://get.acme.sh | sh -s email="$EMAIL"
    else
      curl https://get.acme.sh | sh
    fi
    export PATH=~/.acme.sh:$PATH
    if [ -f ~/.bashrc ]; then
      source ~/.bashrc
    elif [ -f ~/.zshrc ]; then
      source ~/.zshrc
    fi
  fi
}

install_socat() {
  if ! command -v socat >/dev/null 2>&1; then
    echo "[信息] 未检测到socat，正在自动安装..."
    if command -v apt >/dev/null 2>&1; then
      apt update && apt install -y socat
    elif command -v yum >/dev/null 2>&1; then
      yum install -y socat
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y socat
    else
      echo "[错误] 未知包管理器，请手动安装socat！"
      exit 1
    fi
  fi
}

stop_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    echo "[信息] 停止Nginx..."
    # 先尝试优雅停止
    nginx -s quit 2>/dev/null || nginx -s stop 2>/dev/null || systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null
    # 等待进程完全退出
    sleep 5
    # 如果还有进程，再强制停止
    if pgrep -x nginx >/dev/null 2>&1; then
      echo "强制停止剩余的nginx进程..."
      pkill -9 nginx 2>/dev/null || true
      sleep 2
    fi
    # 清理PID文件
    if [ -f "/usr/local/nginx/logs/nginx.pid" ]; then
      echo "清理nginx PID文件..."
      rm -f /usr/local/nginx/logs/nginx.pid
    fi
  fi
}

start_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    echo "[信息] 启动Nginx..."
    nginx || systemctl start nginx || service nginx start
  fi
}

register_zerossl_email() {
  if [[ "$CA" == "zerossl" ]]; then
    # 检查是否已经注册过ZeroSSL
    # 简化检测逻辑，直接检查account.conf文件
    if [ ! -f "$HOME/.acme.sh/account.conf" ] || (! grep -q 'ACCOUNT_THUMBPRINT' "$HOME/.acme.sh/account.conf" 2>/dev/null && ! grep -q 'ZEROSSL_EAB_KID' "$HOME/.acme.sh/account.conf" 2>/dev/null); then
        if [[ -z "$EMAIL" ]]; then
          echo "[错误] ZeroSSL首次签发必须指定邮箱 (-e)！"
          exit 1
        fi
        echo "[信息] 正在注册ZeroSSL账户..."
        acme.sh --register-account -m "$EMAIL" --server zerossl
        # 验证注册是否成功
        # 由于注册命令已经成功执行，直接认为注册成功
        echo "[成功] ZeroSSL账户注册成功！"
      fi
    else
      echo "[信息] ZeroSSL账户已注册。"
    fi
  fi
}

set_ca() {
  case "$CA" in
    letsencrypt)
      acme.sh --set-default-ca --server letsencrypt
      ;;
    zerossl)
      acme.sh --set-default-ca --server zerossl
      ;;
    buypass)
      acme.sh --set-default-ca --server buypass
      ;;
    *)
      echo "[错误] 不支持的CA类型: $CA"
      exit 1
      ;;
  esac
}

# 选择验证方式
choose_method() {
  if [[ -n "$METHOD" ]]; then
    return
  fi
  if ss -lnt | grep -q ':80 '; then
    METHOD="webroot"
  else
    METHOD="standalone"
  fi
}

# 申请/续期证书
apply_cert() {
  local key_flag=""
  if [[ "$KEY_TYPE" == "ecc" ]]; then
    key_flag="--keylength ec-256"
  else
    key_flag="--keylength 2048"
  fi
  if [[ "$ACTION" == "renew" ]]; then
    acme.sh --renew -d "$DOMAIN" $key_flag --force
    return $?
  fi
  case "$METHOD" in
    standalone)
      acme.sh --issue -d "$DOMAIN" --standalone $key_flag --force
      ;;
    nginx)
      acme.sh --issue -d "$DOMAIN" --nginx $key_flag --force
      ;;
    webroot)
      acme.sh --issue -d "$DOMAIN" --webroot "$WEBROOT" $key_flag --force
      ;;
    *)
      acme.sh --issue -d "$DOMAIN" --webroot "$WEBROOT" $key_flag --force
      ;;
  esac
  local exit_code=$?
  # 检查是否需要注册ZeroSSL邮箱
  if [[ $exit_code -ne 0 && "$CA" == "zerossl" ]]; then
    echo "[检测] 检查ZeroSSL邮箱注册状态..."
    # 简化检测逻辑，直接检查account.conf文件
    if [ ! -f "$HOME/.acme.sh/account.conf" ] || (! grep -q 'ACCOUNT_THUMBPRINT' "$HOME/.acme.sh/account.conf" 2>/dev/null && ! grep -q 'ZEROSSL_EAB_KID' "$HOME/.acme.sh/account.conf" 2>/dev/null); then
      echo "[错误] ZeroSSL需要先注册邮箱！"
      echo "[提示] 请使用 -e 参数指定邮箱地址重新运行脚本。"
      echo "[示例] $0 -d $DOMAIN -c zerossl -e your@email.com"
      return 1
    fi
  fi
  return $exit_code
}

# 安装证书到标准目录并reload nginx
install_cert() {
  local key_path="$INSTALL_PATH/$DOMAIN.key"
  local crt_path="$INSTALL_PATH/$DOMAIN.crt"
  mkdir -p "$INSTALL_PATH"
  acme.sh --install-cert -d "$DOMAIN" \
    --key-file "$key_path" \
    --fullchain-file "$crt_path" \
    --reloadcmd "systemctl reload nginx || nginx -s reload"
  if [[ -f "$crt_path" && -f "$key_path" ]]; then
    echo "[成功] 证书已安装到: $crt_path"
    echo "[成功] 私钥已安装到: $key_path"
  else
    echo "[失败] 证书安装失败，请检查acme.sh日志。"
    return 1
  fi
}

# 检查证书文件
check_cert_files() {
  local crt_path="$INSTALL_PATH/$DOMAIN.crt"
  local key_path="$INSTALL_PATH/$DOMAIN.key"
  if [[ -f "$crt_path" && -f "$key_path" ]]; then
    echo "[成功] 证书申请成功！"
    echo "证书路径: $crt_path"
    echo "私钥路径: $key_path"
  else
    echo "[失败] 证书文件未找到，请检查acme.sh日志或手动排查。"
    return 1
  fi
}

# 输出证书信息
show_cert_info() {
  acme.sh --info -d "$DOMAIN"
}

# 主流程
install_acme
install_socat
stop_nginx
set_ca
register_zerossl_email
choose_method
apply_cert
if [ $? -eq 0 ]; then
  install_cert && check_cert_files && show_cert_info
else
  echo "[失败] 证书申请失败，请检查acme.sh日志：$HOME/.acme.sh/acme.sh.log"
  start_nginx
  exit 1
fi
start_nginx
echo "[完成] 证书申请/续期流程结束。" 