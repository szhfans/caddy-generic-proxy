#!/bin/bash

# 目标域名
TARGET_DOMAIN="example.com"

# 临时文件
TMP_CF_IP="/tmp/cf-ips.txt"
TMP_UPSTREAM="/etc/nginx/conf.d/cf_upstream.conf"

# 拉取 Cloudflare 公共 IP 段
curl -s https://www.cloudflare.com/ips-v4 > $TMP_CF_IP
curl -s https://www.cloudflare.com/ips-v6 >> $TMP_CF_IP

# 获取目标域名的 A/AAAA 记录
TARGET_IPS=$(dig +short $TARGET_DOMAIN A)
TARGET_IPS6=$(dig +short $TARGET_DOMAIN AAAA)
TARGET_IPS="$TARGET_IPS $TARGET_IPS6"

# 过滤出属于 CF 的 IP
CF_BACKEND=""
for ip in $TARGET_IPS; do
    for cf in $(cat $TMP_CF_IP); do
        if [[ $ip =~ ^$cf ]]; then
            CF_BACKEND="$CF_BACKEND    server $ip:80 max_fails=3 fail_timeout=10s;"
        fi
    done
done

# 如果没有匹配到 CF IP，则直接使用域名
if [ -z "$CF_BACKEND" ]; then
    CF_BACKEND="    server $TARGET_DOMAIN:80;"
fi

# 生成 Nginx upstream 配置
cat > $TMP_UPSTREAM <<EOF
upstream cf_backend {
    # 自动轮询，提高稳定性
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

# 重载 Nginx
nginx -s reload
echo "Nginx 配置已更新并重载"
