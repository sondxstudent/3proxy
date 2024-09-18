# Hướng dẫn cài đặt Proxy IPv6 trên Cloud Server của CloudFly
Để cài đặt Proxy theo range IPv6 tại CloudFly trên máy chủ CentOS 7.9 thì mình thực hiện các bước sau ạ:

## Bước 1. Cấu hình địa chỉ IPv6 vào máy chủ bằng lệnh:

echo "IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPV6ADDR=2001:df7:c600:6:f816:3eff:fe7a:7839/64
IPV6_DEFAULTGW=2001:df7:c600:6::1" >> /etc/sysconfig/network-scripts/ifcfg-eth0

service network restart

==> Lưu ý: Thay đổi IPV6ADDR và IPV6_DEFAULTGW theo đúng thông tin Public IPv6 Network của máy chủ trong Tab Networking. IPV6ADDR là Address IPv6 và IPV6_DEFAULTGW là Gateway

- Kiểm tra cấu hình IPv6 thành công bằng cách chạy lệnh: ping6 cloudfly.vn

Nếu ping trả về gói tin thì cấu hình IPv6 đã thành công và chuyển sang bước 2

## Bước 2. Cài đặt proxy vào máy chủ với Range /112 như sau

curl -sO https://raw.githubusercontent.com/sondxstudent/3proxy/main/ipv6-with-port-password.sh && chmod +x ipv6-with-port-password.sh && bash ipv6-with-port-password.sh


## Bước 3: Lấy thông tin tài khoản

Lấy thông tin tài khoản tại đường dẫn /home/cloudfly. Mở file proxy.txt để lấy các thông tin đăng nhập.

Để cài đặt Proxy không cần username và password thì thay lệnh ở bước 2 thành lệnh dưới
curl -sO https://raw.githubusercontent.com/sondxstudent/3proxy/main/ipv6-with-port-none-password.sh && chmod +x ipv6-with-port-none-password.sh && bash ipv6-with-port-none-password.sh
