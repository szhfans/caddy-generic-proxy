#!/bin/bash
# sing-box VLESS + QUIC/HTTP3 一键安装脚本（自签证书版）
# Author: ChatGPT

set -e

echo "=== sing-box VLESS + HTTP/3 一键安装脚本（自签证书） ==="

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
apt install -y curl socat cron openssl

# 4. 安装 sing-box
bash <(curl -fsSL https://sing-box.app/install.sh)

# 5. 生成自签证书
mkdir -p /etc/sing-box
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/sing-box/key.pem \
  -out /etc/sing-box/cert.pem \
  -days 365 \
  -subj "/CN=$DOMAIN"

echo "自签证书已生成："
echo "证书路径：/etc/sing-box/cert.pem"
echo "密钥路径：/etc/sing-box/key.pem"

# 6. 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID: $UUID"

# 7. 写入 sing-box 配置
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
echo "TLS: 自签证书 (证书有效期 365 天)"
echo ""
echo "=== vless:// 导入链接 ==="
echo "vless://$UUID@$DOMAIN:$PORT?encryption=none&security=tls&sni=$DOMAIN&type=h3#$DOMAIN-H3"
echo ""
echo "⚠️ 注意：客户端需要开启“不验证证书”或“跳过证书验证”，因为使用的是自签证书。"
