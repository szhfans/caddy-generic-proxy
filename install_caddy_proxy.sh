#!/bin/bash
# =========================================
# VPS 一键部署 AnyTLS 代理（自签名 TLS，443端口，域名直连）
# 支持 Debian/Ubuntu
# =========================================

set -e

# ===== 提示用户输入配置 =====
read -p "请输入你的域名 (默认: example.com): " DOMAIN
DOMAIN=${DOMAIN:-example.com}

read -p "请输入代理密码 (默认: changeme123): " TOKEN
TOKEN=${TOKEN:-changeme123}

read -p "请输入监听端口 (默认: 443): " PORT
PORT=${PORT:-443}

CONFIG_DIR="/etc/proxyserver"
CLIENT_DIR="/root/client_config"

mkdir -p $CONFIG_DIR $CLIENT_DIR

# ===== 安装依赖 =====
apt update -y
apt install -y curl wget unzip socat tar openssl

# ===== 生成自签名证书 =====
CERT_PATH="$CONFIG_DIR/fullchain.pem"
KEY_PATH="$CONFIG_DIR/privkey.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "生成自签名 TLS 证书..."
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -subj "/CN=$DOMAIN"
fi

# ===== 下载 sing-box 最新稳定版 =====
ARCH="amd64"
PLATFORM="linux"
LATEST_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | cut -d '"' -f 4)
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/$LATEST_TAG/sing-box-$PLATFORM-$ARCH.tar.gz"

echo "Downloading sing-box from $DOWNLOAD_URL ..."
wget -O sing-box.tar.gz $DOWNLOAD_URL

# 解压安装
mkdir -p /usr/local/sing-box
tar -zxvf sing-box.tar.gz -C /usr/local/sing-box
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
        "cert_file": "$CERT_PATH",
        "key_file": "$KEY_PATH"
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
echo "AnyTLS 代理部署完成（自签名证书）！"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "密码: $TOKEN"
echo "客户端配置文件已生成: $CLIENT_CONFIG"
echo "证书路径: $CERT_PATH / $KEY_PATH"
echo "注意：客户端需要信任自签名证书"
echo "=============================="
