#!/bin/bash
# 自动部署 Debian + Caddy + TLS + Cloudflare DNS 验证反代
# 用法: ./deploy_caddy_cf.sh <DOMAIN> <UPSTREAM_URL> <CF_API_TOKEN>

set -e

# ------------------------
# 参数检查
# ------------------------
if [ $# -ne 3 ]; then
    echo "Usage: $0 <DOMAIN> <UPSTREAM_URL> <CF_API_TOKEN>"
    echo "Example: $0 example.com https://example-upstream.com abcdef123456"
    exit 1
fi

DOMAIN="$1"
UPSTREAM="$2"
CF_API_TOKEN="$3"

# ------------------------
# 检测 Debian 版本并切换 archive 源
# ------------------------
echo "[*] 检测 Debian 版本..."
VERSION=$(grep -Po '(?<=VERSION_CODENAME=).*' /etc/os-release || true)
if [ -z "$VERSION" ]; then
    echo "[!] 无法检测 Debian 版本，请手动设置 VERSION_CODENAME 变量"
    exit 1
fi
echo "[*] 当前 Debian 版本: $VERSION"

ARCHIVE_SRC="http://archive.debian.org/debian"

cp /etc/apt/sources.list /etc/apt/sources.list.bak
echo "[*] 已备份 /etc/apt/sources.list 到 /etc/apt/sources.list.bak"

cat > /etc/apt/sources.list <<EOF
deb ${ARCHIVE_SRC} $VERSION main contrib non-free
deb-src ${ARCHIVE_SRC} $VERSION main contrib non-free

deb ${ARCHIVE_SRC} $VERSION-updates main contrib non-free
deb-src ${ARCHIVE_SRC} $VERSION-updates main contrib non-free

deb ${ARCHIVE_SRC} $VERSION-backports main contrib non-free
deb-src ${ARCHIVE_SRC} $VERSION-backports main contrib non-free

deb http://security.debian.org/ $VERSION-security main contrib non-free
deb-src http://security.debian.org/ $VERSION-security main contrib non-free
EOF

echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99disable-check-valid-until

echo "[*] 更新软件包列表..."
apt update

# ------------------------
# 安装 Caddy
# ------------------------
echo "[*] 安装 Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# ------------------------
# 写入 Caddyfile（Cloudflare DNS 验证）
# ------------------------
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<EOF
{
    email you@example.com
    acme_dns cloudflare {env.CF_API_TOKEN}
}

$DOMAIN {
    reverse_proxy $UPSTREAM {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    encode gzip
    respond "Caddy 反代已部署成功"
}
EOF

# 设置环境变量供 Caddy 使用
echo "export CF_API_TOKEN=$CF_API_TOKEN" > /etc/profile.d/caddy_cf.sh
chmod +x /etc/profile.d/caddy_cf.sh
source /etc/profile.d/caddy_cf.sh

# ------------------------
# 启用并重载 Caddy
# ------------------------
systemctl enable caddy
systemctl restart caddy

echo "[✅] Caddy + TLS + Cloudflare DNS 验证反代部署完成！"
echo "访问示例: https://$DOMAIN"
