#!/bin/bash
set -e

echo "=== 更新系统 & 安装依赖 ==="
apt update
apt install -y curl wget unzip lsb-release software-properties-common git

echo "=== 安装 OpenResty ==="
wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
add-apt-repository "deb http://openresty.org/package/debian $(lsb_release -sc) main"
apt update
apt install -y openresty

echo "=== 安装 LuaRocks & Lua 库 ==="
apt install -y luarocks
luarocks install lua-resty-http
luarocks install lua-resty-iputils

echo "=== 配置 Nginx 动态 CF 反代 ==="
cat > /etc/openresty/conf.d/dynamic_cf_proxy.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    resolver 1.1.1.1 valid=30s ipv6=on;
    set $upstream "";

    set_by_lua_block $upstream {
        local resolver = require "resty.dns.resolver"
        local iputils = require "resty.iputils"
        iputils.enable_lrucache()

        local cf_ranges = {
            -- IPv4
            "103.21.244.0/22","103.22.200.0/22","103.31.4.0/22",
            "104.16.0.0/13","104.24.0.0/14","108.162.192.0/18",
            "131.0.72.0/22","141.101.64.0/18","162.158.0.0/15",
            "172.64.0.0/13","173.245.48.0/20","188.114.96.0/20",
            "190.93.240.0/20","197.234.240.0/22","198.41.128.0/17",
            -- IPv6
            "2400:cb00::/32","2606:4700::/32","2803:f800::/32",
            "2405:b500::/32","2405:8100::/32","2a06:98c0::/29",
            "2c0f:f248::/32"
        }

        local host = ngx.var.host
        local r, err = resolver:new{nameservers={"1.1.1.1","1.0.0.1"}, retrans=2, timeout=2000}
        if not r then return "" end

        local answers, err = r:query(host)
        if not answers then return "" end

        for _, ans in ipairs(answers) do
            if ans.address then
                for _, cidr in ipairs(cf_ranges) do
                    if iputils.ip_in_cidr(ans.address, cidr) then
                        return ans.address
                    end
                end
            end
        end
        return ""
    }

    location / {
        proxy_pass http://$upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

echo "=== 启动 OpenResty ==="
systemctl enable openresty
systemctl restart openresty

echo "=== 部署完成 ==="
echo "访问任何 Cloudflare 域名即可通过 VPS 反代 CF IP。"
