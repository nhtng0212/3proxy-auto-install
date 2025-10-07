#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "🔧 Đang cài đặt 3proxy, vui lòng đợi..."

# Cài gói cần thiết
sudo apt update >/dev/null 2>&1
sudo apt install -y git make gcc ufw curl >/dev/null 2>&1 || true
sleep 1

# Về thư mục /opt
cd /opt || sudo mkdir -p /opt && cd /opt

# Clone 3proxy (nếu đã có repo thì bỏ bước clone)
if [ ! -d "3proxy" ]; then
  sudo git clone https://github.com/z3APA3A/3proxy.git >/dev/null 2>&1 || true
fi
cd 3proxy || exit 1

# Biên dịch
make -f Makefile.Linux >/dev/null 2>&1 || true

# Tạo thư mục config/log và copy binary
sudo mkdir -p /etc/3proxy/logs
if [ -f src/3proxy ]; then
  sudo cp src/3proxy /usr/local/bin/3proxy
  sudo chmod +x /usr/local/bin/3proxy
else
  echo "❌ Không tìm thấy src/3proxy sau khi build."
  exit 1
fi

# Mở dải cổng proxy
sudo ufw allow 10000:10100/tcp >/dev/null 2>&1 || true

CONFIG_FILE="/etc/3proxy/3proxy.cfg"
echo "⚙️ Đang tạo file cấu hình 3proxy..."
sleep 1

# Lấy prefix IPv6 (4 block đầu) — sửa tuỳ theo tên interface (eth0)
IFACE="eth0"
IPV6_FULL=$(ip -6 addr show dev "$IFACE" | grep 'inet6' | grep -v fe80 | awk '{print $2}' | head -n1)
if [ -z "$IPV6_FULL" ]; then
  echo "❌ Không tìm thấy IPv6 trên $IFACE. Kiểm tra interface hoặc máy chưa có IPv6."
  exit 1
fi

IPV6_ADDR=$(echo "$IPV6_FULL" | cut -d'/' -f1)
# Lấy 4 hextet đầu (prefix) và đảm bảo kết thúc bằng ':'
IPV6_PREFIX=$(echo "$IPV6_ADDR" | awk -F: '{print $1":"$2":"$3":"$4":"}')

randhex() { printf "%04x" $((RANDOM % 0x10000)); }
gen_ipv6() { echo "${IPV6_PREFIX}$(randhex):$(randhex):$(randhex):$(randhex)"; }

# Viết header config
sudo tee "$CONFIG_FILE" >/dev/null <<'EOF'
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy/3proxy.log D
auth strong
# Định nghĩa user theo định dạng user:CL:password (thay đổi ngay)
users USLA:CL:CLIP@proxy2025v6
allow USLA
EOF

# Tạo proxy/socks entries cho dải port 10000..10100
for port in {10000..10100}; do
  ip6=$(gen_ipv6)
  # Thêm địa chỉ IPv6 lên interface (không lặp lỗi nếu đã có)
  sudo ip -6 addr add "${ip6}/64" dev "$IFACE" 2>/dev/null || true

  # Ở đây default là socks; nếu muốn http => thay "socks" bằng "proxy"
  echo "socks -6 -n -a -p${port} -i0.0.0.0 -e${ip6}" | sudo tee -a "$CONFIG_FILE" >/dev/null
done

echo "flush" | sudo tee -a "$CONFIG_FILE" >/dev/null

# Tạo systemd service
sudo tee /etc/systemd/system/3proxy.service >/dev/null <<'EOF'
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable 3proxy >/dev/null 2>&1 || true
sudo systemctl restart 3proxy || sudo systemctl start 3proxy

echo "✅ Cài đặt hoàn tất!"
