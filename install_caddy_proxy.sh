#!/bin/bash
set -e

echo "[*] 修复 Debian Bullseye 源..."
# 备份原 sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 写入 Archive 源
cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian/ bullseye main contrib non-free
deb http://archive.debian.org/debian/ bullseye-updates main contrib non-free
deb http://archive.debian.org/debian-security bullseye-security main contrib non-free
deb http://archive.debian.org/debian/ bullseye-backports main contrib non-free
EOF

# 禁用有效期检查
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99disable-check-valid-until

echo "[*] 更新软件源并安装依赖..."
apt update -y
apt install -y curl sudo gnupg2 lsb-release

echo "[*] 安装 Caddy..."
# 官方安装方式
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.sh' | bash
apt install -y caddy

# 让用户输入信息
read -p "请输入你自己的域名 (如 proxy.example.com): " DOMAIN
read -p "请输入你的 Cloudflare API Token (用于 TLS DNS 验证): " CF_TOKEN

# 写入 Caddyfile
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN:443 {
    encode gzip
    reverse_proxy {
        header_up Host {http.reverse_proxy.upstream.hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
    tls {
        dns cloudflare $CF_TOKEN
    }
}
EOF

echo "[*] 启动并启用 Caddy 服务..."
systemctl enable caddy
systemctl restart caddy

echo "[*] 安装完成！你可以通过 https://$DOMAIN 访问你的代理服务"
