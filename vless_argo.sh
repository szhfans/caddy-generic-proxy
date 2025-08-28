#!/usr/bin/env bash
# ============================================================
#  VLESS + WS + TLS(Cloudflare) + Argo 一键安装脚本 (交互式)
#  支持：Debian/Ubuntu (amd64/arm64)
#  核心：sing-box + cloudflared (Argo Tunnel)
# ============================================================
set -euo pipefail

# ---------- 配色 ----------
Y="\033[33m"; G="\033[32m"; R="\033[31m"; B="\033[36m"; N="\033[0m"

need_root(){ if [[ $EUID -ne 0 ]]; then echo -e "${R}[错误] 请使用 root 运行本脚本${N}"; exit 1; fi; }
need_root

# ---------- 全局默认 ----------
INSTALL_DIR="/usr/local/bin"
SB_BIN="${INSTALL_DIR}/sing-box"
SB_SVC="sing-box.service"
SB_ETC="/etc/sing-box"
SB_CFG="${SB_ETC}/config.json"
CFD_BIN="/usr/local/bin/cloudflared"
CFD_LOG="/var/log/cloudflared.log"
CFD_SVC="cloudflared-argo.service"
LISTEN_IP="127.0.0.1"
DEF_PORT=40000
DEF_PATH="/vless"
DEF_NAME="VLESS-WS-Argo"
DEF_ALPN="h2,http/1.1"
DEF_FP="chrome"

# ---------- 工具函数 ----------
cmd_exists(){ command -v "$1" >/dev/null 2>&1; }
rand_uuid(){ cat /proc/sys/kernel/random/uuid; }
rand_path(){ echo "/"$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n') ; }
trim(){ sed -e 's/^\s\+//' -e 's/\s\+$//'; }

# ---------- 交互 ----------
interactive(){
  echo -e "${B}=== 基本信息设置 ===${N}"
  read -rp "自定义备注名称 [默认: ${DEF_NAME}]: " NAME; NAME=${NAME:-$DEF_NAME}

  UUID_DEF=$(rand_uuid)
  read -rp "VLESS UUID [默认: 自动生成 ${UUID_DEF}]: " UUID; UUID=${UUID:-$UUID_DEF}

  read -rp "本地监听端口 [默认: ${DEF_PORT}]: " PORT; PORT=${PORT:-$DEF_PORT}

  PATH_DEF=$(rand_path)
  read -rp "WebSocket 路径 [默认: ${DEF_PATH}; 推荐随机 eg. ${PATH_DEF}]: " WSPATH; WSPATH=${WSPATH:-$DEF_PATH}
  [[ $WSPATH = /* ]] || WSPATH="/${WSPATH}"

  echo -e "\n${B}=== Argo 模式选择 ===${N}"
  echo -e "1) 固定隧道 (Token 模式)"
  echo -e "2) 快速临时隧道 (Quick Tunnel)"
  echo -e "3) 使用已存在的命名隧道"
  read -rp "选择模式 [1/2/3, 默认 2]: " MODE; MODE=${MODE:-2}

  case "$MODE" in
    1) read -rp "输入 Cloudflare 隧道 Token: " CFD_TOKEN; CFD_TOKEN=$(echo "$CFD_TOKEN"|trim) ;;
    2) echo -e "${Y}将创建 Quick Tunnel，域名为随机 *.trycloudflare.com${N}" ;;
    3) read -rp "输入 credentials.json 路径: " CREDS; CREDS=$(echo "$CREDS"|trim) ;;
    *) MODE=2 ;;
  esac
}

# ---------- 安装依赖 ----------
install_deps(){
  apt-get update -y
  apt-get install -y curl wget tar unzip jq socat
}

# ---------- 安装 sing-box ----------
install_singbox(){
  if cmd_exists sing-box; then return; fi
  bash <(curl -fsSL https://sing-box.sagernet.org/install.sh)
}

# ---------- 安装 cloudflared ----------
install_cloudflared(){
  if cmd_exists cloudflared; then return; fi
  curl -fsSL https://pkg.cloudflare.com/gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(. /etc/os-release && echo $VERSION_CODENAME) main" \
    | tee /etc/apt/sources.list.d/cloudflared.list
  apt-get update -y && apt-get install -y cloudflared
}

# ---------- 写入 sing-box 配置 ----------
write_singbox_cfg(){
  mkdir -p "$SB_ETC"
  cat > "$SB_CFG" <<EOF
{
  "inbounds": [{
    "type": "vless",
    "listen": "${LISTEN_IP}",
    "listen_port": ${PORT},
    "users": [{"uuid": "${UUID}"}],
    "transport": {
      "type": "ws",
      "path": "${WSPATH}"
    }
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
}

# ---------- systemd 服务 ----------
write_singbox_service(){
  cat > "/etc/systemd/system/${SB_SVC}" <<EOF
[Unit]
Description=sing-box VLESS-WS
After=network-online.target

[Service]
ExecStart=${SB_BIN} run -c ${SB_CFG}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ${SB_SVC}
}

# ---------- 主流程 ----------
main(){
  interactive
  install_deps
  install_singbox
  install_cloudflared
  write_singbox_cfg
  write_singbox_service
  echo -e "\n${G}安装完成！sing-box 配置路径: ${SB_CFG}${N}"
}
main "$@"
