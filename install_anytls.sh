#!/bin/bash

# ===============================
# AnyTLS + Sing-box 一键部署脚本
# ===============================

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本！"
    exit 1
fi

# 更新系统并安装必要工具
apt update && apt install -y wget curl tar unzip socat lsof openssl jq

# -------------------------------
# 用户输入
# -------------------------------
read -p "请输入你的域名 (必须解析到本 VPS): " DOMAIN
read -p "请输入代理端口 (建议 443): " PORT
read -p "请输入任意密码: " PASSWORD

# -------------------------------
# 证书路径
# -------------------------------
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"

# -------------------------------
# 安装 Certbot 并尝试获取证书
# -------------------------------
apt install -y certbot

echo "尝试申请 TLS 证书，请确保域名已正确解析到本 VPS..."
certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
if [ $? -ne 0 ]; then
    echo "Let's Encrypt 证书申请失败，使用自签名证书代替..."
    mkdir -p /etc/sing-box/cert
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/sing-box/cert/privkey.pem \
      -out /etc/sing-box/cert/fullchain.pem \
      -subj "/CN=$DOMAIN"
    CERT_FILE="/etc/sing-box/cert/fullchain.pem"
    KEY_FILE="/etc/sing-box/cert/privkey.pem"
    CERT_TYPE="自签名"
else
    CERT_TYPE="Let's Encrypt"
fi

# -------------------------------
# 下载最新 sing-box
# -------------------------------
echo "正在下载最新 Sing-box..."
LATEST_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
| jq -r '.assets[] | select(.name|test("linux-amd64.tar.gz")) | .browser_download_url')
wget -O sing-box.tar.gz $LATEST_URL
tar -xzf sing-box.tar.gz
chmod +x sing-box
mv sing-box /usr/local/bin/

# -------------------------------
# 生成 sing-box 配置
# -------------------------------
CONFIG_FILE="/etc/sing-box.json"

cat > $CONFIG_FILE <<EOF
{
  "inbounds": [
    {
      "type": "anytls",
      "listen": "0.0.0.0",
      "listen_port": $PORT,
      "password": "$PASSWORD",
      "transport": {
        "type": "tcp"
      },
      "tls": {
        "cert": "$CERT_FILE",
        "key": "$KEY_FILE"
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

# -------------------------------
# 创建 systemd 服务
# -------------------------------
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box AnyTLS Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动并开机自启
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# -------------------------------
# 自动生成客户端配置
# -------------------------------
CLIENT_CONFIG_FILE="/root/anytls-client.json"

cat > $CLIENT_CONFIG_FILE <<EOF
{
  "type": "anytls",
  "server": "$DOMAIN",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "tls": {
    "insecure": $( [ "$CERT_TYPE" == "自签名" ] && echo true || echo false )
  }
}
EOF

# -------------------------------
# 输出信息
# -------------------------------
echo "====================================="
echo "Sing-box AnyTLS 代理部署完成！"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "密码: $PASSWORD"
echo "证书类型: $CERT_TYPE"
echo "服务状态: systemctl status sing-box"
echo "客户端配置文件: $CLIENT_CONFIG_FILE"
if [ "$CERT_TYPE" == "自签名" ]; then
    echo "⚠️ 由于使用自签名证书，客户端需设置 'insecure': true 来跳过 TLS 验证。"
fi
echo "====================================="
