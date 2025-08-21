#!/bin/bash
# 一键部署 Cloudflare IP 反代 + 健康检测 + 零中断切换
# 使用方法: sudo bash cf_proxy_full.sh

# ---------- 用户配置 ----------
read -p "请输入 Cloudflare 域名列表（用空格分开）: " -a CF_DOMAINS
read -p "请输入 VPS 监听 TCP/HTTPS 端口（默认8443）: " PORT_TCP
PORT_TCP=${PORT_TCP:-8443}
read -p "请输入 VPS 监听 HTTP 端口（默认8080）: " PORT_HTTP
PORT_HTTP=${PORT_HTTP:-8080}
# --------------------------------

NGINX_CONF="/etc/nginx/nginx.conf"
BACKUP_CONF="/etc/nginx/nginx.conf.bak"
LOG_FILE="/var/log/cf_proxy.log"
AUTO_SCRIPT="/usr/local/bin/update_cf_ips.sh"

# 安装必要软件
echo "[*] 更新系统并安装 Nginx + dig..."
sudo apt update -y
sudo apt install nginx dnsutils -y

# 备份 Nginx 配置
if [ ! -f "$BACKUP_CONF" ]; then
    sudo cp $NGINX_CONF $BACKUP_CONF
fi

# 获取 CF IP 列表
get_cf_ips() {
    IPS=()
    for DOMAIN in "${CF_DOMAINS[@]}"; do
        IP=$(dig +short $DOMAIN | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -n1)
        if [ ! -z "$IP" ]; then
            IPS+=("$IP $DOMAIN")
        fi
    done
    echo "${IPS[@]}"
}

CF_IPS=($(get_cf_ips))
if [ ${#CF_IPS[@]} -eq 0 ]; then
    echo "[❌] 无法获取任何 CF IP，请检查域名或网络！"
    exit 1
fi

echo "[*] 当前可用 CF 节点:"
for ipdomain in "${CF_IPS[@]}"; do
    echo "  $ipdomain"
done

# 写入初始 Nginx 配置
write_nginx() {
sudo tee $NGINX_CONF > /dev/null <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

stream {
    upstream cf_up {
EOF

    for ipdomain in "${CF_IPS[@]}"; do
        IP=$(echo $ipdomain | awk '{print $1}')
        echo "        server $IP:443;" | sudo tee -a $NGINX_CONF > /dev/null
    done

sudo tee -a $NGINX_CONF > /dev/null <<EOF
    }

    server {
        listen $PORT_TCP;
        proxy_pass cf_up;

        proxy_ssl on;
        proxy_ssl_server_name on;
        proxy_ssl_name ${CF_DOMAINS[0]};
    }
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen $PORT_HTTP;

        location / {
            proxy_pass https://${CF_IPS[0]% *}; # 初始第一个可用 IP
            proxy_set_header Host ${CF_DOMAINS[0]};
            proxy_ssl_server_name on;
            proxy_ssl_name ${CF_DOMAINS[0]};
        }
    }
}
EOF
}

write_nginx

# 检查并启动 Nginx
sudo nginx -t && sudo systemctl restart nginx
sudo systemctl enable nginx
echo "[✅] Nginx 初始部署完成！"

# 创建自动更新 + 健康检测脚本
sudo tee $AUTO_SCRIPT > /dev/null <<'EOL'
#!/bin/bash
NGINX_CONF="/etc/nginx/nginx.conf"
LOG_FILE="/var/log/cf_proxy.log"

# 配置你的 CF 域名列表
CF_DOMAINS=("example.com" "example2.com")  # 注意：部署后可手动修改为真实域名

# 获取 CF IP 列表
get_cf_ips() {
    IPS=()
    for DOMAIN in "${CF_DOMAINS[@]}"; do
        IP=$(dig +short $DOMAIN | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" | head -n1)
        if [ ! -z "$IP" ]; then
            IPS+=("$IP $DOMAIN")
        fi
    done
    echo "${IPS[@]}"
}

CF_IPS=($(get_cf_ips))
if [ ${#CF_IPS[@]} -eq 0 ]; then
    echo "$(date '+%F %T') [❌] 无可用 CF IP" >> $LOG_FILE
    exit 0
fi

# 健康检测函数
check_ip() {
    local IP=$1
    timeout 2 bash -c "echo > /dev/tcp/$IP/443" &>/dev/null
    return $?
}

# 找到第一个可用节点
AVAILABLE_IP=""
for ipdomain in "${CF_IPS[@]}"; do
    IP=$(echo $ipdomain | awk '{print $1}')
    if check_ip $IP; then
        AVAILABLE_IP=$IP
        DOMAIN=$(echo $ipdomain | awk '{print $2}')
        break
    fi
done

if [ -z "$AVAILABLE_IP" ]; then
    echo "$(date '+%F %T') [❌] 所有 CF IP 均不可用" >> $LOG_FILE
    exit 0
fi

# 检查当前 Nginx 配置中的 IP
CURRENT_IP=$(grep -oP '(?<=server )([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(?=:443;)' $NGINX_CONF | head -n1)

# 如果不一样，更新 Nginx upstream
if [ "$AVAILABLE_IP" != "$CURRENT_IP" ]; then
    sed -i "s/$CURRENT_IP/$AVAILABLE_IP/g" $NGINX_CONF
    nginx -t && systemctl reload nginx
    echo "$(date '+%F %T') [✅] CF IP 自动切换: $CURRENT_IP -> $AVAILABLE_IP" >> $LOG_FILE
fi
EOL

sudo chmod +x $AUTO_SCRIPT

# 设置定时任务，每2分钟检测一次
(crontab -l 2>/dev/null; echo "*/2 * * * * $AUTO_SCRIPT") | crontab -

echo "[✅] 多节点自动负载 + 健康检测 + 零中断切换已启用"
echo "VPS IP 访问方式:"
echo "  TCP/HTTPS: https://VPS_IP:$PORT_TCP"
echo "  HTTP: http://VPS_IP:$PORT_HTTP"
echo "日志路径: $LOG_FILE"
