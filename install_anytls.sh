#!/bin/bash
# AnyTLS 修正版安装脚本
# 修复参数使用问题

set -e

# 颜色输出
red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }
blue(){ echo -e "\033[36m\033[01m$1\033[0m"; }

# 检查 root 权限
[[ $EUID -ne 0 ]] && red "错误：请使用 root 用户运行此脚本" && exit 1

# 欢迎信息
clear
green "========================================"
green "       AnyTLS 修正版安装脚本"
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
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    package_manager="yum"
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

# 获取配置参数
echo ""
blue "请配置 AnyTLS 参数："
read -p "请输入监听端口 [默认: 443]: " port
port=${port:-443}

read -p "请输入连接密码 [默认: anytls123]: " password  
password=${password:-anytls123}

echo ""
green "配置信息确认："
echo "  端口: $port"
echo "  密码: $password"
read -p "确认无误请按回车继续，或 Ctrl+C 退出..."

# 清理旧安装
green "清理旧安装..."
systemctl stop anytls 2>/dev/null || true
systemctl disable anytls 2>/dev/null || true
rm -rf /etc/anytls
rm -f /etc/systemd/system/anytls.service
systemctl daemon-reload 2>/dev/null || true

# 安装依赖包
green "安装系统依赖..."
if [[ "$package_manager" == "apt" ]]; then
    apt update -y >/dev/null 2>&1
    apt install -y curl wget unzip openssl net-tools >/dev/null 2>&1
else
    yum update -y >/dev/null 2>&1  
    yum install -y curl wget unzip openssl net-tools >/dev/null 2>&1
fi
green "✅ 依赖安装完成"

# 创建安装目录
mkdir -p /etc/anytls
cd /etc/anytls

# 获取系统架构
arch=$(uname -m)
case $arch in
    x86_64)
        arch_name="amd64"
        ;;
    aarch64|arm64)
        arch_name="arm64"
        ;;
    armv7l)
        arch_name="armv7"
        ;;
    *)
        red "❌ 不支持的架构: $arch"
        exit 1
        ;;
esac

green "✅ 检测架构: $arch ($arch_name)"

# 下载 AnyTLS
green "下载 AnyTLS 程序..."
version="0.0.8"
download_urls=(
    "https://github.com/anytls/anytls-go/releases/download/v${version}/anytls_${version}_linux_${arch_name}.zip"
    "https://ghproxy.com/https://github.com/anytls/anytls-go/releases/download/v${version}/anytls_${version}_linux_${arch_name}.zip"
    "https://mirror.ghproxy.com/https://github.com/anytls/anytls-go/releases/download/v${version}/anytls_${version}_linux_${arch_name}.zip"
)

download_success=false
for url in "${download_urls[@]}"; do
    blue "尝试下载: $url"
    if curl -L --connect-timeout 30 --max-time 300 -o anytls.zip "$url" >/dev/null 2>&1; then
        if [[ -f anytls.zip ]] && [[ $(stat -c%s anytls.zip 2>/dev/null) -gt 1000 ]]; then
            green "✅ 下载成功"
            download_success=true
            break
        fi
    fi
    yellow "下载失败，尝试下一个源..."
done

if [[ "$download_success" != "true" ]]; then
    red "❌ 所有下载源都失败"
    exit 1
fi

# 解压文件
green "解压程序文件..."
if ! unzip -o anytls.zip >/dev/null 2>&1; then
    red "❌ 解压失败"
    exit 1
fi

# 查找并设置可执行文件
if [[ -f "anytls-server" ]]; then
    mv anytls-server anytls
    green "✅ 找到服务端程序"
elif [[ -f "anytls" ]]; then
    green "✅ 程序文件已存在"
else
    exec_file=$(find . -type f -executable | grep -v ".zip" | head -1)
    if [[ -n "$exec_file" ]]; then
        mv "$exec_file" anytls
        green "✅ 找到可执行文件: $exec_file"
    else
        red "❌ 未找到可执行文件"
        ls -la
        exit 1
    fi
fi

chmod +x anytls
rm -f *.zip *.md anytls-client 2>/dev/null || true

# 查看程序帮助信息
green "查看程序使用方法..."
./anytls --help || ./anytls -h || true

# 获取服务器IP
green "获取服务器IP..."
server_ip=""
ip_apis=(
    "https://ipv4.icanhazip.com"
    "https://api.ipify.org"  
    "https://ifconfig.me"
    "https://ipinfo.io/ip"
)

