#!/bin/bash
# =========================================
# VPS 一键部署 AnyTLS 代理（443端口，域名直连）
# 自动生成客户端配置文件
# 支持 Debian/Ubuntu
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

# ===== 下载 sing-box 最新稳定版 =====
ARCH="amd64"
PLATFORM="linux"
LATEST_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/$LATEST_TAG/sing-box-$PLATFORM-$ARCH.zip"

echo "Downloading sing-box from $DOWNLOAD_URL ..."
wget -O sing-box.zip $DOWNLOAD_URL

# 检查下载是否成功
if [ ! -f sing-box.zip ]; then
    echo "下载失败，请检查网络或手动下载"
    exit 1
fi

# 解压安装
mkdir -p /usr/local/sing-box
unzip -o sing-box.zip -d /usr/local/sing-box
chmod +x /usr/local/sing-box/sing-box

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
Description=ProxyServer AnyTLS Service
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

# ===== 生成客户端配置 =====
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
echo "AnyTLS 代理部署完成！"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "Token: $TOKEN"
echo "客户端配置文件已生成: $CLIENT_CONFIG"
echo "支持 AnyTLS 协议，直接导入客户端即可使用"
echo "=============================="
