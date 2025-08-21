#!/bin/bash
set -e

# ==========================
# Bullseye 修复 + 安装 Caddy
# ==========================

echo "[*] 修复 Debian Bullseye 源..."
cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian/ bullseye main contrib non-free
deb http://archive.debian.org/debian/ bullseye-updates main contrib non-free
deb http://archive.debian.org/debian/ bullseye-backports main contrib non-free
EOF

# 禁用 Check-Valid-Until 避免过期错误
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99disable-check-valid-until

# 更新源
apt-get update -o Acquire::Check-Valid-Until=false
apt-get upgrade -y

# ==========================
# 安装 Caddy
# ==========================
echo "[*] 安装 Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -

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
    route {
        @upstream {
            query url
        }
        reverse_proxy @upstream {
            header_up Host {http.reverse_proxy.upstream.hostport}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    tls {
        dns cloudflare $CF_TOKEN
    }
}
EOF

# 启动 Caddy
systemctl restart caddy
systemctl enable caddy

echo "[*] Caddy 已安装并启动，域名：$DOMAIN"
