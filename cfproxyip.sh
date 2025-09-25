================= Dockerfile =================

使用官方 Python 镜像

FROM python:3.11-slim

设置工作目录

WORKDIR /app

安装依赖

COPY requirements.txt requirements.txt RUN pip install --no-cache-dir -r requirements.txt

拷贝脚本

COPY finder.py finder.py

设置入口命令

CMD ["python", "finder.py"]

================= requirements.txt =================

requests beautifulsoup4

================= finder.py =================

import requests import socket import re import time from bs4 import BeautifulSoup

========== 配置区 ==========

shodan_api_key = "YOUR_SHODAN_API_KEY"   # 去 https://account.shodan.io 获取

========== 1. 查询 crt.sh 获取子域名 ==========

def get_subdomains(domain): url = f"https://crt.sh/?q=%25.{domain}&output=json" try: r = requests.get(url, timeout=10) if r.status_code != 200: return [] data = r.json() subdomains = set() for entry in data: name_value = entry["name_value"] for sub in name_value.split("\n"): if sub.endswith(domain): subdomains.add(sub.strip()) return sorted(subdomains) except Exception as e: print("[!] crt.sh 查询失败", e) return []

========== 2. 尝试解析子域名的 IP ==========

def resolve_domain(d): try: return socket.gethostbyname(d) except: return None

========== 3. ViewDNS 历史解析记录 ==========

def get_historical_ips(domain): url = f"https://viewdns.info/iphistory/?domain={domain}" try: r = requests.get(url, timeout=10, headers={"User-Agent": "Mozilla/5.0"}) if r.status_code != 200: return [] soup = BeautifulSoup(r.text, "html.parser") ips = set() for row in soup.find_all("tr"): cols = [c.get_text(strip=True) for c in row.find_all("td")] if len(cols) >= 2 and re.match(r"^\d+.\d+.\d+.\d+$", cols[0]): ips.add(cols[0]) return sorted(ips) except Exception as e: print("[!] ViewDNS 查询失败", e) return []

========== 4. Shodan 搜索证书/域名 ==========

def search_shodan(domain, api_key): if not api_key or api_key == "YOUR_SHODAN_API_KEY": print("[!] 未配置 Shodan API Key，跳过") return [] url = f"https://api.shodan.io/shodan/host/search?key={api_key}&query=hostname:{domain}" try: r = requests.get(url, timeout=15) if r.status_code != 200: print("[!] Shodan 查询失败", r.text) return [] data = r.json() ips = set() for match in data.get("matches", []): if "ip_str" in match: ips.add(match["ip_str"]) return sorted(ips) except Exception as e: print("[!] Shodan 查询出错", e) return []

========== 主流程 ==========

if name == "main": domain = input("请输入要查询的域名 (不带 http/https)： ").strip()

print(f"\n[*] 正在查询 {domain} 的子域名...")
subs = get_subdomains(domain)
print(f"[*] 找到 {len(subs)} 个子域名")

results = {}
for s in subs:
    ip = resolve_domain(s)
    if ip:
        results[s] = ip
    time.sleep(0.5)  # 防止请求过快被封

print("\n[*] 子域名解析结果:")
for s, ip in results.items():
    print(f"{s:30} {ip}")

print("\n[*] 历史解析 IP (ViewDNS):")
hist_ips = get_historical_ips(domain)
for ip in hist_ips:
    print(ip)

print("\n[*] Shodan 查询结果:")
shodan_ips = search_shodan(domain, shodan_api_key)
for ip in shodan_ips:
    print(ip)

