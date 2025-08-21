#!/bin/bash
set -e

# ------------------------
# 用户自定义
# ------------------------
DOMAIN="proxy.yourdomain.com"  # <- 改成你的域名

# ------------------------
# 安装 Caddy
# ------------------------
echo "[*] 安装 Caddy ..."
sudo apt update
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo tee /etc/apt/trusted.gpg.d/caddy-stable.asc
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# ------------------------
# 配置 Caddyfile
# ------------------------
echo "[*] 配置 Caddy 泛用代理 ..."
CADDYFILE="/etc/caddy/Caddyfile"

sudo tee $CADDYFILE > /dev/null <<EOF
# 泛用 Cloudflare 反代
$DOMAIN {

    @proxy {
        query url *
    }

    handle @proxy {
        reverse_proxy {query.url} {
            header_up Host {http.request.uri.host}
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    respond "Usage: https://$DOMAIN/?url=https://example.com"
}
EOF

# ------------------------
# 重载 Caddy
# ------------------------
echo "[*] 启动 Caddy ..."
sudo systemctl reload caddy

echo "[✅] 安装完成！"
echo "访问示例: https://$DOMAIN/?url=https://example.com"