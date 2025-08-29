#!/bin/bash
# VLESS+WS+TLS+Argo 一键脚本 (修复版)

SB_CFG="/etc/sing-box/config.json"

# ========== 基础工具 ==========
need_root(){
  if [[ $EUID -ne 0 ]]; then
    echo "请用 root 运行此脚本"
    exit 1
  fi
}

install_deps(){
  apt update -y
  apt install -y curl wget tar unzip jq socat
}

# ========== 安装 sing-box ==========
install_singbox(){
  echo "安装 sing-box..."
  VER=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
  wget -O /tmp/sb.tar.gz https://github.com/SagerNet/sing-box/releases/download/${VER}/sing-box-${VER#v}-linux-amd64.tar.gz
  tar -xvf /tmp/sb.tar.gz -C /tmp
  cp /tmp/sing-box-*/sing-box /usr/local/bin/
  chmod +x /usr/local/bin/sing-box
}

# ========== 安装 cloudflared ==========
install_cloudflared(){
  echo "安装 cloudflared..."
  wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /usr/local/bin/cloudflared
}

# ========== 用户交互 ==========
interactive(){
  read -rp "请输入 UUID (留空随机生成): " UUID
  [[ -z "$UUID" ]] && UUID=$(cat /proc/sys/kernel/random/uuid)

  read -rp "请输入 WebSocket 路径 (默认 /ws): " WSPATH
  [[ -z "$WSPATH" ]] && WSPATH="/ws"

  read -rp "请输入本地监听端口 (默认 8080): " PORT
  [[ -z "$PORT" ]] && PORT=8080

  read -rp "请选择 Argo 模式 (1=Token隧道  2=Quick Tunnel): " MODE
  [[ -z "$MODE" ]] && MODE=2

  read -rp "请输入节点名称 (默认 vless-node): " NAME
  [[ -z "$NAME" ]] && NAME="vless-node"
}

# ========== 写入 sing-box 配置 ==========
write_singbox_cfg(){
  mkdir -p /etc/sing-box
  cat > $SB_CFG <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "127.0.0.1",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": ""
        }
      ],
      "transport": {
        "type": "ws",
        "path": "$WSPATH"
      },
      "tls": {
        "enabled": false
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF
}

# ========== 启动 sing-box ==========
start_singbox(){
  pkill -9 sing-box >/dev/null 2>&1
  nohup sing-box run -c $SB_CFG >/dev/null 2>&1 &
  sleep 2
}

# ========== 启动 cloudflared ==========
run_argo(){
  if [[ "$MODE" = "1" ]]; then
    echo "请手动配置你的 Cloudflare 隧道 Token 模式"
    DOMAIN="请使用你的自定义域名"
  else
    echo "启动 Quick Tunnel..."
    TMP_FILE=$(mktemp)
    nohup cloudflared tunnel --url http://127.0.0.1:${PORT} >$TMP_FILE 2>&1 &
    for i in {1..20}; do
      sleep 2
      DOMAIN=$(grep -oE "https://[0-9a-zA-Z.-]+trycloudflare.com" $TMP_FILE | head -n1)
      [[ -n "$DOMAIN" ]] && break
    done
    [[ -z "$DOMAIN" ]] && DOMAIN="获取失败"
  fi
  echo "$DOMAIN"
}

# ========== 生成 vless 链接 ==========
generate_vless_link(){
  DOMAIN=$(run_argo)
  VLESS_URL="vless://${UUID}@${DOMAIN#https://}:443?type=ws&security=tls&host=${DOMAIN#https://}&path=${WSPATH}#${NAME}"
  echo -e "\n==== 节点链接 ===="
  echo "$VLESS_URL"
}

# ========== 主流程 ==========
main(){
  need_root
  install_deps
  install_singbox
  install_cloudflared
  interactive
  write_singbox_cfg
  start_singbox
  generate_vless_link
  echo -e "\n完成！配置文件路径: $SB_CFG"
}

main "$@"
