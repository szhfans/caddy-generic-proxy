#!/bin/bash
# 自动检测 Debian 版本并切换 archive 源，同时安装配置 Caddy

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

echo "[*] 升级系统（可选）"
# apt upgrade -y
# apt full-upgrade -y

# ------------------------
# 安装 Caddy
# ------------------------
if ! command -v caddy >/dev/null 2>&1; then
    echo "[*] Caddy 未安装，开始安装..."
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg2
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor | sudo tee /usr/share/keyrings/caddy-stable-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
else
    echo "[*] Caddy 已安装，跳过安装"
fi

# ------------------------
# 确保 Caddy systemd 单元存在
# ------------------------
if ! systemctl list-unit-files | grep -q '^caddy.service'; then
    echo "[*] 创建 Caddy systemd 单元..."
    mkdir -p /etc/caddy
    cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy web server
After=network.target

[Service]
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable caddy
fi

# ------------------------
# 写入 Caddyfile 示例
# ------------------------
if [ ! -f /etc/caddy/Caddyfile ]; then
    echo "[*] 创建 /etc/caddy/Caddyfile 示例"
    DOMAIN="example.com"  # 请替换为你自己的域名
    cat > /etc/caddy/Caddyfile <<EOF
{$DOMAIN} {
    respond "Hello from Caddy"
}
EOF
fi

# ------------------------
# 启动或重载 Caddy
# ------------------------
if systemctl list-units --all | grep -q caddy.service; then
    echo "[*] 重载 Caddy..."
    systemctl reload caddy || systemctl start caddy
else
    echo "[!] Caddy systemd 单元不存在，无法重载"
fi

echo "[✅] 安装完成！"
echo "访问示例: https://$DOMAIN/"
