#!/bin/bash

# Script: 07-update-pgbouncer-users.sh
# Mô tả: Cập nhật PGBouncer userlist từ PostgreSQL
# Chạy trên: Bất kỳ DB node nào khi thêm user mới

set -e

CONFIG_FILE="/etc/ha_postgres/config.env"

# Màu sắc
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ Script này cần chạy với quyền root!${NC}" 
   exit 1
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Không tìm thấy file cấu hình: $CONFIG_FILE${NC}"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "${YELLOW}=== Cập nhật PGBouncer Userlist ===${NC}"
echo ""

# Kiểm tra PostgreSQL có chạy không
if ! sudo -u postgres psql -p ${PG_PORT} -c "SELECT 1" >/dev/null 2>&1; then
    echo -e "${RED}✗ Không thể kết nối PostgreSQL trên port ${PG_PORT}${NC}"
    echo "Vui lòng kiểm tra PostgreSQL đã khởi động chưa"
    exit 1
fi

# Backup userlist cũ
if [ -f /etc/pgbouncer/userlist.txt ]; then
    cp /etc/pgbouncer/userlist.txt /etc/pgbouncer/userlist.txt.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}✓ Đã backup userlist cũ${NC}"
fi

# Hiển thị danh sách users hiện có trong PostgreSQL
echo ""
echo "Danh sách users trong PostgreSQL:"
sudo -u postgres psql -p ${PG_PORT} -c "SELECT usename FROM pg_shadow ORDER BY usename;"
echo ""

# Hỏi users nào cần thêm vào PGBouncer
read -p "Nhập tên các users cần thêm (cách nhau bởi dấu cách, hoặc 'all' để thêm tất cả): " USERS_INPUT

if [ "$USERS_INPUT" = "all" ]; then
    # Lấy tất cả users
    echo ">> Thêm tất cả users vào PGBouncer userlist..."
    sudo -u postgres psql -p ${PG_PORT} -t -A -c \
      "SELECT '\"' || usename || '\" \"' || passwd || '\"' 
       FROM pg_shadow 
       ORDER BY usename;" \
      > /etc/pgbouncer/userlist.txt
else
    # Lấy các users cụ thể
    # Chuyển input thành SQL array
    USERS_ARRAY=$(echo $USERS_INPUT | sed "s/ /', '/g")
    
    echo ">> Thêm users: $USERS_INPUT vào PGBouncer userlist..."
    sudo -u postgres psql -p ${PG_PORT} -t -A -c \
      "SELECT '\"' || usename || '\" \"' || passwd || '\"' 
       FROM pg_shadow 
       WHERE usename IN ('$USERS_ARRAY')
       ORDER BY usename;" \
      > /etc/pgbouncer/userlist.txt
fi

# Kiểm tra file có nội dung không
if [ ! -s /etc/pgbouncer/userlist.txt ]; then
    echo -e "${RED}✗ Lỗi: File userlist rỗng!${NC}"
    echo "Khôi phục từ backup..."
    cp /etc/pgbouncer/userlist.txt.backup.$(date +%Y%m%d_%H%M%S) /etc/pgbouncer/userlist.txt
    exit 1
fi

# Set quyền
chown postgres:postgres /etc/pgbouncer/userlist.txt
chmod 640 /etc/pgbouncer/userlist.txt

echo -e "${GREEN}✓ Đã cập nhật userlist${NC}"
echo ""
echo "Số lượng users trong userlist:"
wc -l < /etc/pgbouncer/userlist.txt
echo ""

# Reload PGBouncer
echo ">> Reload PGBouncer..."
systemctl reload pgbouncer

if systemctl is-active --quiet pgbouncer; then
    echo -e "${GREEN}✓ PGBouncer đã reload thành công${NC}"
else
    echo -e "${RED}✗ PGBouncer không chạy!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Hoàn thành cập nhật PGBouncer userlist${NC}"
echo ""
echo "Test kết nối:"
echo "  psql -h 127.0.0.1 -p ${PGBOUNCER_PORT} -U <username> -d <database>"
