#!/bin/bash
# AnyTLS 完整重装脚本

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

green "======================================="
green "       AnyTLS 完整重装"
green "======================================="

# 检查系统
check_system

# 清理旧安装
green "[0/7] 清理旧安装..."
systemctl stop anytls 2>/dev/null || true
systemctl disable anytls 2>/dev/null || true
rm -f /etc/systemd/system/anytls.service
rm -rf /etc/anytls
systemctl daemon-reload

# 输入配置
green "[1/7] 配置参数..."
read -p "请输入 AnyTLS 监听端口 [默认:10567]：" PORT
PORT=${PORT:-10567}

read -p "请输入连接密码 [默认:wb222106]：" PASSWORD
PASSWORD=${PASSWORD:-wb222106}

green "配置信息："
green " - 端口: $PORT"
green " - 密码: $PASSWORD"

# 安装依赖
green "[2/7] 安装依赖..."
if [[ "$SYSTEM" == "debian" ]]; then
    apt update -y
    apt install -y curl wget unzip openssl socat net-tools
elif [[ "$SYSTEM" == "centos" ]]; then
    yum update -y
    yum install -y curl wget unzip openssl socat net-tools
fi

# 创建目录
green "[3/7] 创建安装目录..."
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

green "系统架构: $ARCH"

# 下载程序
green "[4/7] 下载 AnyTLS..."
ANYTLS_VER="v0.0.8"
ANYTLS_VER_NUM="0.0.8"

# 多个下载源
DOWNLOAD_URLS=(
    "https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER_NUM}_linux_${ARCH}.zip"
    "https://ghproxy.com/https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER_NUM}_linux_${ARCH}.zip"
    "https://mirror.ghproxy.com/https://github.com/anytls/anytls-go/releases/download/${ANYTLS_VER}/anytls_${ANYTLS_VER_NUM}_linux_${ARCH}.zip"
)

DOWNLOAD_SUCCESS=false
for url in "${DOWNLOAD_URLS[@]}"; do
    green "尝试从: $url"
    
    if curl -L --connect-timeout 15 --max-time 120 -o anytls.zip "$url"; then
        if [[ -f anytls.zip ]] && [[ $(stat -c%s anytls.zip 2>/dev/null || wc -c < anytls.zip) -gt 1000 ]]; then
            green "✅ 下载成功！"
            DOWNLOAD_SUCCESS=true
            break
        else
            rm -f anytls.zip
        fi
    fi
done

if [[ "$DOWNLOAD_SUCCESS" != true ]]; then
    red "❌ 所有下载源都失败了"
    red "请手动下载以下任一文件并重命名为 anytls.zip："
    for url in "${DOWNLOAD_URLS[@]}"; do
        echo "   $url"
    done
    exit 1
fi

# 解压文件
green "解压文件..."
if ! unzip -o anytls.zip; then
    red "❌ 解压失败"
    exit 1
fi

# 查找可执行文件
if [[ ! -f "anytls" ]]; then
    yellow "寻找可执行文件..."
    ls -la
    
    EXEC_FILE=$(find . -type f -name "*anytls*" | head -1)
    if [[ -n "$EXEC_FILE" ]]; then
        mv "$EXEC_FILE" anytls
    else
        red "❌ 未找到可执行文件"
        exit 1
    fi
fi

chmod +x anytls
rm -f anytls.zip

# 测试程序
green "测试可执行文件..."
echo "文件信息: $(file anytls)"
if ./anytls --help >/dev/null 2>&1 || ./anytls -h >/dev/null 2>&1; then
    green "✅ 程序可正常运行"
else
    yellow "⚠️ 程序帮助信息获取失败，但继续安装..."
fi

# 获取公网 IP
green "[5/7] 获取服务器信息..."
SERVER_IP=$(curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 ipinfo.io/ip || echo "未知")
if [[ "$SERVER_IP" == "未知" ]]; then
    read -p "请手动输入服务器公网 IP: " SERVER_IP
fi
green "服务器 IP: $SERVER_IP"

# 生成证书
green "[6/7] 生成 SSL 证书..."
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -subj "/C=US/ST=CA/L=SanFrancisco/O=AnyTLS/OU=Server/CN=${SERVER_IP}" \
  -keyout anytls.key -out anytls.crt

# 创建配置文件
green "创建配置文件..."
cat > config.json <<EOF
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

# 设置权限
chown root:root /etc/anytls/*
chmod 600 /etc/anytls/anytls.key
chmod 644 /etc/anytls/anytls.crt
chmod 755 /etc/anytls/anytls
chmod 644 /etc/anytls/config.json

# 创建服务
green "[7/7] 创建系统服务..."
cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/anytls
ExecStart=/etc/anytls/anytls -config /etc/anytls/config.json
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=anytls
KillMode=mixed
TimeoutStopSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 重载并启动服务
systemctl daemon-reload
systemctl enable anytls
systemctl start anytls

# 等待服务启动
sleep 5

# 检查服务状态
green "检查服务状态..."
if systemctl is-active --quiet anytls; then
    green "✅ 服务启动成功"
    
    # 检查进程
    if pgrep -f anytls >/dev/null; then
        green "✅ 进程运行正常"
        
        # 检查端口
        if netstat -tlnp 2>/dev/null | grep ":$PORT " || ss -tlnp 2>/dev/null | grep ":$PORT "; then
            green "✅ 端口监听正常"
            
            # 测试连接
            if timeout 5 bash -c "</dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
                green "✅ 本地连接测试成功"
            else
                yellow "⚠️ 本地连接测试失败，但服务可能正常"
            fi
            
            # 生成节点信息
            NODE_URL="anytls://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1"
            
            green ""
            green "======================================="
            green "✅ AnyTLS 安装完成！"
            green "======================================="
            green " 服务端口: $PORT"
            green " 连接密码: $PASSWORD"
            green " 服务器IP: $SERVER_IP"
            green " 节点链接: $NODE_URL"
            green "======================================="
            green ""
            green "管理命令："
            green " systemctl start anytls    # 启动服务"
            green " systemctl stop anytls     # 停止服务"
            green " systemctl restart anytls  # 重启服务"
            green " systemctl status anytls   # 查看状态"
            green " journalctl -u anytls -f   # 查看日志"
            green ""
            yellow "节点链接已生成，请复制到客户端使用！"
            
        else
            red "❌ 端口 $PORT 未监听"
            yellow "检查服务日志："
            journalctl -u anytls --no-pager -l --since "5 minutes ago"
        fi
    else
        red "❌ 进程未运行"
        yellow "检查服务状态："
        systemctl status anytls --no-pager -l
    fi
else
    red "❌ 服务启动失败"
    yellow "检查服务状态："
    systemctl status anytls --no-pager -l
    yellow "检查日志："
    journalctl -u anytls --no-pager -l --since "5 minutes ago"
fi

green ""
green "安装完成！"
