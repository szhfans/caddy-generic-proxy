#!/bin/bash
set -e

echo "请 输 入 你 自 己 的 域 名 (如 proxy.example.com):"
read DOMAIN
echo "请 输 入 你 的 Cloudflare API Token (用 于 TLS DNS 验 证):"
read CF_TOKEN

# 修复 Bullseye 源问题
echo "[*] 配置 Debian Bullseye Archive 源..."
cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian/ bullseye main contrib non-free
deb http://archive.debian.org/debian/ bullseye-updates main contrib non-free
deb http://archive.debian.org/debian/ bullseye-backports main contrib non-free
EOF
echo 'Acquire::Check-Valid-Until "false";' >/etc/apt/apt.conf.d/99disable-check-valid-until

# 更新系统
apt-get update -o Acquire::Check-Valid-Until=false
apt-get install -y curl sudo gnupg2 lsb-release

# 安装 Caddy
echo "[*] 安 装 Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.sh' | bash
apt-get install -y caddy

# 配置 Caddy
echo "[*] 配置 Caddy 反代..."
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

# 启动 Caddy
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

echo "[*] Caddy 安装并启动完成！"
echo "访问 https://$DOMAIN 测试反代是否成功"
