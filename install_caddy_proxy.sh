#!/bin/bash
# 一键安装 Caddy 反代 + 修复 Debian Bullseye 源

set -e

echo "=== 一键安装 Caddy 反代 ==="

# 1️⃣ 输入域名和 Cloudflare Token
read -p "请输入你的域名 (如 proxy.example.com): " DOMAIN
read -p "请输入你的 Cloudflare API Token: " CF_TOKEN

# 2️⃣ 修复 Debian 源
echo "[*] 修复 Debian Bullseye 源..."
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian/ bullseye main contrib non-free
deb http://archive.debian.org/debian/ bullseye-updates main contrib non-free
deb http://archive.debian.org/debian/ bullseye-backports main contrib non-free
EOF
echo 'Acquire::Check-Valid-Until "false";' >/etc/apt/apt.conf.d/99disable-check-valid-until

apt-get update -o Acquire::Check-Valid-Until=false
apt-get install -y curl gnupg lsb-release

# 3️⃣ 安装 Caddy
echo "[*] 安装 Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.sh' | bash
apt-get install -y caddy

# 4️⃣ 配置 Caddyfile
echo "[*] 配置 Caddy..."
cat >/etc/caddy/Caddyfile <<EOF
$DOMAIN:443 {
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

# 5️⃣ 启动 Caddy
echo "[*] 启动 Caddy..."
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy
systemctl status caddy --no-pager

echo "=== 安装完成 ==="
echo "域名: $DOMAIN"
echo "Caddy 已启动并启用 TLS"
