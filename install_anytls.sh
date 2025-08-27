#!/bin/bash
# AnyTLS 一键安装脚本（自签证书版）
# 自动识别架构 + 最新版本 + 节点链接

set -e

# 颜色输出
green(){ echo -e "\033[32m$1\033[0m"; }
red(){ echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }

# 检查系统
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        SYSTEM="centos"
        PACKAGE_MANAGER="yum"
    elif [[ -f /etc/debian_version ]]; then
        SYSTEM="debian"
        PACKAGE_MANAGER="apt"
    else
        red "❌ 不支持的系统，仅支持 CentOS/RHEL 和 Debian/Ubuntu"
        exit 1
    fi
}

# 检查 root
[[ $EUID -ne 0 ]] && red "请使用 root 运行此脚本" && exit 1

# 检查系统
check_system

# 输入端口（增加端口验证）
while true; do
    read -p "请输入 AnyTLS 监听端口 [默认:443]：" PORT
    PORT=${PORT:-443}
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        # 检查端口是否被占用
        if netstat -tuln | grep -q ":$PORT "; then
            yellow "⚠️ 端口 $PORT 已被占用，请选择其他端口"
            continue
        fi
        break
    else
        red "❌ 请输入有效的端口号 (1-65535)"
    fi
done

# 输入密码（支持环境变量 ANYTLS_PASS）
read -p "请输入连接密码 [默认:changeme123]：" PASSWORD_INPUT
PASSWORD=${PASSWORD_INPUT:-${ANYTLS_PASS:-changeme123}}

# 密码长度检查
if [ ${#PASSWORD} -lt 6 ]; then
    yellow "⚠️ 建议使用至少6位密码以提高安全性"
fi

# 安装依赖
green "[1/5] 安装依赖..."
if [[ "$SYSTEM" == "debian" ]]; then
    apt update -y
    apt install -y curl wget unzip openssl socat net-tools
elif [[ "$SYSTEM" == "centos" ]]; then
    yum update -y
    yum install -y curl wget unzip openssl socat net-tools
fi

# 创建目录
mkdir -p /etc/anytls
cd /etc/anytls

# 获取架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    i386|i686) ARCH="386" ;;
    *) red "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 获取最新版本（增加错误处理和重试机制）
green "[2/5] 获取 AnyTLS 最新版本..."
ANYTLS_VER=""
for i in {1..3}; do
    ANYTLS_VER=$(curl -s --connect-timeout 10 --max-time 30 https://api.github.com/repos/anytls/anytls-go/releases/latest | grep -o '"tag_name": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' 2>/dev/null || echo "")
    if [[ -n "$ANYTLS_VER" ]]; then
        break
    fi
    yellow "⚠️ 第 $i 次尝试获取版本失败，重试中..."
    sleep 2
done

# fallback 默认版本
if [[ -z "$ANYTLS_VER" ]]; then
    yellow "⚠️ GitHub API 获取失败，使用默认版本 v0.0.8"
    ANYTLS_VER="v0.0.8"
fi

green "获取到版本: $ANYTLS_VER"

# 构造下载 URL（保持完整版本号格式）
DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER}_linux_${ARCH}.zip"

# 检查版本是否可用并下载（增加重试机制）
green "[3/5] 下载 AnyTLS ${ANYTLS_VER} (${ARCH})..."
DOWNLOAD_SUCCESS=false
for i in {1..3}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$DOWNLOAD_URL")
    if [[ "$STATUS" -eq 200 ]]; then
        if wget -O anytls.zip --timeout=30 --tries=2 "$DOWNLOAD_URL"; then
            DOWNLOAD_SUCCESS=true
            break
        fi
    fi
    yellow "⚠️ 第 $i 次下载失败 (HTTP: $STATUS)，重试中..."
    sleep 2
done

if [[ "$DOWNLOAD_SUCCESS" != true ]]; then
    red "❌ 下载失败，请检查网络连接或手动下载"
    red "URL: $DOWNLOAD_URL"
    exit 1
fi

# 解压并设置权限
if ! unzip -o anytls.zip; then
    red "❌ 解压失败，可能下载文件损坏"
    exit 1
fi

if [[ ! -f "anytls" ]]; then
    red "❌ 解压后未找到 anytls 可执行文件"
    exit 1
fi

chmod +x anytls

# 获取公网 IP（增加更多 IP 获取源）
green "获取服务器公网 IP..."
SERVER_IP=""
IP_SOURCES=(
    "ipv4.icanhazip.com"
    "ifconfig.me"
    "ipinfo.io/ip"
    "api.ipify.org"
    "checkip.amazonaws.com"
)

for source in "${IP_SOURCES[@]}"; do
    SERVER_IP=$(curl -s --connect-timeout 5 --max-time 10 "$source" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    if [[ -n "$SERVER_IP" ]]; then
        green "检测到公网 IP: $SERVER_IP"
        break
    fi
done

if [[ -z "$SERVER_IP" ]]; then
    yellow "⚠️ 无法自动获取公网 IP，请手动输入"
    read -p "请输入服务器公网 IP: " SERVER_IP
    if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        red "❌ IP 格式不正确"
        exit 1
    fi
fi

# 生成自签证书（CN 动态使用服务器 IP）
green "[4/5] 生成自签证书..."
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=AnyTLS/OU=Server/CN=${SERVER_IP}" \
  -keyout /etc/anytls/anytls.key -out /etc/anytls/anytls.crt

# 检查证书是否生成成功
if [[ ! -f "/etc/anytls/anytls.key" ]] || [[ ! -f "/etc/anytls/anytls.crt" ]]; then
    red "❌ 证书生成失败"
    exit 1
fi

# 写配置文件
cat > /etc/anytls/config.json <<EOF
{
  "listen": ":${PORT}",
  "cert": "/etc/anytls/anytls.crt",
  "key": "/etc/anytls/anytls.key",
  "auth": {
    "mode": "password",
    "password": "${PASSWORD}"
  }
}
EOF

# systemd 服务
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/anytls
ExecStart=/etc/anytls/anytls -config /etc/anytls/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
green "[5/5] 启动 AnyTLS..."
systemctl daemon-reload
systemctl enable anytls

# 检查服务是否启动成功
if systemctl start anytls; then
    sleep 3
    if systemctl is-active --quiet anytls; then
        green "✅ AnyTLS 服务启动成功"
    else
        red "❌ AnyTLS 服务启动失败"
        red "错误日志："
        systemctl status anytls --no-pager
        exit 1
    fi
else
    red "❌ AnyTLS 服务启动失败"
    exit 1
fi

# 节点链接
NODE_URL="anytls://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1"

green "✅ AnyTLS 已安装并运行成功！"
green "=============================="
green " 服务端口: ${PORT}"
green " 用户密码: ${PASSWORD}"
green " 服务器IP: ${SERVER_IP}"
green " 证书路径: /etc/anytls/anytls.crt"
green " 节点链接: ${NODE_URL}"
green "=============================="
green ""
green "管理命令："
green " 启动服务: systemctl start anytls"
green " 停止服务: systemctl stop anytls"
green " 重启服务: systemctl restart anytls"
green " 查看状态: systemctl status anytls"
green " 查看日志: journalctl -u anytls -f"
