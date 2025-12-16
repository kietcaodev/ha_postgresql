#!/bin/bash

# Script: 05-install-pgbouncer.sh
# Mô tả: Cài đặt và cấu hình PGBouncer
# Chạy trên: Tất cả 3 node DB (pg1, pg2, pg3)

set -e

CONFIG_FILE="/etc/ha_postgres/config.env"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Script này cần chạy với quyền root!" 
   exit 1
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "✗ Không tìm thấy file cấu hình: $CONFIG_FILE"
    echo "Vui lòng chạy ./00-setup-config.sh trước!"
    exit 1
fi

source "$CONFIG_FILE"

echo "=== Cài đặt và cấu hình PGBouncer ==="

# Nhập password từ người dùng
echo ""
read -s -p "Nhập Postgres password: " POSTGRES_PASSWORD
echo ""
echo ""

# Kiểm tra password không được rỗng
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "✗ Lỗi: Password không được để trống!"
    exit 1
fi

# Cài đặt PGBouncer
echo ">> Cài đặt PGBouncer..."
apt install -y pgbouncer

# Stop service để cấu hình
systemctl stop pgbouncer

# Backup file cấu hình gốc
cp /etc/pgbouncer/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini.backup

# Tạo file userlist.txt với password
cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "${POSTGRES_PASSWORD}"
EOF

# Tạo file cấu hình pgbouncer.ini
cat > /etc/pgbouncer/pgbouncer.ini <<EOF
[databases]
* = host=127.0.0.1 port=${PG_PORT}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = ${PGBOUNCER_PORT}
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
admin_users = postgres
pool_mode = transaction

ignore_startup_parameters = extra_float_digits

default_pool_size = 20
reserve_pool_size = 5
max_client_conn = 1000

idle_transaction_timeout = 60
EOF

# Set quyền cho các file
chown postgres:postgres /etc/pgbouncer/userlist.txt
chown postgres:postgres /etc/pgbouncer/pgbouncer.ini
chmod 640 /etc/pgbouncer/userlist.txt
chmod 640 /etc/pgbouncer/pgbouncer.ini

# Tạo thư mục log nếu chưa có
mkdir -p /var/log/postgresql
chown postgres:postgres /var/log/postgresql

echo "✓ Đã cấu hình PGBouncer"

# Khởi động PGBouncer
echo ">> Khởi động PGBouncer..."
systemctl enable pgbouncer
systemctl start pgbouncer
systemctl status pgbouncer --no-pager

echo ""
echo "✓ PGBouncer đã được cài đặt và khởi động"
echo ""
echo "Thông tin kết nối:"
echo "  Host: localhost"
echo "  Port: ${PGBOUNCER_PORT}"
echo "  User: postgres"
echo "  Password: (password bạn đã nhập)"
echo ""
echo "Kiểm tra kết nối:"
echo "  psql -h localhost -p ${PGBOUNCER_PORT} -U postgres -c 'SELECT version();'"
