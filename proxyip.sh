#!/bin/bash
# sing-box VLESS + QUIC/HTTP3 一键安装脚本
# Author: ChatGPT

set -e

echo "=== sing-box VLESS + HTTP/3 一键安装脚本 ==="

# 1. 输入域名
read -p "请输入绑定到 VPS 的域名: " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "域名不能为空！"
  exit 1
fi

# 2. 输入端口
read -p "请输入端口 (默认 443): " PORT
PORT=${PORT:-443}

# 3. 安装依赖
apt update -y
apt install -y curl socat cron

# 4. 安装 acme.sh 并申请证书
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256 --force
~/.acme.sh/acme.sh --install-cert -d $DOMAIN --ecc \
  --fullchain-file /etc/sing-box/cert.pem \
  --key-file /etc/sing-box/key.pem

# 5. 安装 sing-box
bash <(curl -fsSL https://sing-box.app/install.sh)

# 6. 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

# 7. 写入配置文件
cat > /etc/sing-box/config.json <<EOF
{
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DOMAIN",
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/key.pem"
      },
      "transport": {
        "type": "h3"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# 8. 启动 sing-box
systemctl enable sing-box
systemctl restart sing-box

# 9. 输出结果
echo "=== 安装完成！ ==="
echo "服务器地址: $DOMAIN"
echo "端口: $PORT"
echo "UUID: $UUID"
echo "协议: VLESS"
echo "传输: HTTP/3 (QUIC)"
echo "TLS: 已启用 (证书自动申请)"
echo ""
echo "=== vless:// 导入链接 ==="
echo "vless://$UUID@$DOMAIN:$PORT?encryption=none&security=tls&sni=$DOMAIN&type=h3#$DOMAIN-H3"
