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

# Tạo file cấu hình pgbouncer.ini trước
cat > /etc/pgbouncer/pgbouncer.ini <<EOF
[databases]
* = host=127.0.0.1 port=${PG_PORT}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = ${PGBOUNCER_PORT}
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
admin_users = postgres
pool_mode = session

ignore_startup_parameters = extra_float_digits

default_pool_size = 20
reserve_pool_size = 5
max_client_conn = 1000

idle_transaction_timeout = 60
EOF

# Set quyền cho pgbouncer.ini
chown postgres:postgres /etc/pgbouncer/pgbouncer.ini
chmod 640 /etc/pgbouncer/pgbouncer.ini

# Đợi PostgreSQL và Patroni khởi động hoàn toàn
echo ">> Đợi PostgreSQL sẵn sàng..."
for i in {1..30}; do
    if sudo -u postgres psql -p ${PG_PORT} -c "SELECT 1" >/dev/null 2>&1; then
        echo "✓ PostgreSQL đã sẵn sàng"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠ PostgreSQL chưa sẵn sàng, tiếp tục nhưng có thể cần cập nhật userlist sau"
    fi
    sleep 2
done

# Tạo file userlist.txt với SCRAM hash từ PostgreSQL
echo ">> Tạo userlist với SCRAM-SHA-256 hash từ PostgreSQL..."
if sudo -u postgres psql -p ${PG_PORT} -c "SELECT 1" >/dev/null 2>&1; then
    # Lấy SCRAM hash từ PostgreSQL
    sudo -u postgres psql -p ${PG_PORT} -t -A -c \
      "SELECT '\"' || usename || '\" \"' || passwd || '\"' 
       FROM pg_shadow 
       WHERE usename IN ('postgres', 'admin', 'percona');" \
      > /etc/pgbouncer/userlist.txt
    
    echo "✓ Đã tạo userlist với SCRAM hash"
else
    # Fallback: tạo file tạm với plaintext (sẽ cần update sau)
    echo "⚠ Không thể kết nối PostgreSQL, tạo userlist tạm thời"
    cat > /etc/pgbouncer/userlist.txt <<EOF
"postgres" "${POSTGRES_PASSWORD}"
EOF
    echo ""
    echo "⚠ CHÚ Ý: Sau khi PostgreSQL khởi động, chạy lệnh sau để cập nhật userlist:"
    echo "   sudo -u postgres psql -p ${PG_PORT} -t -A -c \"SELECT '\\\"' || usename || '\\\" \\\"' || passwd || '\\\"' FROM pg_shadow WHERE usename IN ('postgres', 'admin', 'percona');\" | sudo tee /etc/pgbouncer/userlist.txt"
    echo "   sudo systemctl reload pgbouncer"
fi

# Set quyền cho userlist
chown postgres:postgres /etc/pgbouncer/userlist.txt
chmod 640 /etc/pgbouncer/userlist.txt

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
