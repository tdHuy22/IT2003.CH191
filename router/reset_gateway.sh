#!/bin/bash

# Script reset cấu hình edge gateway về trạng thái mặc định
# Xóa cấu hình NetworkManager, iptables, sysctl.d

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Script phải được chạy với quyền root (sudo)." 
   exit 1
fi

# Xóa cấu hình NetworkManager
echo "Xóa cấu hình NetworkManager..."
nmcli con delete wlan0-ap eth0-lan 2>/dev/null || true
# for CONN in $(nmcli -f NAME,DEVICE con | grep -E 'wlan0|e(n|x)' | awk '{print $>
#     nmcli con delete "$CONN" 2>/dev/null || true
# done

# Tắt IP forwarding
echo "Tắt IP forwarding..."
sysctl -w net.ipv4.ip_forward=0
rm -f /etc/sysctl.d/99-ip-forwarding.conf

# Xóa quy tắc iptables
echo "Xóa quy tắc iptables..."
iptables -F
iptables -X            
iptables -t nat -F
iptables -t nat -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
netfilter-persistent save

# Khởi động lại NetworkManager
echo "Khởi động lại NetworkManager..."
systemctl restart NetworkManager

# Gỡ cài đặt gói (tùy chọn, bỏ comment nếu muốn)
# echo "Gỡ cài đặt gói..."
# apt purge -y network-manager iptables-persistent netfilter-persistent

# Hoàn tất
echo "Reset hoàn tất. Vui lòng reboot để áp dụng: sudo reboot"
reboot -h now
exit 0
