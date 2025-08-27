#!/bin/bash
# AnyTLS 一键安装脚本（终极修复版）
# 多源下载 + 镜像加速 + 手动上传支持

set -e

# 颜色输出
green(){ echo -e "\033[32m$1\033[0m"; }
red(){ echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }
blue(){ echo -e "\033[34m$1\033[0m"; }

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
    read -p "请输入 AnyTLS 监听端口 [默认:10567]：" PORT
    PORT=${PORT:-10567}
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        # 检查端口是否被占用
        if netstat -tuln 2>/dev/null | grep -q ":$PORT " || ss -tuln 2>/dev/null | grep -q ":$PORT "; then
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

# 获取最新版本
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

# 去掉版本号前缀 v
ANYTLS_VER_NUM=${ANYTLS_VER#v}

# 多个下载源
DOWNLOAD_URLS=(
    "https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER_NUM}_linux_${ARCH}.zip"
    "https://ghproxy.com/https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER_NUM}_linux_${ARCH}.zip"
    "https://mirror.ghproxy.com/https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER_NUM}_linux_${ARCH}.zip"
)

green "[3/5] 下载 AnyTLS ${ANYTLS_VER} (${ARCH})..."

# 首先检查是否已存在文件
if [[ -f "anytls.zip" ]]; then
    yellow "发现已存在的 anytls.zip 文件"
    read -p "是否使用现有文件？(y/N): " USE_EXISTING
    if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
        green "使用现有文件..."
        DOWNLOAD_SUCCESS=true
    else
        rm -f anytls.zip
        DOWNLOAD_SUCCESS=false
    fi
else
    DOWNLOAD_SUCCESS=false
fi

# 如果没有现有文件或选择重新下载，则尝试下载
if [[ "$DOWNLOAD_SUCCESS" != true ]]; then
    for url in "${DOWNLOAD_URLS[@]}"; do
        green "尝试从: $url"
        
        # 尝试多种下载方法
        METHODS=(
            "curl -L --connect-timeout 15 --max-time 120 -H 'User-Agent: Mozilla/5.0' -o anytls.zip"
            "wget --timeout=120 --tries=2 --user-agent='Mozilla/5.0' -O anytls.zip"
            "curl -L --connect-timeout 15 --max-time 120 -o anytls.zip"
        )
        
        for method in "${METHODS[@]}"; do
            yellow "使用方法: $method"
            if $method "$url"; then
                # 检查文件是否有效
                if [[ -f anytls.zip ]] && [[ $(stat -c%s anytls.zip 2>/dev/null || wc -c < anytls.zip) -gt 1000 ]]; then
                    green "✅ 下载成功！"
                    DOWNLOAD_SUCCESS=true
                    break 2
                else
                    yellow "⚠️ 下载的文件无效，尝试其他方法..."
                    rm -f anytls.zip
                fi
            fi
        done
        
        if [[ "$DOWNLOAD_SUCCESS" = true ]]; then
            break
        fi
    done
fi

# 如果所有下载方法都失败，提供手动上传选项
if [[ "$DOWNLOAD_SUCCESS" != true ]]; then
    red "❌ 所有下载方法都失败了"
    yellow "请选择以下选项："
    yellow "1. 手动下载文件并上传到服务器"
    yellow "2. 退出脚本"
    
    echo ""
    yellow "手动下载地址（任选一个）："
    for url in "${DOWNLOAD_URLS[@]}"; do
        echo "   $url"
    done
    echo ""
    yellow "下载后请将文件重命名为 anytls.zip 并上传到当前目录: $(pwd)"
    
    read -p "选择 [1-手动上传/2-退出]: " CHOICE
    case $CHOICE in
        1)
            echo ""
            yellow "请在另一个终端窗口中上传文件，然后按回车继续..."
            read -p "按回车键继续..." 
            if [[ -f "anytls.zip" ]] && [[ $(stat -c%s anytls.zip 2>/dev/null || wc -c < anytls.zip) -gt 1000 ]]; then
                green "✅ 检测到有效的 anytls.zip 文件"
                DOWNLOAD_SUCCESS=true
            else
                red "❌ 未检测到有效的 anytls.zip 文件"
                exit 1
            fi
            ;;
        *)
            red "❌ 用户取消安装"
            exit 1
            ;;
    esac
fi

# 解压并设置权限
green "解压文件..."
if ! unzip -o anytls.zip; then
    red "❌ 解压失败，可能下载文件损坏"
    exit 1
fi

# 检查解压后的文件
if [[ ! -f "anytls" ]]; then
    # 列出所有文件，看看实际的文件名
    yellow "解压后的文件列表："
    ls -la
    
    # 尝试找到可执行文件
    EXEC_FILE=$(find . -type f -executable -name "*anytls*" | head -1)
    if [[ -n "$EXEC_FILE" ]]; then
        yellow "找到可执行文件: $EXEC_FILE"
        mv "$EXEC_FILE" anytls
    else
        red "❌ 未找到 anytls 可执行文件"
        exit 1
    fi
fi

chmod +x anytls

# 验证可执行文件
if ! ./anytls -version 2>/dev/null && ! ./anytls --version 2>/dev/null && ! ./anytls -h 2>/dev/null; then
    yellow "⚠️ 无法验证 anytls 版本，但继续安装..."
fi

# 获取公网 IP
green "获取服务器公网 IP..."
SERVER_IP=""
IP_SOURCES=(
    "ipv4.icanhazip.com"
    "ifconfig.me"
    "ipinfo.io/ip"
    "api.ipify.org"
    "checkip.amazonaws.com"
    "ident.me"
    "whatismyipaddress.com/api/v1/ip"
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

# 生成自签证书
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
        systemctl status anytls --no-pager -l
        journalctl -u anytls --no-pager -l --since "5 minutes ago"
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
green " 配置文件: /etc/anytls/config.json"
green " 节点链接: ${NODE_URL}"
green "=============================="
green ""
green "管理命令："
green " 启动服务: systemctl start anytls"
green " 停止服务: systemctl stop anytls"
green " 重启服务: systemctl restart anytls"
green " 查看状态: systemctl status anytls"
green " 查看日志: journalctl -u anytls -f"
green ""
green "故障排除："
green " 检查端口: netstat -tlnp | grep ${PORT}"
green " 测试连接: curl -k https://${SERVER_IP}:${PORT}"
