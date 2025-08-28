#!/bin/bash
# AnyTLS 最终修复脚本

# 颜色输出
green(){ echo -e "\033[32m$1\033[0m"; }
red(){ echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }

cd /etc/anytls

green "现在修复 AnyTLS 配置问题..."

# 1. 停止现有服务
systemctl stop anytls 2>/dev/null || true

# 2. 检查文件并重命名
green "检查和修复可执行文件..."
ls -la

if [[ -f "anytls-server" ]]; then
    green "✅ 找到服务端程序 anytls-server"
    # 重命名服务端程序为 anytls
    mv anytls-server anytls
elif [[ -f "anytls" ]]; then
    green "✅ anytls 文件已存在"
else
    red "❌ 未找到可执行的服务端程序"
    exit 1
fi

chmod +x anytls

# 3. 检查系统架构匹配
green "检查系统架构..."
echo "当前系统: $(uname -a)"
echo "程序架构: $(ls -la anytls)"

# 手动测试程序是否可运行
green "测试程序兼容性..."
timeout 5s ./anytls --help 2>/dev/null || {
    yellow "⚠️ 程序帮助命令失败，检查是否架构不匹配"
    
    # 如果是架构问题，尝试下载正确版本
    CURRENT_ARCH=$(uname -m)
    echo "当前架构: $CURRENT_ARCH"
    
    if [[ "$CURRENT_ARCH" != "x86_64" ]]; then
        yellow "检测到非 x86_64 架构，尝试下载对应版本..."
        
        case "$CURRENT_ARCH" in
            aarch64|arm64) NEW_ARCH="arm64" ;;
            armv7l) NEW_ARCH="armv7" ;;
            i386|i686) NEW_ARCH="386" ;;
            *) 
                red "❌ 不支持的架构: $CURRENT_ARCH"
                exit 1
                ;;
        esac
        
        # 备份当前文件
        mv anytls anytls.backup
        rm -f anytls.zip
        
        # 下载正确架构的版本
        DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/v0.0.8/anytls_0.0.8_linux_${NEW_ARCH}.zip"
        green "下载 $NEW_ARCH 架构版本: $DOWNLOAD_URL"
        
        if curl -L -o anytls_new.zip "$DOWNLOAD_URL"; then
            if unzip -o anytls_new.zip; then
                if [[ -f "anytls-server" ]]; then
                    mv anytls-server anytls
                    chmod +x anytls
                    rm -f anytls_new.zip anytls.backup
                    green "✅ 重新下载成功"
                else
                    red "❌ 新下载的文件中没有找到 anytls-server"
                    mv anytls.backup anytls
                fi
            else
                red "❌ 解压新下载文件失败"
                mv anytls.backup anytls
            fi
        else
            red "❌ 重新下载失败"
            mv anytls.backup anytls
        fi
    fi
}

# 4. 最终测试程序
green "最终兼容性测试..."
if timeout 10s ./anytls -config config.json &
TEST_PID=$!; then
    sleep 3
    if kill -0 $TEST_PID 2>/dev/null; then
        green "✅ 程序可以正常运行"
        kill $TEST_PID 2>/dev/null || true
        PROGRAM_WORKS=true
    else
        red "❌ 程序启动后立即退出"
        PROGRAM_WORKS=false
    fi
else
    red "❌ 程序无法启动"
    PROGRAM_WORKS=false
fi

# 5. 如果程序工作正常，修复服务配置
if [[ "$PROGRAM_WORKS" == "true" ]]; then
    green "更新 systemd 服务配置..."
    
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
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=anytls
KillMode=mixed
TimeoutStopSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # 重载服务配置
    systemctl daemon-reload
    
    # 启动服务
    green "启动服务..."
    if systemctl start anytls; then
        sleep 5
        
        # 检查服务状态
        if systemctl is-active --quiet anytls && pgrep -f anytls >/dev/null; then
            PORT=$(grep -o '"listen": *":[0-9]*"' config.json | grep -o '[0-9]*')
            
            # 检查端口监听
            if netstat -tlnp 2>/dev/null | grep ":$PORT " || ss -tlnp 2>/dev/null | grep ":$PORT "; then
                PASSWORD=$(grep -o '"password": *"[^"]*"' config.json | cut -d'"' -f4)
                SERVER_IP="80.75.218.223"
                NODE_URL="anytls://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1"
                
                green ""
                green "🎉🎉🎉 AnyTLS 修复成功！🎉🎉🎉"
                green "======================================="
                green "✅ 服务状态: 正常运行"
                green "✅ 监听端口: $PORT"
                green "✅ 连接密码: $PASSWORD"
                green "✅ 服务器IP: $SERVER_IP"
                green ""
                green "📱 节点链接:"
                green "$NODE_URL"
                green "======================================="
                green ""
                green "📋 管理命令:"
                green " systemctl status anytls   # 查看状态"
                green " systemctl restart anytls  # 重启服务"
                green " journalctl -u anytls -f   # 查看日志"
                green ""
                yellow "🔥 节点链接已生成，复制到客户端即可使用！"
                
            else
                red "❌ 服务启动了但端口未监听"
                yellow "检查日志:"
                journalctl -u anytls --no-pager -l --since "5 minutes ago"
            fi
        else
            red "❌ 服务无法保持运行"
            systemctl status anytls --no-pager -l
        fi
    else
        red "❌ 服务启动失败"
        systemctl status anytls --no-pager -l
    fi
else
    red "❌ 程序架构不兼容或存在其他问题"
    echo ""
    yellow "可能的解决方案:"
    yellow "1. 检查是否为正确的系统架构"
    yellow "2. 尝试在不同的系统上运行"
    yellow "3. 联系软件作者获取适合的版本"
    echo ""
    echo "当前系统信息:"
    uname -a
fi
