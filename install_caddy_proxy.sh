#!/bin/bash
# 自动检测 Debian 版本并切换 archive 源，同时安装 Caddy 并配置反代 CF 保护网站

set -e

# ------------------------
# 检测 Debian 版本
# ------------------------
echo "[*] 检测 Debian 版本..."
VERSION=$(grep -Po '(?<=VERSION_CODENAME=).*' /etc/os-release || true)
if [ -z "$VERSION" ]; then
    echo "[!] 无法检测 Debian 版本，请手动设置 VERSION_CODENAME 变量"
    exit 1
fi
echo "[*] 当前 Debian 版本: $VERSION"

# ------------------------
# 切换到 archive 源（旧系统可用）
# ------------------------
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
apt update

echo "[*] 系统软件包已更新（可选升级可手动执行 apt upgrade -y）"

# ------------------------
# 安装 Caddy
# ------------------------
if ! command -v caddy >/dev/null 2>&1; then
    echo "[*] 安装 Caddy..."
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | apt-key add -
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
fi

# ------------------------
# 提示用户输入域名和 CF API Token
# ------------------------
read -p "请输入你的域名（用于 TLS 证书申请）: " DOMAIN
read -s -p "请输入 Cloudflare API Token（用于 TLS DNS 验证）: " CF_API_TOKEN
echo -e "\n[*] 域名: $DOMAIN"
echo "[*] CF API Token 已获取"

# ------------------------
# 生成 Caddyfile
# ------------------------
mkdir -p /etc/caddy
cat > /etc/caddy/Caddyfile <<EOF
:443 {
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

echo "[*] Caddyfile 已生成"

# ------------------------
# 启用并启动 Caddy
# ------------------------
systemctl enable caddy
systemctl restart caddy

echo "[✅] 安装完成！"
echo "访问示例: https://$DOMAIN/?url=https://any-cloudflare-protected-site.com"
