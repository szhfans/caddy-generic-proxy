#!/bin/bash
set -e

# --------- 修复 Bullseye 源 ----------
echo "[*] 修复 Debian Bullseye 源..."
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian/ bullseye main contrib non-free
deb http://archive.debian.org/debian/ bullseye-updates main contrib non-free
deb http://archive.debian.org/debian/ bullseye-backports main contrib non-free
deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
EOF
echo 'Acquire::Check-Valid-Until "false";' >/etc/apt/apt.conf.d/99disable-check-valid-until
apt-get update -o Acquire::Check-Valid-Until=false
apt-get upgrade -y

# --------- 安装 Caddy ----------
echo "[*] 安装 Caddy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

# --------- 提示用户输入 ----------
read -p "请输入你自己的域名 (如 proxy.example.com): " DOMAIN
read -p "请输入你的 Cloudflare API Token (用于 TLS DNS 验证): " CF_TOKEN

# --------- 配置 Caddyfile ----------
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

# --------- 启动 Caddy ----------
echo "[*] 启动 Caddy..."
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

echo "[*] 安装和配置完成！请确认 $DOMAIN 已解析到本 VPS IP。"
