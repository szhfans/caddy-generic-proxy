#!/bin/bash
# AnyTLS 问题修复脚本

# 颜色输出
green(){ echo -e "\033[32m$1\033[0m"; }
red(){ echo -e "\033[31m$1\033[0m"; }
yellow(){ echo -e "\033[33m$1\033[0m"; }

green "开始修复 AnyTLS..."

# 1. 停止服务
green "[1/6] 停止现有服务"
systemctl stop anytls
systemctl disable anytls

# 2. 检查可执行文件
green "[2/6] 检查可执行文件"
cd /etc/anytls
if [[ ! -f "anytls" ]]; then
    red "❌ 可执行文件不存在"
    exit 1
fi

# 测试可执行文件是否正常
green "测试可执行文件..."
if ! ./anytls --help >/dev/null 2>&1 && ! ./anytls -h >/dev/null 2>&1; then
    yellow "⚠️ 程序可能不兼容，尝试直接运行..."
    timeout 5s ./anytls -config /etc/anytls/config.json &
    sleep 2
    if ! pgrep -f anytls >/dev/null; then
        red "❌ 程序无法正常运行，可能是架构不匹配"
        echo "当前系统架构："
        uname -a
        echo "文件类型："
        file ./anytls
        
        # 尝试重新下载正确的版本
        green "尝试重新下载正确的架构..."
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64) ARCH="amd64" ;;
            aarch64|arm64) ARCH="arm64" ;;
            armv7l) ARCH="armv7" ;;
            i386|i686) ARCH="386" ;;
        esac
        
        # 备份旧文件
        mv anytls anytls.backup
        
        # 下载新文件
        DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/v0.0.8/anytls_0.0.8_linux_${ARCH}.zip"
        green "下载地址: $DOWNLOAD_URL"
        
        if curl -L -o anytls_new.zip "$DOWNLOAD_URL"; then
            unzip -o anytls_new.zip
            chmod +x anytls
            rm anytls_new.zip
        else
            red "❌ 重新下载失败"
            mv anytls.backup anytls
        fi
    else
        # 停止测试进程
        pkill -f anytls
    fi
fi

# 3. 检查配置文件
green "[3/6] 验证配置文件"
if [[ ! -f config.json ]]; then
    red "❌ 配置文件不存在"
    exit 1
fi

# 显示当前配置
echo "当前配置："
cat config.json

# 验证 JSON 格式
if ! python3 -m json.tool config.json >/dev/null 2>&1 && ! python -m json.tool config.json >/dev/null 2>&1; then
    yellow "⚠️ 无法验证 JSON 格式，但继续尝试..."
fi

# 4. 检查证书文件权限
green "[4/6] 检查文件权限"
chown root:root /etc/anytls/*
chmod 600 /etc/anytls/anytls.key
chmod 644 /etc/anytls/anytls.crt
chmod 755 /etc/anytls/anytls
chmod 644 /etc/anytls/config.json

# 5. 重新创建 systemd 服务文件
green "[5/6] 重新创建服务文件"
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

# 6. 启动服务并测试
green "[6/6] 启动服务"
systemctl daemon-reload
systemctl enable anytls

# 先手动测试一下程序
green "手动测试程序..."
timeout 10s ./anytls -config config.json &
TEST_PID=$!
sleep 3

if kill -0 $TEST_PID 2>/dev/null; then
    green "✅ 程序可以正常运行"
    kill $TEST_PID
    
    # 启动服务
    green "启动 systemd 服务..."
    systemctl start anytls
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet anytls; then
        green "✅ 服务启动成功"
        
        # 检查端口
        PORT=$(grep -o '"listen": *":[0-9]*"' config.json | grep -o '[0-9]*')
        if netstat -tlnp 2>/dev/null | grep ":$PORT " || ss -tlnp 2>/dev/null | grep ":$PORT "; then
            green "✅ 端口 $PORT 正在监听"
            
            # 测试连接
            green "测试本地连接..."
            if timeout 5 bash -c "</dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
                green "✅ 端口连接测试成功"
            else
                yellow "⚠️ 端口连接测试失败，但服务可能仍可用"
            fi
            
            # 生成节点信息
            PASSWORD=$(grep -o '"password": *"[^"]*"' config.json | cut -d'"' -f4)
            SERVER_IP="80.75.218.223"
            NODE_URL="anytls://${PASSWORD}@${SERVER_IP}:${PORT}?insecure=1"
            
            green "=================================="
            green "✅ AnyTLS 修复完成！"
            green "=================================="
            green " 服务端口: $PORT"
            green " 密码: $PASSWORD"
            green " 服务器IP: $SERVER_IP"
            green " 节点链接: $NODE_URL"
            green "=================================="
            
        else
            red "❌ 端口未监听，检查服务日志"
        fi
    else
        red "❌ 服务启动失败"
        systemctl status anytls --no-pager -l
    fi
else
    red "❌ 程序无法正常运行"
    
    # 显示详细错误信息
    green "尝试查看错误信息..."
    ./anytls -config config.json 2>&1 || true
fi

# 显示调试信息
green "\n调试信息："
echo "系统架构: $(uname -m)"
echo "文件信息: $(file anytls)"
echo "当前进程: $(pgrep -f anytls || echo '无')"
echo "服务状态: $(systemctl is-active anytls)"
echo "服务日志: "
journalctl -u anytls --no-pager -l --since "5 minutes ago" | tail -10
