#!/bin/bash
# 一键配置 Debian archive 源 + 安装/配置 Caddy

set -e

echo "[*] 检测 Debian 版本..."
VERSION=$(grep -Po '(?<=VERSION_CODENAME=).*' /etc/os-release || true)
if [ -z "$VERSION" ]; then
    echo "[!] 无法检测 Debian 版本，请手动设置 VERSION_CODENAME 变量"
    exit 1
fi
echo "[*] 当前 Debian 版本: $VERSION"

# 定义 archive 源
ARCHIVE_SRC="http://archive.debian.org/debian"

# 备份 sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.bak
echo "[*] 已备份 /etc/apt/sources.list 到 /etc/apt/sources.list.bak"

# 写入新的 archive 源
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

echo "[*] sources.list 已更新为 archive 源"

# 配置 APT 允许使用过期签名
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99disable-check-valid-until

echo "[*] 更新软件包列表..."
apt update

echo "[*] 升级系统（可选，若要自动升级可取消注释）"
# apt upgrade -y
# apt full-upgrade -y

# ------------------------
# 安装 Caddy（如果未安装）
# ------------------------
if ! command -v caddy &> /dev/null; then
    echo "[*] 未检测到 Caddy，开始安装..."
    
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg2
    
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install -y caddy
    
    sudo systemctl enable caddy
    sudo systemctl start caddy
    echo "[✅] Caddy 安装完成并已启动"
else
    echo "[*] 已检测到 Caddy，跳过安装"
fi

# ------------------------
# 配置 Caddyfile
# ------------------------
# 设置你的域名
DOMAIN="yourdomain.com"

# 确保 Caddy 配置目录存在
sudo mkdir -p /etc/caddy

# 写入 Caddyfile
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOF
https://$DOMAIN {
    reverse_proxy / {
        to http://127.0.0.1:8080
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    respond "Usage: https://$DOMAIN/?url=https://example.com"
}
EOF

# 重载 Caddy
echo "[*] 重载 Caddy ..."
sudo systemctl reload caddy || echo "[!] Caddy 可能未启动，跳过重载"

echo "[✅] 脚本执行完成！"
echo "访问示例: https://$DOMAIN/?url=https://example.com"
