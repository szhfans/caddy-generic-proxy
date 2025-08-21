#!/bin/bash
# 一键部署 VPS IP 反代 Cloudflare 节点
# 使用方法: sudo bash cf_ip_proxy.sh

# ---------- 用户配置 ----------
read -p "请输入 Cloudflare 边缘节点 IP: " CF_IP
read -p "请输入原始域名（SNI/Host用）: " DOMAIN
read -p "请输入 VPS 监听 TCP/HTTPS 端口（默认8443）: " PORT_TCP
PORT_TCP=${PORT_TCP:-8443}
read -p "请输入 VPS 监听 HTTP 端口（默认8080）: " PORT_HTTP
PORT_HTTP=${PORT_HTTP:-8080}
# --------------------------------

echo "[*] 更新系统并安装 Nginx..."
sudo apt update -y
sudo apt install nginx -y

NGINX_CONF="/etc/nginx/nginx.conf"
BACKUP_CONF="/etc/nginx/nginx.conf.bak"

# 备份原始配置
if [ ! -f "$BACKUP_CONF" ]; then
    sudo cp $NGINX_CONF $BACKUP_CONF
fi

echo "[*] 写入 Nginx stream + HTTP 反代配置..."

sudo tee $NGINX_CONF > /dev/null <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

# TCP/HTTPS 反代
stream {
    upstream cf_up {
        server $CF_IP:443;
    }

    server {
        listen $PORT_TCP;
        proxy_pass cf_up;

        proxy_ssl on;
        proxy_ssl_server_name on;
        proxy_ssl_name $DOMAIN;
    }
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen $PORT_HTTP;

        location / {
            proxy_pass https://$CF_IP;
            proxy_set_header Host $DOMAIN;
            proxy_ssl_server_name on;
            proxy_ssl_name $DOMAIN;
        }
    }
}
EOF

echo "[*] 检查 Nginx 配置..."
sudo nginx -t

echo "[*] 重启 Nginx..."
sudo systemctl restart nginx
sudo systemctl enable nginx

echo "[✅] 部署完成！"
echo "VPS IP 访问方式:"
echo "  TCP/HTTPS: https://VPS_IP:$PORT_TCP"
echo "  HTTP: http://VPS_IP:$PORT_HTTP"
