#!/bin/bash
# AnyTLS 一键安装脚本（自签证书版）
# 自动识别架构 + 最新版本 + 节点链接

set -e

# 颜色输出
green(){ echo -e "\033[32m$1\033[0m"; }
red(){ echo -e "\033[31m$1\033[0m"; }

# 检查 root
[[ $EUID -ne 0 ]] && red "请使用 root 运行此脚本" && exit 1

# 输入端口
read -p "请输入 AnyTLS 监听端口 [默认:443]：" PORT
PORT=${PORT:-443}

# 输入密码（支持环境变量 ANYTLS_PASS）
read -p "请输入连接密码 [默认:changeme123]：" PASSWORD_INPUT
PASSWORD=${PASSWORD_INPUT:-${ANYTLS_PASS:-changeme123}}

# 安装依赖
green "[1/5] 安装依赖..."
apt update -y
apt install -y curl wget unzip openssl socat

# 创建目录
mkdir -p /etc/anytls
cd /etc/anytls

# 获取架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    *) red "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 获取最新版本
green "[2/5] 获取 AnyTLS 最新版本..."
ANYTLS_VER=$(curl -s https://api.github.com/repos/anytls/anytls/releases/latest | grep tag_name | cut -d '"' -f 4)

# fallback 防止 API 失效
if [[ -z "$ANYTLS_VER" ]]; then
    green "⚠️ GitHub API 获取失败，使用默认版本 v1.0.0"
    ANYTLS_VER="v1.0.0"
fi

# 下载
green "[3/5] 下载 AnyTLS ${ANYTLS_VER} (${ARCH})..."
wget -N https://github.com/anytls/anytls/releases/download/${ANYTLS_VER}/anytls-linux-${ARCH}.zip
unzip -o anytls-linux-${ARCH}.zip
chmod +x anytls

# 获取公网 IP（多重兜底）
SERVER_IP=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")

# 生成自签证书（CN 动态使用服务器 IP）
green "[4/5] 生成自签证书..."
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=AnyTLS/OU=Server/CN=${SERVER_IP}" \
  -keyout /etc/anytls/anytls.key -out /etc/anytls/anytls.crt

# 写配置文件
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
WorkingDirectory=/etc/anytls
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

# 节点链接
NODE_URL="anytls://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1"

green "✅ AnyTLS 已安装并运行成功！"
green "=============================="
green " 服务端口: ${PORT}"
green " 用户密码: ${PASSWORD}"
green " 证书路径: /etc/anytls/anytls.crt"
green " 节点链接: ${NODE_URL}"
green "=============================="
