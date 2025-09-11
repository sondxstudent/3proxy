# Hướng dẫn cài đặt Proxy IPv6 trên Cloud Server của CloudFly
Để cài đặt Proxy theo range IPv6 tại CloudFly trên máy chủ CentOS 7.9 thì mình thực hiện các bước sau ạ:
## Bước 0.

sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo

sed -i s/^#.*baseurl=http/baseurl=http/g /etc/yum.repos.d/*.repo

sed -i s/^mirrorlist=http/#mirrorlist=http/g /etc/yum.repos.d/*.repo

echo "sslverify=false" >> /etc/yum.conf

## Bước 1. Cấu hình địa chỉ IPv6 vào máy chủ bằng lệnh:

echo "IPV6_FAILURE_FATAL=no

IPV6_ADDR_GEN_MODE=stable-privacy

IPV6ADDR=2001:df7:c600:6:f816:3eff:fe7a:7839/64

IPV6_DEFAULTGW=2001:df7:c600:6::1" >> /etc/sysconfig/network-scripts/ifcfg-eth0

service network restart

==> Lưu ý: Thay đổi IPV6ADDR và IPV6_DEFAULTGW theo đúng thông tin Public IPv6 Network của máy chủ trong Tab Networking. IPV6ADDR là Address IPv6 và IPV6_DEFAULTGW là Gateway

- Kiểm tra cấu hình IPv6 thành công bằng cách chạy lệnh: ping6 cloudfly.vn

Nếu ping trả về gói tin thì cấu hình IPv6 đã thành công và chuyển sang bước 2

## Cách I:. Cài đặt proxy vào máy chủ với Range /112 như sau

curl -sO https://raw.githubusercontent.com/sondxstudent/3proxy/main/ipv6-with-port-password.sh && chmod +x ipv6-with-port-password.sh && bash ipv6-with-port-password.sh

Để cài đặt Proxy không cần username và password thì thay lệnh ở bước 2 thành lệnh dưới
curl -sO https://raw.githubusercontent.com/sondxstudent/3proxy/main/ipv6-with-port-none-password.sh && chmod +x ipv6-with-port-none-password.sh && bash ipv6-with-port-none-password.sh


## Bước: Lấy thông tin proxy

cat /home/cloudfly/proxy.txt

## Cách II: white list IP 09/2025

# 1. Tải script về VPS
curl -fsSLO https://raw.githubusercontent.com/sondxstudent/3proxy/main/setup_3proxy_ipv6_whitelist.sh

# 2. Đảm bảo file không dính CRLF (nếu có, chuyển sang LF)
sed -i 's/\r$//' setup_3proxy_ipv6_whitelist.sh

# 3. Cấp quyền thực thi
chmod +x setup_3proxy_ipv6_whitelist.sh

# 4. Chạy script bằng bash

/bin/bash setup_3proxy_ipv6_whitelist.sh

-----
fix giới hạn  rồi thêm wl

ulimit -n 65535

----
#5. Nếu muốn thêm WL example ip: 203.0.113.45

echo "203.0.113.45" >> /usr/local/etc/3proxy/whitelist.txt

pkill 3proxy

/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg





