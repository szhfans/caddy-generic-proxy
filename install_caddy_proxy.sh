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
apt update && apt install -y wget curl tar unzip socat lsof

# -------------------------------
# 用户输入
# -------------------------------
read -p "请输入你的域名 (必须解析到本 VPS): " DOMAIN
read -p "请输入代理端口 (建议 443): " PORT
read -p "请输入任意密码: " PASSWORD

# -------------------------------
# 安装 Certbot 获取 TLS 证书
# -------------------------------
apt install -y certbot

echo "正在申请 TLS 证书，请确保域名已正确解析到本 VPS..."
certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
if [ $? -ne 0 ]; then
    echo "TLS 证书申请失败，请检查域名解析或证书限额。"
    exit 1
fi

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"

# -------------------------------
# 下载最新 sing-box
# -------------------------------
echo "正在下载最新 Sing-box..."
LATEST_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
| grep "browser_download_url.*linux-amd64.tar.gz" | cut -d '"' -f 4)
wget -O sing-box.tar.gz $LATEST_URL
tar -xzf sing-box.tar.gz
chmod +x sing-box

# 移动到 /usr/local/bin
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

echo "====================================="
echo "Sing-box AnyTLS 代理部署完成！"
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "密码: $PASSWORD"
echo "服务状态: systemctl status sing-box"
echo "====================================="
