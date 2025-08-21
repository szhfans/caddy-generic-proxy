#!/bin/bash

# 提示用户输入
read -p "请输入你自己的域名 (如 proxy.example.com): " DOMAIN
read -p "请输入你的 Cloudflare API Token (用于 TLS DNS 验证): " CF_TOKEN

echo "[*] 替换 Debian 源为官方镜像..."
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://deb.debian.org/debian bullseye-backports main contrib non-free
EOF

echo "[*] 更新 apt 并安装必要软件..."
apt update -y
apt install -y curl sudo

echo "[*] 安装 Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update -y
apt install -y caddy

echo "[*] 写入 Caddyfile..."
cat > /etc/caddy/Caddyfile <<EOF
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

echo "[*] 重载并启动 Caddy..."
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

echo "[✅] 安装完成！"
echo "访问示例: https://$DOMAIN"
