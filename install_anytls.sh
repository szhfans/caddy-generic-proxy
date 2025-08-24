#!/bin/bash
# AnyTLS 一键安装脚本（自签证书版，交互式端口+节点链接）

set -e

# 颜色输出
green(){ echo -e "\033[32m$1\033[0m"; }
red(){ echo -e "\033[31m$1\033[0m"; }

# 检查root
[[ $EUID -ne 0 ]] && red "请使用 root 运行此脚本" && exit 1

# 输入端口
read -p "请输入 AnyTLS 监听端口 [默认:443]：" PORT
PORT=${PORT:-443}

# 输入密码
read -p "请输入连接密码 [默认:changeme123]：" PASSWORD
PASSWORD=${PASSWORD:-changeme123}

# 安装依赖
green "[1/5] 安装依赖..."
apt update -y
apt install -y curl wget unzip socat openssl

# 创建目录
mkdir -p /etc/anytls
cd /etc/anytls

# 下载 AnyTLS 最新版本 (示例用 v0.9.7)
green "[2/5] 下载 AnyTLS..."
ANYTLS_VER="0.9.7"
wget -N https://github.com/anytls/anytls/releases/download/v${ANYTLS_VER}/anytls-linux-amd64.zip
unzip -o anytls-linux-amd64.zip
chmod +x anytls

# 生成自签证书
green "[3/5] 生成自签证书..."
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=AnyTLS/OU=Server/CN=example.com" \
  -keyout /etc/anytls/anytls.key -out /etc/anytls/anytls.crt

# 生成配置文件
green "[4/5] 创建配置文件..."
cat > /etc/anytls/config.json <<EOF
{
  "listen": ":${PORT}",
  "cert": "/etc/anytls/anytls.crt",
  "key": "/etc/anytls/anytls.key",
  "auth": {
    "mode": "password",
    "password": "${PASSWORD}"
  }
}
EOF

# systemd 服务
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
After=network.target

[Service]
ExecStart=/etc/anytls/anytls -config /etc/anytls/config.json
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
green "[5/5] 启动 AnyTLS..."
systemctl daemon-reload
systemctl enable anytls
systemctl restart anytls

# 获取公网IP
SERVER_IP=$(curl -s ipv4.icanhazip.com || echo "YOUR_SERVER_IP")

# 生成节点链接
NODE_URL="anytls://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1"

green "✅ AnyTLS 已安装并运行成功！"
green "=============================="
green " 服务端口: ${PORT}"
green " 用户密码: ${PASSWORD}"
green " 证书路径: /etc/anytls/anytls.crt"
green " 节点链接: ${NODE_URL}"
green "=============================="
