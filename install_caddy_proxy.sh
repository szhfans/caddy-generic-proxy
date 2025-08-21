#!/bin/bash
set -e

# ==========================
# Bullseye 修复 + 安装 Caddy
# ==========================

echo "[*] 修复 Debian Bullseye 源..."
cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian bullseye main contrib non-free
deb http://archive.debian.org/debian bullseye-updates main contrib non-free
deb http://archive.debian.org/debian bullseye-backports main contrib non-free
EOF

# 禁用过期检查
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99disable-check-valid-until

# 更新源
apt-get update -o Acquire::Check-Valid-Until=false
apt-get -y upgrade

# ==========================
# 安装 Caddy
# ==========================
echo "[*] 安装 Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list

apt update
apt install -y caddy

# ==========================
# 配置 Caddy
# ==========================
read -p "请输入你的域名 (如 proxy.example.com): " DOMAIN
read -p "请输入你的 Cloudflare API Token: " CF_TOKEN

cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    encode gzip
    reverse_proxy 127.0.0.1:8080
    tls {
        dns cloudflare $CF_TOKEN
    }
}
EOF

systemctl restart caddy
systemctl enable caddy

echo "[*] Caddy 已安装并启动，域名：$DOMAIN"