for api in "${ip_apis[@]}"; do
    server_ip=$(curl -s --connect-timeout 5 --max-time 10 "$api" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    if [[ -n "$server_ip" ]]; then
        break
    fi
done

if [[ -z "$server_ip" ]]; then
    yellow "⚠️ 无法自动获取IP，请手动输入"
    read -p "请输入服务器公网IP: " server_ip
fi

green "✅ 服务器IP: $server_ip"

# 生成SSL证书（如果程序需要的话）
green "生成SSL证书..."
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=CA/L=San Francisco/O=AnyTLS/CN=$server_ip" \
    -keyout server.key -out server.crt >/dev/null 2>&1

# 设置文件权限
chown -R root:root /etc/anytls
chmod 755 /etc/anytls
chmod 755 /etc/anytls/anytls
chmod 644 /etc/anytls/server.crt
chmod 600 /etc/anytls/server.key

# 构建启动参数
listen_addr="0.0.0.0:$port"

# 测试程序
green "测试程序启动..."
blue "启动参数: -l $listen_addr -p $password"

# 先进行手动测试
timeout 10 ./anytls -l "$listen_addr" -p "$password" &
test_pid=$!
sleep 3

if kill -0 $test_pid 2>/dev/null; then
    kill $test_pid 2>/dev/null || true
    green "✅ 程序测试通过"
    
    # 创建systemd服务
    green "创建系统服务..."
    cat > /etc/systemd/system/anytls.service <<EOF
[Unit]
Description=AnyTLS Server
Documentation=https://github.com/anytls/anytls-go
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/etc/anytls/anytls -l $listen_addr -p $password
WorkingDirectory=/etc/anytls
Restart=always
RestartSec=10
RestartPreventExitStatus=23
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    green "启动AnyTLS服务..."
    systemctl daemon-reload
    systemctl enable anytls >/dev/null 2>&1
    
    if systemctl start anytls; then
        sleep 5
        
        # 检查服务状态
        if systemctl is-active --quiet anytls; then
            green "✅ 服务启动成功"
            
            # 检查端口监听
            sleep 2
            if netstat -tlnp 2>/dev/null | grep ":$port " >/dev/null || ss -tlnp 2>/dev/null | grep ":$port " >/dev/null; then
                green "✅ 端口监听正常"
                
                # 检查进程
                if pgrep -f "/etc/anytls/anytls" >/dev/null; then
                    green "✅ 进程运行正常"
                    
                    # 生成节点链接
                    node_link="anytls://$password@$server_ip:$port?insecure=1"
                    
                    echo ""
                    green "🎉 AnyTLS 安装成功！"
                    echo ""
                    blue "=========================================="
                    green "  服务端口: $port"
                    green "  连接密码: $password" 
                    green "  服务器IP: $server_ip"
                    green "  监听地址: $listen_addr"
                    echo ""
                    yellow "📱 节点链接:"
                    echo "$node_link"
                    blue "=========================================="
                    echo ""
                    green "📋 管理命令:"
                    echo "  systemctl status anytls    # 查看状态"
                    echo "  systemctl stop anytls      # 停止服务"
                    echo "  systemctl start anytls     # 启动服务" 
                    echo "  systemctl restart anytls   # 重启服务"
                    echo "  journalctl -u anytls -f    # 查看日志"
                    echo ""
                    echo "  手动启动命令:"
                    echo "  cd /etc/anytls && ./anytls -l $listen_addr -p $password"
                    echo ""
                    yellow "🔥 复制节点链接到客户端即可使用！"
                    
                else
                    yellow "⚠️ systemd 服务运行但进程检测失败"
                    echo "尝试检查："
                    echo "  ps aux | grep anytls"
                    echo "  journalctl -u anytls -f"
                fi
            else
                red "❌ 端口未监听"
                echo "端口检查命令："
                echo "  netstat -tlnp | grep $port"
                echo "  ss -tlnp | grep $port"
                echo ""
                echo "尝试手动启动："
                echo "  cd /etc/anytls && ./anytls -l $listen_addr -p $password"
            fi
        else
            red "❌ 服务启动失败"
            echo "查看服务状态："
            systemctl status anytls --no-pager
            echo ""
            echo "查看服务日志："
            journalctl -u anytls --no-pager -l --since "5 minutes ago"
            echo ""
            echo "尝试手动启动："
            echo "  cd /etc/anytls && ./anytls -l $listen_addr -p $password"
        fi
    else
        red "❌ systemd 启动失败"
        echo "尝试手动启动："
        echo "  cd /etc/anytls && ./anytls -l $listen_addr -p $password"
    fi
    
else
    red "❌ 程序测试失败"
    echo ""
    echo "尝试手动运行查看错误："
    echo "  cd /etc/anytls"
    echo "  ./anytls -l $listen_addr -p $password"
fi

green ""
green "安装脚本执行完成！"
