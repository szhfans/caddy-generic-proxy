#!/bin/bash

# ---------- 配置 ----------
TARGET_DOMAIN="example.com"   # 替换为你要代理的域名
NGINX_CONF_DIR="/etc/nginx/conf.d"
UPSTREAM_CONF="$NGINX_CONF_DIR/cf_upstream.conf"

# ---------- 安装 Nginx ----------
if ! command -v nginx &> /dev/null; then
    echo "Nginx 未安装，开始安装..."
    sudo apt update
    sudo apt install -y nginx
fi

# ---------- 创建 conf.d 目录 ----------
sudo mkdir -p $NGINX_CONF_DIR

# ---------- 获取 Cloudflare IP ----------
TMP_CF_IP=$(mktemp)
curl -s https://www.cloudflare.com/ips-v4 > $TMP_CF_IP
curl -s https://www.cloudflare.com/ips-v6 >> $TMP_CF_IP

# ---------- 获取目标域名的 A/AAAA 记录 ----------
TARGET_IPS=$(dig +short $TARGET_DOMAIN A)
TARGET_IPS6=$(dig +short $TARGET_DOMAIN AAAA)
TARGET_IPS="$TARGET_IPS $TARGET_IPS6"

# ---------- 生成 upstream ----------
CF_BACKEND=""
for ip in $TARGET_IPS; do
    for cf in $(cat $TMP_CF_IP); do
        if [[ $ip =~ ^$cf ]]; then
            CF_BACKEND="$CF_BACKEND    server $ip:80 max_fails=3 fail_timeout=10s;"
        fi
    done
done

# fallback
if [ -z "$CF_BACKEND" ]; then
    CF_BACKEND="    server $TARGET_DOMAIN:80;"
fi

# ---------- 写入 Nginx 配置 ----------
sudo tee $UPSTREAM_CONF > /dev/null <<EOF
upstream cf_backend {
$CF_BACKEND
}

server {
    listen 80;
    server_name $TARGET_DOMAIN;

    location / {
        proxy_pass http://cf_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Connection "";
    }
}
EOF

# ---------- 重载 Nginx ----------
sudo nginx -t && sudo systemctl reload nginx
echo "Nginx 配置已更新并重载"
