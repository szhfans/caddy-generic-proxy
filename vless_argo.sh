#!/usr/bin/env bash
set -euo pipefail

# ---------- 配色 ----------
Y="\033[33m"; G="\033[32m"; R="\033[31m"; B="\033[36m"; N="\033[0m"

# ---------- 全局变量 ----------
INSTALL_DIR="/usr/local/bin"
SB_BIN="${INSTALL_DIR}/sing-box"
SB_ETC="/etc/sing-box"
SB_CFG="${SB_ETC}/config.json"
LISTEN_IP="127.0.0.1"
DEF_PORT=40000
DEF_PATH="/vless"
DEF_NAME="VLESS-WS-Argo"

cmd_exists(){ command -v "$1" >/dev/null 2>&1; }
rand_uuid(){ cat /proc/sys/kernel/random/uuid; }
rand_path(){ echo "/"$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'); }
need_root(){ [[ $EUID -ne 0 ]] && echo -e "${R}[错误] 请用 root 运行${N}" && exit 1; }
need_root

# ---------- 交互 ----------
interactive(){
  echo -e "${B}=== 基本信息设置 ===${N}"
  read -rp "备注名称 [默认: ${DEF_NAME}]: " NAME; NAME=${NAME:-$DEF_NAME}
  UUID_DEF=$(rand_uuid)
  read -rp "UUID [默认: ${UUID_DEF}]: " UUID; UUID=${UUID:-$UUID_DEF}
  read -rp "本地监听端口 [默认: ${DEF_PORT}]: " PORT; PORT=${PORT:-$DEF_PORT}
  PATH_DEF=$(rand_path)
  read -rp "WebSocket 路径 [默认: ${DEF_PATH}; 推荐随机 eg. ${PATH_DEF}]: " WSPATH; WSPATH=${WSPATH:-$DEF_PATH}
  [[ $WSPATH = /* ]] || WSPATH="/${WSPATH}"

  echo -e "\n${B}=== Argo 模式选择 ===${N}"
  echo -e "1) 固定隧道 (Token)"
  echo -e "2) 临时隧道 (Quick Tunnel)"
  read -rp "选择模式 [1/2, 默认 2]: " MODE; MODE=${MODE:-2}
  if [[ "$MODE" = "1" ]]; then read -rp "输入 Cloudflare 隧道 Token: " CFD_TOKEN; fi
}

# ---------- 安装依赖 ----------
install_deps(){
  apt-get update -y
  apt-get install -y curl wget tar jq
}

# ---------- 安装 sing-box ----------
install_singbox(){
  if cmd_exists sing-box; then return; fi
  echo -e "${B}安装 sing-box ...${N}"
  API_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  URL=$(curl -s $API_URL | jq -r '.assets[] | select(.name|test("linux-amd64.tar.gz$")) | .browser_download_url')
  wget -q $URL -O sing-box.tar.gz
  tar -xzf sing-box.tar.gz
  install -m 755 sing-box-*-linux-amd64/sing-box ${SB_BIN}
}

# ---------- 安装 cloudflared ----------
install_cloudflared(){
  if cmd_exists cloudflared; then return; fi
  echo -e "${B}安装 cloudflared ...${N}"
  API_URL="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
  URL=$(curl -s $API_URL | jq -r '.assets[] | select(.name|test("linux-amd64$")) | .browser_download_url')
  wget -q $URL -O cloudflared
  install -m 755 cloudflared /usr/local/bin/cloudflared
}

# ---------- 写 sing-box 配置 ----------
write_singbox_cfg(){
  mkdir -p "$SB_ETC"
  cat > "$SB_CFG" <<EOF
{
  "inbounds": [{
    "type": "vless",
    "listen": "${LISTEN_IP}",
    "listen_port": ${PORT},
    "users": [{"uuid": "${UUID}"}],
    "transport": {"type":"ws","path":"${WSPATH}"}
  }],
  "outbounds": [{"type":"direct"}]
}
EOF
}

# ---------- 启动 sing-box ----------
start_singbox(){
  echo -e "${B}启动 sing-box ...${N}"
  nohup sing-box run -c ${SB_CFG} >/dev/null 2>&1 &
}

# ---------- 启动 cloudflared Quick Tunnel 或 Token ----------
run_argo(){
  if [[ "$MODE" = "1" ]]; then
    echo -e "${B}使用固定 Token 隧道，请确保你已创建 Cloudflare 隧道${N}"
    DOMAIN="请使用你的自定义域名"
  else
    echo -e "${B}启动 Quick Tunnel 并获取域名...${N}"
    DOMAIN=""
    TMP_FILE=$(mktemp)
    nohup cloudflared tunnel --url http://${LISTEN_IP}:${PORT} >$TMP_FILE 2>&1 &
    PID=$!
    echo -e "${B}等待 Quick Tunnel 启动 (最多 30 秒)...${N}"
    for i in {1..30}; do
      sleep 1
      DOMAIN=$(grep -oP 'https://.*trycloudflare.com' $TMP_FILE | head -n1 || true)
      if [[ -n "$DOMAIN" ]]; then break; fi
    done
    if [[ -z "$DOMAIN" ]]; then
      DOMAIN="请检查 cloudflared 是否启动"
    fi
  fi
  echo "$DOMAIN"
}

# ---------- 生成 vless 链接 ----------
generate_vless_link(){
  DOMAIN=$(run_argo)
  VLESS_URL="vless://${UUID}@${DOMAIN}:${PORT}?type=ws&security=tls&host=${DOMAIN}&path=${WSPATH}#${NAME}"
  echo -e "\n${G}==== 节点链接 ====${N}"
  echo "$VLESS_URL"
  echo -e "${G}==== 完成 ====${N}"
}

# ---------- 主流程 ----------
main(){
  need_root
  interactive
  install_deps
  install_singbox
  install_cloudflared
  write_singbox_cfg
  start_singbox
  generate_vless_link
}

main "$@"
