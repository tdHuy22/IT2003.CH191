#!/bin/bash

# Script cấu hình Raspberry Pi 5 làm edge gateway
# Yêu cầu: WLAN (wlan0, 192.168.1.0/24) -> RasPi -> LAN (eth0, 192.168.2.0/24)
# Access Point với WPA2, NAT, không sử dụng firewall nghiêm ngặt, dùng NetworkManager

# Định nghĩa biến
ETH_IF="eth0"
WLAN_IF="wlan0"
AP_NAME="wlan0-ap"
LAN_NAME="eth0-lan"
SSID="IoT_Network"
WLAN_IP="192.168.1.1/24"
LAN_IP="192.168.2.1/24"
WIFI_PSK="StrongPassword"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
    echo "Script phải được chạy với quyền root (sudo)."
    exit 1
fi

# Kiểm tra giao diện mạng
for iface in "$ETH_IF" "$WLAN_IF"; do
    if ! ip link show "$iface" > /dev/null 2>&1; then
        echo "Lỗi: Giao diện $iface không tồn tại. Kiểm tra phần cứng."
        exit 1
    fi
done

# Khởi động và kiểm tra NetworkManager
echo "Kiểm tra và khởi động NetworkManager..."
systemctl enable --now NetworkManager
if ! systemctl is-active --quiet NetworkManager; then
    echo "Lỗi: Không thể khởi động NetworkManager. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Bật IP forwarding
echo "Bật IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-ip-forwarding.conf
chmod 644 /etc/sysctl.d/99-ip-forwarding.conf

# Đặt khu vực WiFi
echo "Đặt khu vực WiFi..."
iw reg set VN

# Cấu hình Access Point trên wlan0
echo "Cấu hình Access Point trên $WLAN_IF..."
if nmcli con show | grep -q "$AP_NAME"; then
    nmcli con mod "$AP_NAME" wifi.mode ap wifi.ssid "$SSID" ipv4.method shared ipv4.addresses "$WLAN_IP"
    nmcli con mod "$AP_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PSK"
    nmcli con mod "$AP_NAME" wifi.band bg wifi.channel 11
else
    nmcli con add type wifi ifname "$WLAN_IF" con-name "$AP_NAME" autoconnect yes \
        wifi.mode ap wifi.ssid "$SSID" ipv4.method shared ipv4.addresses "$WLAN_IP"
    nmcli con mod "$AP_NAME" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PSK"
    nmcli con mod "$AP_NAME" wifi.band bg wifi.channel 11
fi
if ! nmcli con up "$AP_NAME"; then
    echo "Lỗi: Không thể kích hoạt $AP_NAME. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Cấu hình IP cho giao diện Ethernet
echo "Cấu hình IP cho $ETH_IF..."
if nmcli con show | grep -q "$LAN_NAME"; then
    nmcli con mod "$LAN_NAME" ipv4.method manual ipv4.addresses "$LAN_IP"
else
    nmcli con add type ethernet ifname "$ETH_IF" con-name "$LAN_NAME" autoconnect yes \
        ipv4.method manual ipv4.addresses "$LAN_IP"
fi
if ! nmcli con up "$LAN_NAME"; then
    echo "Lỗi: Không thể kích hoạt $LAN_NAME. Kiểm tra log: journalctl -u NetworkManager"
    exit 1
fi

# Xóa và cấu hình iptables
echo "Cấu hình NAT và forwarding..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Cấu hình NAT
iptables -t nat -A POSTROUTING -o "$ETH_IF" -j MASQUERADE

# Cấu hình forwarding giữa eth0 và wlan0
iptables -A FORWARD -i "$ETH_IF" -o "$WLAN_IF" -j ACCEPT
iptables -A FORWARD -i "$WLAN_IF" -o "$ETH_IF" -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Lưu cấu hình iptables
netfilter-persistent save

# Kiểm tra trạng thái kết nối
echo "Kiểm tra trạng thái kết nối..."
for conn in "$AP_NAME" "$LAN_NAME"; do
    if nmcli -f NAME,DEVICE con show --active | grep -q "$conn"; then
        echo "$conn đã được kích hoạt."
    else
        echo "Lỗi: Không thể kích hoạt $conn. Kiểm tra log: journalctl -u NetworkManager"
        exit 1
    fi
done

# Hoàn tất
echo "Cấu hình hoàn tất. Vui lòng reboot để áp dụng: sudo reboot"
exit 0