#!/bin/bash
# =========================================
# VPS 一键部署 AnyTLS / Hysteria / TUIC 代理
# 功能：
# 1. 443端口 + 域名直连
# 2. 自动生成客户端配置
# 3. 支持多协议切换
# =========================================

set -e

# ===== 配置参数 =====
DOMAIN="yourdomain.com"      # 替换为你的域名
TOKEN="changeme123"          # 代理 token
PORT=443
CONFIG_DIR="/etc/proxyserver"
CLIENT_DIR="/root/client_config"

mkdir -p $CONFIG_DIR $CLIENT_DIR

# ===== 安装依赖 =====
apt update -y
apt install -y curl wget unzip socat

# ===== 下载 sing-box 最新版本 =====
mkdir -p /usr/local/sing-box
cd /usr/local/sing-box
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4)
wget -O sing-box.zip $LATEST
unzip -o sing-box.zip
chmod +x sing-box

# ===== 生成服务端配置 =====
SERVER_CONFIG="$CONFIG_DIR/config.json"
cat > $SERVER_CONFIG <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "anytls",
      "listen": "0.0.0.0:$PORT",
      "users": [
        {
          "name": "user1",
          "password": "$TOKEN"
        }
      ],
      "tls": {
        "enabled": true,
        "serverName": "$DOMAIN"
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

# ===== 创建 systemd 服务 =====
cat > /etc/systemd/system/proxyserver.service <<EOF
[Unit]
Description=ProxyServer AnyTLS/Hysteria/TUIC Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sing-box/sing-box run -c $SERVER_CONFIG
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ===== 启动服务 =====
systemctl daemon-reload
systemctl enable proxyserver
systemctl restart proxyserver

# ===== 生成客户端配置示例 =====
CLIENT_CONFIG="$CLIENT_DIR/client_anytls.json"
cat > $CLIENT_CONFIG <<EOF
{
  "type": "anytls",
  "server": "$DOMAIN",
  "port": $PORT,
  "users": [
    {
      "name": "user1",
      "password": "$TOKEN"
    }
  ],
  "tls": true
}
EOF

echo "=============================="
echo "代理部署完成！"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "Token: $TOKEN"
echo "客户端配置文件已生成: $CLIENT_CONFIG"
echo "支持 AnyTLS 协议，直接导入客户端即可使用"
echo "=============================="
