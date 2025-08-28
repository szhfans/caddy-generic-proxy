#!/usr/bin/env bash
# ============================================================
#  VLESS + WS + TLS + Argo 一键安装脚本 (交互式)
#  sing-box + cloudflared 自动获取最新版本
# ============================================================
set -euo pipefail

Y="\033[33m"; G="\033[32m"; R="\033[31m"; B="\033[36m"; N="\033[0m"
need_root(){ [[ $EUID -ne 0 ]] && echo -e "${R}[错误] 请用 root 运行${N}" && exit 1; }
need_root

INSTALL_DIR="/usr/local/bin"
SB_BIN="${INSTALL_DIR}/sing-box"
SB_SVC="sing-box.service"
SB_ETC="/etc/sing-box"
SB_CFG="${SB_ETC}/config.json"
CFD_BIN="/usr/local/bin/cloudflared"
CFD_SVC="cloudflared-argo.service"
LISTEN_IP="127.0.0.1"
DEF_PORT=40000
DEF_PATH="/vless"
DEF_NAME="VLESS-WS-Argo"

cmd_exists(){ command -v "$1" >/dev/null 2>&1; }
rand_uuid(){ cat /proc/sys/kernel/random/uuid; }
rand_path(){ echo "/"$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'); }

interactive(){
  echo -e "${B}=== 基本信息设置 ===${N}"
  read -rp "备注名称 [默认: ${DEF_NAME}]: " NAME; NAME=${NAME:-$DEF_NAME}
  UUID_DEF=$(rand_uuid)
  read -rp "UUID [默认: ${UUID_DEF}]: " UUID; UUID=${UUID:-$UUID_DEF}
  read -rp "本地监听端口 [默认: ${DEF_PORT}]: " PORT; PORT=${PORT:-$DEF_PORT}
  PATH_DEF=$(rand_path)
  read -rp "WebSocket 路径 [默认: ${DEF_PATH} ; 推荐随机 eg. ${PATH_DEF}]: " WSPATH; WSPATH=${WSPATH:-$DEF_PATH}
  [[ $WSPATH = /* ]] || WSPATH="/${WSPATH}"

  echo -e "\n${B}=== Argo 模式选择 ===${N}"
  echo -e "1) 固定隧道 (Token)"
  echo -e "2) 临时隧道 (Quick Tunnel)"
  read -rp "选择模式 [1/2, 默认 2]: " MODE; MODE=${MODE:-2}
  if [[ "$MODE" = "1" ]]; then read -rp "输入 Cloudflare 隧道 Token: " CFD_TOKEN; fi
}

install_deps(){
  apt-get update -y
  apt-get install -y curl wget tar jq
}

install_singbox(){
  if cmd_exists sing-box; then return; fi
  echo -e "${B}安装 sing-box ...${N}"
  API_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  URL=$(curl -s $API_URL | jq -r '.assets[] | select(.name|test("linux-amd64.tar.gz$")) | .browser_download_url')
  wget -q $URL -O sing-box.tar.gz
  tar -xzf sing-box.tar.gz
  install -m 755 sing-box-*-linux-amd64/sing-box ${SB_BIN}
}

install_cloudflared(){
  if cmd_exists cloudflared; then return; fi
  echo -e "${B}安装 cloudflared ...${N}"
  API_URL="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
  URL=$(curl -s $API_URL | jq -r '.assets[] | select(.name|test("linux-amd64$")) | .browser_download_url')
  wget -q $URL -O cloudflared
  install -m 755 cloudflared ${CFD_BIN}
}

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

write_singbox_service(){
  cat > "/etc/systemd/system/${SB_SVC}" <<EOF
[Unit]
Description=sing-box VLESS-WS
After=network-online.target

[Service]
ExecStart=${SB_BIN} run -c ${SB_CFG}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ${SB_SVC}
}

write_cloudflared_service(){
  mkdir -p /etc/systemd/system
  if [[ "$MODE" = "1" ]]; then
    CMD="${CFD_BIN} tunnel run --token ${CFD_TOKEN}"
  else
    CMD="${CFD_BIN} tunnel --url http://${LISTEN_IP}:${PORT}"
  fi
  cat > "/etc/systemd/system/${CFD_SVC}" <<EOF
[Unit]
Description=cloudflared Argo Tunnel
After=network-online.target

[Service]
ExecStart=${CMD}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable ${CFD_SVC}
  systemctl start ${CFD_SVC}
}

generate_vless_link(){
  if [[ "$MODE" = "1" ]]; then
    DOMAIN="自定义隧道域名"
  else
    DOMAIN=$(${CFD_BIN} tunnel --url http://${LISTEN_IP}:${PORT} 2>&1 | grep -oP 'https://.*trycloudflare.com')
  fi
  VLESS_URL="vless://${UUID}@${DOMAIN}:${PORT}?type=ws&security=tls&host=${DOMAIN}&path=${WSPATH}#${NAME}"
  echo -e "\n${G}==== 节点链接 ====${N}"
  echo "$VLESS_URL"
  echo -e "${G}==== 完成 ====${N}"
}

main(){
  interactive
  install_deps
  install_singbox
  install_cloudflared
  write_singbox_cfg
  write_singbox_service
  write_cloudflared_service
  generate_vless_link
}

main "$@"
