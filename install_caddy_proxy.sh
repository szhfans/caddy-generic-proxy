#!/bin/bash
# 自动部署 Caddy 反代 CF 保护网站
# 说明：使用自己的域名访问所有 CF 验证网站

set -e

# 提示用户输入域名和 Cloudflare API Token
read -p "请输入你自己的域名 (如 proxy.example.com): " DOMAIN
read -p "请输入你的 Cloudflare API Token (用于 TLS DNS 验证): " CF_API_TOKEN

# 安装 Caddy（Debian 系统示例）
echo "[*] 安装 Caddy..."
apt update
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.sh' | bash
apt install -y caddy

# 创建 Caddyfile 配置
echo "[*] 写入 /etc/caddy/Caddyfile ..."
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
        dns cloudflare $CF_API_TOKEN
    }
}
EOF

# 重载并启动 Caddy
echo "[*] 启动并重载 Caddy ..."
systemctl daemon-reload
systemctl enable caddy
systemctl restart caddy

echo "[✅] 完成！"
echo "访问示例: https://$DOMAIN/?url=https://example.com"
