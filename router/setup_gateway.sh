#!/bin/bash

# Script tự động cấu hình Raspberry Pi 5 làm edge gateway
# Yêu cầu: WLAN (wlan0, 192.168.1.0/24) -> RasPi -> LAN (eth0, 192.168.2.0/24)
# AP với WPA2, NAT, firewall chỉ mở port 8883, sử dụng NetworkManager

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Script phải được chạy với quyền root (sudo)."
   exit 1
fi

# Kiểm tra và phát hiện giao diện Ethernet
if ! ip link show eth0 > /dev/null 2>&1; then
   echo "Lỗi: Giao diện eth0 không tồn tại. Kiểm tra phần cứng Ethernet."
   exit 1
fi

# Kiểm tra giao diện wlan0
if ! ip link show wlan0 > /dev/null 2>&1; then
   echo "Lỗi: Giao diện wlan0 không tồn tại. Kiểm tra phần cứng WiFi."
   exit 1
fi

# Đảm bảo NetworkManager đang chạy
echo "Kiểm tra và khởi động NetworkManager..."
systemctl enable NetworkManager
if ! systemctl is-active --quiet NetworkManager; then
    systemctl start NetworkManager
    if ! systemctl is-active --quiet NetworkManager; then
        echo "Lỗi: Không thể khởi động NetworkManager. Kiểm tra log: journalctl -u NetworkManager"
        exit 1
    fi
fi

# Bật IP forwarding
echo "Bật IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forwarding.conf
chmod 644 /etc/sysctl.d/99-ip-forwarding.conf

# Đặt khu vực WiFi
echo "Đặt khu vực WiFi..."
iw reg set VN

# Kiểm tra và cấu hình Access Point trên wlan0
echo "Cấu hình Access Point trên wlan0 bằng NetworkManager..."
if nmcli con show | grep -q wlan0-ap; then
    nmcli con mod wlan0-ap wifi.mode ap wifi.ssid IoT_Network ipv4.method shared ipv4.addresses 192.168.1.1/24
    nmcli con mod wlan0-ap wifi-sec.key-mgmt wpa-psk wifi-sec.psk StrongPassword
    nmcli con mod wlan0-ap wifi.band bg wifi.channel 11
else
    nmcli con add type wifi ifname wlan0 con-name wlan0-ap autoconnect yes wifi.mode ap wifi.ssid IoT_Network ipv4.method shared ipv4.addresses 192.168.1.1/24
    nmcli con mod wlan0-ap wifi-sec.key-mgmt wpa-psk wifi-sec.psk StrongPassword
    nmcli con mod wlan0-ap wifi.band bg wifi.channel 11
fi
nmcli con up wlan0-ap
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể kích hoạt kết nối wlan0-ap. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Kiểm tra và cấu hình IP cho giao diện Ethernet
echo "Cấu hình IP cho eth0 bằng NetworkManager..."
if nmcli con show | grep -q eth0-lan; then
    nmcli con mod eth0-lan ipv4.method manual ipv4.addresses 192.168.2.1/24
else
    nmcli con add type ethernet ifname eth0 con-name eth0-lan autoconnect yes ipv4.method manual ipv4.addresses 192.168.2.1/24
fi
nmcli con up eth0-lan
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể kích hoạt kết nối eth0-lan. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Cấu hình NAT
echo "Cấu hình NAT..."
iptables -t nat -F
iptables -t nat -X
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
netfilter-persistent save

# Cấu hình firewall
echo "Cấu hình firewall (chỉ mở port 8883, cho phép DHCP và ICMP)..."
iptables -F && iptables -X
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -i eth0 -p udp --dport 67:68 -j ACCEPT
iptables -A INPUT -i wlan0 -p udp --dport 67:68 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT
iptables -P INPUT DROP
iptables -A FORWARD -i wlan0 -o eth0 -p tcp --dport 8883 -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -p icmp --icmp-type echo-request -j ACCEPT
iptables -A FORWARD -i eth0 -o wlan0 -p icmp --icmp-type echo-reply -j ACCEPT
iptables -A FORWARD -i eth0 -o wlan0 -p icmp --icmp-type echo-request -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -p icmp --icmp-type echo-reply -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -P FORWARD DROP
netfilter-persistent save

# Kiểm tra trạng thái AP
echo "Kiểm tra trạng thái Access Point..."
if nmcli -f NAME,DEVICE con show --active | grep -q wlan0-ap; then
    echo "Access Point IoT_Network đã được kích hoạt."
else
    echo "Lỗi: Không thể kích hoạt Access Point. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Kiểm tra trạng thái Ethernet
echo "Kiểm tra trạng thái Ethernet..."
if nmcli -f NAME,DEVICE --active | grep -q eth0-lan; then
    echo "Kết nối Ethernet eth0-lan đã được kích hoạt."
else
    echo "Lỗi: Không thể kích hoạt kết nối eth0-lan. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Hoàn tất
echo "Cấu hình hoàn tất. Vui lòng reboot để áp dụng: sudo reboot"
exit 0