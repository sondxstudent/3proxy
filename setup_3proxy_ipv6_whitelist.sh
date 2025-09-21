#!/usr/bin/env bash
set -e
set -u
set -o pipefail

### ====== CẤU HÌNH CƠ BẢN ======
WORKDIR="/home/cloudfly"
WORKDATA="${WORKDIR}/data.txt"           # Lưu danh sách IP4/PORT/IPv6
THROTTLE_PORTS=2000                       # Số port muốn tạo (tối đa)
MAX_FD=65535                              # ulimit -n
EPHEMERAL_START=49152
EPHEMERAL_END=65535

# File chứa whitelist IP (mỗi IP một dòng)
WHITELIST_FILE="/usr/local/etc/3proxy/whitelist.txt"
# Nếu chưa có whitelist.txt thì tạo mặc định
if [[ ! -f ${WHITELIST_FILE} ]]; then
  mkdir -p "$(dirname ${WHITELIST_FILE})"
  cat > ${WHITELIST_FILE} <<EOF
42.117.81.179
EOF
  echo "[*] Tạo whitelist.txt mặc định tại ${WHITELIST_FILE}"
fi


### ====== HÀM PHỤ TRỢ ======
ipv6_tail() {
  local hex=({0..9} a b c d e f)
  printf "%s:%s:%s:%s" \
    "${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}" \
    "${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}" \
    "${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}" \
    "${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}${hex[$RANDOM%16]}"
}

detect_iface() { ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1; }
assert_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Thiếu lệnh bắt buộc: $1"; exit 1; }; }

### ====== CÀI GÓI CẦN THIẾT ======
echo "[*] Installing required packages..."
yum -y install -q gcc make net-tools bsdtar zip curl >/dev/null

assert_cmd curl; assert_cmd ip; assert_cmd make; assert_cmd gcc; assert_cmd bsdtar

### ====== LẤY IP4, PREFIX IPv6 /64 ======
IP4="$(curl -4 -s icanhazip.com || true)"
IP6_PREFIX="$(curl -6 -s icanhazip.com | cut -d':' -f1-4 || true)"   # 4 hextet đầu làm prefix /64

if [[ -z "${IP6_PREFIX}" ]]; then
  echo "[!] VPS chưa có IPv6 public /64 (curl -6 thất bại). Hãy gán IPv6 rồi chạy lại."
  exit 1
fi

IFACE="$(detect_iface)"
if [[ -z "${IFACE}" ]]; then
  echo "[!] Không phát hiện được interface mạng mặc định."; exit 1
fi

echo "[i] IPv4: ${IP4}"
echo "[i] IPv6 prefix (/64): ${IP6_PREFIX}::/64"
echo "[i] Interface: ${IFACE}"

### ====== CHỌN DẢI PORT ======
read -rp "Nhập FIRST_PORT (khuyến nghị 21000–49000, tránh 49152–65535): " FIRST_PORT
if ! [[ "${FIRST_PORT}" =~ ^[0-9]+$ ]]; then echo "FIRST_PORT không hợp lệ"; exit 1; fi

CANDIDATE_LAST=$(( FIRST_PORT + THROTTLE_PORTS - 1 ))
LAST_PORT=$(( CANDIDATE_LAST > 65535 ? 65535 : CANDIDATE_LAST ))

if (( FIRST_PORT < 1024 || FIRST_PORT > 65535 )); then echo "FIRST_PORT phải trong 1024–65535"; exit 1; fi
if (( FIRST_PORT <= EPHEMERAL_END && LAST_PORT >= EPHEMERAL_START )); then
  echo "[!] Cảnh báo: dải ${FIRST_PORT}-${LAST_PORT} giao với ephemeral ${EPHEMERAL_START}-${EPHEMERAL_END}."
  echo "    Tự động cắt LAST_PORT để tránh va chạm."
  LAST_PORT=$(( EPHEMERAL_START - 1 ))
fi
if (( LAST_PORT < FIRST_PORT )); then
  echo "[!] Dải port sau khi tránh ephemeral không còn hợp lệ. Chọn FIRST_PORT < ${EPHEMERAL_START}."; exit 1
fi
echo "[i] Sử dụng dải PORT: ${FIRST_PORT} – ${LAST_PORT}"

### ====== TẠO THƯ MỤC LÀM VIỆC ======
echo "[*] Preparing workdir: ${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

### ====== DOWN & BUILD 3PROXY ======
echo "[*] Building 3proxy..."
URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
curl -sL "$URL" | bsdtar -xvf- >/dev/null
pushd 3proxy-3proxy-0.8.6 >/dev/null
make -s -f Makefile.Linux
mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/
popd >/dev/null

