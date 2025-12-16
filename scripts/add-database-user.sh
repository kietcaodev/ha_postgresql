#!/bin/bash

# Script: add-database-user.sh
# Mô tả: Thêm user mới vào PostgreSQL và đồng bộ sang PGBouncer
# Chạy trên: Primary node

set -e

# Màu sắc
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="/etc/ha_postgres/config.env"

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Thêm User mới vào PostgreSQL HA Cluster                ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

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

# Kiểm tra node hiện tại có phải Primary không
echo ">> Kiểm tra node hiện tại..."
CURRENT_ROLE=$(sudo -u postgres psql -p ${PG_PORT} -t -A -c "SELECT pg_is_in_recovery();" 2>/dev/null || echo "error")

if [ "$CURRENT_ROLE" = "t" ]; then
    echo -e "${RED}✗ Node này là STANDBY/REPLICA${NC}"
    echo "Vui lòng chạy script trên PRIMARY node"
    echo ""
    echo "Kiểm tra PRIMARY node bằng lệnh:"
    echo "  patronictl -c /etc/patroni/patroni.yml list ${SCOPE}"
    exit 1
elif [ "$CURRENT_ROLE" = "error" ]; then
    echo -e "${RED}✗ Không thể kết nối PostgreSQL${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Node này là PRIMARY${NC}"
echo ""

# Nhập thông tin user
echo -e "${YELLOW}=== Thông tin User mới ===${NC}"
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo ""
read -p "Database name (để trống nếu không tạo database mới): " DATABASE
echo ""

# Xác nhận
echo ""
echo -e "${YELLOW}Xác nhận thông tin:${NC}"
echo "  Username: $USERNAME"
echo "  Password: ********"
echo "  Database: ${DATABASE:-<không tạo database mới>}"
echo ""
read -p "Tiếp tục? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Đã hủy"
    exit 0
fi

# Tạo user trong PostgreSQL
echo ""
echo ">> Tạo user trong PostgreSQL..."
sudo -u postgres psql -p ${PG_PORT} <<EOF
CREATE USER ${USERNAME} WITH ENCRYPTED PASSWORD '${PASSWORD}';
GRANT CONNECT ON DATABASE postgres TO ${USERNAME};
EOF

echo -e "${GREEN}✓ Đã tạo user ${USERNAME}${NC}"

# Tạo database nếu được yêu cầu
if [ -n "$DATABASE" ]; then
    echo ">> Tạo database ${DATABASE}..."
    sudo -u postgres psql -p ${PG_PORT} <<EOF
CREATE DATABASE ${DATABASE} OWNER ${USERNAME};
GRANT ALL PRIVILEGES ON DATABASE ${DATABASE} TO ${USERNAME};
EOF
    echo -e "${GREEN}✓ Đã tạo database ${DATABASE}${NC}"
fi

# Cập nhật PGBouncer userlist trên node hiện tại
echo ""
echo ">> Cập nhật PGBouncer userlist trên PRIMARY node..."

# Backup
cp /etc/pgbouncer/userlist.txt /etc/pgbouncer/userlist.txt.backup.$(date +%Y%m%d_%H%M%S)

# Lấy SCRAM hash của user mới
USER_HASH=$(sudo -u postgres psql -p ${PG_PORT} -t -A -c \
  "SELECT '\"' || usename || '\" \"' || passwd || '\"' 
   FROM pg_shadow 
   WHERE usename = '${USERNAME}';")

# Thêm vào userlist
echo "$USER_HASH" >> /etc/pgbouncer/userlist.txt

# Set quyền
chown postgres:postgres /etc/pgbouncer/userlist.txt
chmod 640 /etc/pgbouncer/userlist.txt

# Reload PGBouncer
systemctl reload pgbouncer

echo -e "${GREEN}✓ Đã cập nhật PGBouncer trên PRIMARY node${NC}"

# Hướng dẫn cập nhật trên các node khác
echo ""
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  QUAN TRỌNG: Cập nhật trên các node khác                 ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Chạy lệnh sau trên TỪNG STANDBY NODE (pg2, pg3):"
echo ""
echo -e "${BLUE}./scripts/07-update-pgbouncer-users.sh${NC}"
echo ""
echo "Hoặc chạy thủ công:"
echo ""
echo -e "${BLUE}# Trên pg2 và pg3:"
echo "sudo -u postgres psql -p ${PG_PORT} -t -A -c \\"
echo "  \"SELECT '\\\"' || usename || '\\\" \\\"' || passwd || '\\\"' \\"
echo "   FROM pg_shadow \\"
echo "   WHERE usename = '${USERNAME}';\" \\"
echo "  | sudo tee -a /etc/pgbouncer/userlist.txt"
echo ""
echo "sudo systemctl reload pgbouncer${NC}"
echo ""

# Test kết nối
echo -e "${YELLOW}=== Test kết nối ===${NC}"
echo ""
echo "Test trên PRIMARY node:"
echo "  psql -h 127.0.0.1 -p ${PGBOUNCER_PORT} -U ${USERNAME} -d ${DATABASE:-postgres}"
echo ""
echo "Test qua HAProxy (sau khi update tất cả nodes):"
echo "  psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U ${USERNAME} -d ${DATABASE:-postgres}"
echo ""

echo -e "${GREEN}✓ Hoàn thành!${NC}"
