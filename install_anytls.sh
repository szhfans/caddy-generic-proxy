#!/bin/bash
# AnyTLS + Argo Tunnel 一键安装脚本
# 默认端口 1080，增加端口检测 & 可选 Argo 加速

set -e

# 颜色输出
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }
blue(){ echo -e "\033[36m\033[01m$1\033[0m"; }

[[ $EUID -ne 0 ]] && red "错误：请使用 root 用户运行此脚本" && exit 1

clear
green "========================================"
green "     AnyTLS + Argo Tunnel 安装脚本"
green "========================================"
echo ""

# 检测系统
if [[ -f /etc/redhat-release ]]; then
    release="centos"
    package_manager="yum"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
    package_manager="apt"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
    package_manager="apt"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
    package_manager="apt"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
    package_manager="apt"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    package_manager="yum"
else
    red "❌ 不支持的操作系统！"
    exit 1
fi
green "✅ 检测到系统: $release"

# 获取参数
echo ""
blue "请配置 AnyTLS 参数："
read -p "请输入监听端口 [默认: 1080]: " port
port=${port:-1080}
while ss -tulnp 2>/dev/null | grep -q ":$port "; do
    red "❌ 端口 $port 已被占用"
    read -p "请输入新的监听端口: " port
    port=${port:-1080}
done
green "✅ 使用端口: $port"

read -p "请输入连接密码 [默认: anytls123]: " password
password=${password:-anytls123}

# 安装依赖
green "安装依赖..."
if [[ "$package_manager" == "apt" ]]; then
    apt update -y >/dev/null 2>&1
    apt install -y curl wget unzip openssl net-tools >/dev/null 2>&1
else
    yum install -y curl wget unzip openssl net-tools >/dev/null 2>&1
fi
green "✅ 依赖安装完成"

# 清理旧安装
systemctl stop anytls 2>/dev/null || true
systemctl disable anytls 2>/dev/null || true
rm -rf /etc/anytls
rm -f /etc/systemd/system/anytls.service
systemctl daemon-reload 2>/dev/null || true

# 创建目录
mkdir -p /etc/anytls
cd /etc/anytls

# 架构判断
arch=$(uname -m)
case $arch in
    x86_64) arch_name="amd64" ;;
    aarch64|arm64) arch_name="arm64" ;;
    armv7l) arch_name="armv7" ;;
    *) red "❌ 不支持架构: $arch" && exit 1 ;;
esac
green "✅ 架构: $arch ($arch_name)"

# 下载 AnyTLS
version="0.0.8"
url="https://github.com/anytls/anytls-go/releases/download/v${version}/anytls_${version}_linux_${arch_name}.zip"
green "下载 AnyTLS..."
curl -L -o anytls.zip "$url"
unzip -o anytls.zip >/dev/null 2>&1
mv anytls-server anytls 2>/dev/null || true
chmod +x anytls
rm -f anytls.zip anytls-client README*

# 获取公网 IP
server_ip=$(curl -s https://ipv4.icanhazip.com || echo "")
if [[ -z "$server_ip" ]]; then
    read -p "请输入服务器公网IP: " server_ip
fi
green "✅ 服务器IP: $server_ip"

# SSL 证书
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -subj "/C=US/ST=CA/L=San Francisco/O=AnyTLS/CN=$server_ip" \
  -keyout server.key -out server.crt >/dev/null 2>&1

# systemd 服务
listen_addr="0.0.0.0:$port"
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
After=network.target

[Service]
ExecStart=/etc/anytls/anytls -l $listen_addr -p $password
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable anytls
systemctl start anytls

if systemctl is-active --quiet anytls; then
    green "🎉 AnyTLS 安装成功"
else
    red "❌ AnyTLS 启动失败"
    exit 1
fi

# Argo 配置
echo ""
yellow "是否启用 Cloudflare Argo Tunnel 加速？"
read -p "输入 y 启用，直接回车跳过: " enable_argo
if [[ "$enable_argo" == "y" || "$enable_argo" == "Y" ]]; then
    green "安装 cloudflared..."
    if ! command -v cloudflared >/dev/null 2>&1; then
        if [[ "$package_manager" == "apt" ]]; then
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
            dpkg -i cloudflared.deb || apt -f install -y
            rm -f cloudflared.deb
        else
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.rpm -o cloudflared.rpm
            rpm -i cloudflared.rpm || yum install -f -y
            rm -f cloudflared.rpm
        fi
    fi

    blue "请输入你在 Cloudflare 上绑定的域名:"
    read -p "域名: " argo_domain
    read -p "请输入 Argo Tunnel Token: " argo_token

    if [[ -n "$argo_domain" && -n "$argo_token" ]]; then
        cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Cloudflare Argo Tunnel
After=network.target

[Service]
ExecStart=/usr/bin/cloudflared tunnel run --token $argo_token
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable argo
        systemctl start argo
        sleep 5
        if systemctl is-active --quiet argo; then
            green "🎉 Argo Tunnel 已启动成功"
            echo ""
            yellow "🌍 节点链接 (Argo 加速):"
            echo "anytls://$password@$argo_domain:443?insecure=1"
        else
            red "❌ Argo 启动失败，请检查日志：journalctl -u argo -f"
        fi
    else
        red "❌ 未输入 Argo 域名或 Token，跳过配置"
    fi
else
    yellow "跳过 Argo 配置，使用原始 IP 连接"
    echo "anytls://$password@$server_ip:$port?insecure=1"
fi

green "安装完成！"