### ====== TẠO DATA: IP4/PORT/IPv6 ======
echo "[*] Generating IPv6 and port map..."
:> "${WORKDATA}"
for ((port=FIRST_PORT; port<=LAST_PORT; port++)); do
  echo "${IP4}/${port}/${IP6_PREFIX}:$(ipv6_tail)" >> "${WORKDATA}"
done

### ====== THÊM ĐỊA CHỈ IPv6 VÀO INTERFACE ======
echo "[*] Adding IPv6 addresses to ${IFACE}..."
BOOT_IFCFG="${WORKDIR}/boot_ifconfig.sh"
:> "${BOOT_IFCFG}"
while IFS='/' read -r ip4 port ip6full; do
  echo "ip -6 addr add ${ip6full}/64 dev ${IFACE} || true" >> "${BOOT_IFCFG}"
done < "${WORKDATA}"
chmod +x "${BOOT_IFCFG}"
bash "${BOOT_IFCFG}"

### ====== FIREWALL RULES (IPv4 + IPv6) ======
echo "[*] Opening firewall ports..."
BOOT_IPT="${WORKDIR}/boot_iptables.sh"
:> "${BOOT_IPT}"
while IFS='/' read -r ip4 port ip6full; do
  echo "iptables -I INPUT -p tcp --dport ${port} -j ACCEPT || true" >> "${BOOT_IPT}"
  echo "ip6tables -I INPUT -p tcp --dport ${port} -j ACCEPT || true" >> "${BOOT_IPT}"
done < "${WORKDATA}"
chmod +x "${BOOT_IPT}"
bash "${BOOT_IPT}" || true

### ====== TẠO CẤU HÌNH 3PROXY (ip:port + whitelist IP) ======
echo "[*] Writing 3proxy config..."
CFG="/usr/local/etc/3proxy/3proxy.cfg"
{
  cat <<'HDR'
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
stacksize 6291456
flush
HDR

  if id nobody &>/dev/null; then
    echo "setgid $(id -g nobody)"
    echo "setuid $(id -u nobody)"
  else
    echo "setgid 65535"
    echo "setuid 65535"
  fi

  echo "auth iponly"
  if [[ -f ${WHITELIST_FILE} ]]; then
    while read -r ip; do
      [[ -n "$ip" ]] && echo "allow * $ip"
    done < ${WHITELIST_FILE}
  fi
  echo "deny *"

  while IFS='/' read -r ip4 port ip6full; do
    echo "proxy -6 -n -a -p${port} -i${ip4} -e${ip6full}"
    echo "flush"
  done < "${WORKDATA}"
} > "${CFG}"

### ====== XUẤT DANH SÁCH CHỈ ip:port ======
echo "[*] Writing proxy_ipport.txt (ip:port)..."
OUT="${WORKDIR}/proxy_ipport.txt"
:> "${OUT}"
while IFS='/' read -r ip4 port ip6full; do
  echo "${ip4}:${port}" >> "${OUT}"
done < "${WORKDATA}"
echo "[i] Danh sách ip:port: ${OUT}"

### ====== CẤU HÌNH RC.LOCAL (KHỞI ĐỘNG CÙNG HỆ THỐNG) ======
echo "[*] Setting rc.local autostart..."
cat >/etc/rc.d/rc.local <<EOF
#!/bin/bash
set -e
ulimit -n ${MAX_FD} || true
bash ${BOOT_IPT} || true
bash ${BOOT_IFCFG} || true
/usr/local/etc/3proxy/bin/3proxy ${CFG} || true
EOF
chmod +x /etc/rc.d/rc.local
if systemctl list-unit-files | grep -q rc-local.service; then
  systemctl enable rc-local.service >/dev/null 2>&1 || true
fi

### ====== KHỞI ĐỘNG 3PROXY NGAY BÂY GIỜ ======
echo "[*] Starting 3proxy..."
ulimit -n "${MAX_FD}" || true
pkill 3proxy >/dev/null 2>&1 || true
/usr/local/etc/3proxy/bin/3proxy "${CFG}"

echo
echo "================= HOÀN TẤT ================="
echo "Whitelist IP file: ${WHITELIST_FILE}"
echo "Để thêm IP mới: echo 'x.x.x.x' >> ${WHITELIST_FILE} && pkill 3proxy && /usr/local/etc/3proxy/bin/3proxy ${CFG}"
echo "Proxy list (ip:port): ${OUT}"



