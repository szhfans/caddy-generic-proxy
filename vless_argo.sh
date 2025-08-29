#!/bin/bash
set -e

# ========== 配置 ==========
CONFIG_FILE="/etc/sing-box/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
ARGO_LOG="/tmp/argo.log"
SING_BOX_BIN="/usr/local/bin/sing-box"
CF_BIN="/usr/local/bin/cloudflared"

# ========== 前置 ==========
apt update -y
apt install -y curl wget tar unzip jq socat

# 下载最新 sing-box
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
wget -O /tmp/sb.tar.gz https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${LATEST}-linux-amd64.tar.gz
tar -xzf /tmp/sb.tar.gz -C /tmp
install -m 755 /tmp/sing-box-${LATEST}-linux-amd64/sing-box $SING_BOX_BIN

# 下载 cloudflared
wget -O $CF_BIN https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x $CF_BIN

# ========== 用户输入 ==========
read -p "请输入 UUID (留空自动生成): " UUID
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}

read -p "请输入 WebSocket 路径 (默认 /ws): " WSPATH
WSPATH=${WSPATH:-/ws}

read -p "请输入本地监听端口 (默认 8080): " PORT
PORT=${PORT:-8080}

read -p "请输入节点名称 (默认 vless-argo): " NODENAME
NODENAME=${NODENAME:-vless-argo}

# ========== 写配置 ==========
mkdir -p /etc/sing-box

cat > $CONFIG_FILE <<EOF
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "users": [
        { "uuid": "$UUID" }
      ],
      "transport": {
        "type": "ws",
        "path": "$WSPATH"
      },
      "tls": {}
    }
  ],
  "outbounds": [
    { "type": "direct" },
    { "type": "block" }
  ]
}
EOF

# ========== systemd ==========
cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=$SING_BOX_BIN run -c $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ========== 启动 cloudflared Quick Tunnel ==========
pkill -f "cloudflared" || true
nohup $CF_BIN tunnel --no-autoupdate --url http://127.0.0.1:$PORT > $ARGO_LOG 2>&1 &

# 等待生成域名
echo "等待 Cloudflare Quick Tunnel 建立..."
sleep 5
DOMAIN=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" $ARGO_LOG | head -n1 | sed 's#https://##')

if [ -z "$DOMAIN" ]; then
  echo "❌ 获取 Argo 隧道域名失败，请检查 cloudflared 日志：$ARGO_LOG"
  exit 1
fi

# ========== 输出节点 ==========
VLESS_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WSPATH}#${NODENAME}"

echo "==== 节点链接 ===="
echo $VLESS_LINK
echo "配置文件路径: $CONFIG_FILE"
