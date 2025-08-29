#!/bin/bash
set -e

CONFIG_FILE="/etc/sing-box/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

# 依赖
apt-get update -y
apt-get install -y curl wget tar unzip jq socat

# 下载最新 sing-box
LATEST_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.assets[] | select(.name | test("linux-amd64\\.tar\\.gz$")) | .browser_download_url')
mkdir -p /usr/local/sing-box
wget -O /tmp/sing-box.tar.gz "$LATEST_URL"
tar -xzf /tmp/sing-box.tar.gz -C /usr/local/sing-box --strip-components=1
ln -sf /usr/local/sing-box/sing-box /usr/local/bin/sing-box

# 交互
read -p "请输入 UUID (留空随机生成): " UUID
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}

read -p "请输入 WebSocket 路径 (默认 /ws): " WSPATH
WSPATH=${WSPATH:-/ws}

read -p "请输入 本地监听端口 (默认 8080): " PORT
PORT=${PORT:-8080}

read -p "请选择 Argo 模式 (1=Token隧道  2=Quick Tunnel): " MODE
MODE=${MODE:-2}

read -p "请输入 节点名称 (默认 vless-node): " NODENAME
NODENAME=${NODENAME:-vless-node}

# Argo 配置
if [ "$MODE" = "1" ]; then
    read -p "请输入你的 Cloudflare 隧道 Token: " ARGO_TOKEN
    read -p "请输入你的自定义域名 (已在CF解析好): " ARGO_DOMAIN
else
    # Quick Tunnel 模式
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    cloudflared tunnel --url http://127.0.0.1:$PORT > /tmp/argo.log 2>&1 &
    sleep 5
    ARGO_DOMAIN=$(grep -oE "https://[a-zA-Z0-9.-]+.trycloudflare.com" /tmp/argo.log | head -n1 | sed 's#https://##')
    ARGO_TOKEN=""
fi

# 生成配置
mkdir -p /etc/sing-box
cat > $CONFIG_FILE <<EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen": "0.0.0.0",
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
    {
      "type": "direct"
    }
  ]
}
EOF

# systemd
cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_FILE
Restart=always
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box --now

# 输出节点
if [ "$MODE" = "1" ]; then
    LINK="vless://$UUID@$ARGO_DOMAIN:443?type=ws&security=tls&host=$ARGO_DOMAIN&path=$WSPATH#$NODENAME"
else
    LINK="vless://$UUID@$ARGO_DOMAIN:443?type=ws&security=tls&host=$ARGO_DOMAIN&path=$WSPATH#$NODENAME"
fi

echo "==== 节点链接 ===="
echo "$LINK"
echo "完成！配置文件路径: $CONFIG_FILE"
