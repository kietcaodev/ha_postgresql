#!/bin/bash

# Script: 04-config-patroni.sh
# Mô tả: Cấu hình Patroni cho bất kỳ node nào
# Chạy trên: Bất kỳ Database Node nào (pg1, pg2, pg3)

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

# Xác định node hiện tại dựa trên IP
CURRENT_IP=$(hostname -I | awk '{print $1}')

if [ "$CURRENT_IP" = "$PG1_IP" ]; then
    NODE_NAME="pg1"
    NODE_IP="$PG1_IP"
elif [ "$CURRENT_IP" = "$PG2_IP" ]; then
    NODE_NAME="pg2"
    NODE_IP="$PG2_IP"
elif [ "$CURRENT_IP" = "$PG3_IP" ]; then
    NODE_NAME="pg3"
    NODE_IP="$PG3_IP"
else
    echo "Không thể xác định node. IP hiện tại: $CURRENT_IP"
    echo "Vui lòng nhập tên node (pg1/pg2/pg3):"
    read -p "Node name: " NODE_NAME
    
    case $NODE_NAME in
        pg1)
            NODE_IP="$PG1_IP"
            ;;
        pg2)
            NODE_IP="$PG2_IP"
            ;;
        pg3)
            NODE_IP="$PG3_IP"
            ;;
        *)
            echo "Tên node không hợp lệ!"
            exit 1
            ;;
    esac
fi

echo "=== Cấu hình Patroni cho node ${NODE_NAME} (${NODE_IP}) ==="

# Dừng và disable PostgreSQL service (Patroni sẽ quản lý)
echo ">> Dừng PostgreSQL service (nếu đang chạy)..."
systemctl stop postgresql 2>/dev/null || true
systemctl disable postgresql 2>/dev/null || true

# Nhập password từ người dùng
echo ""
echo ">> Nhập mật khẩu cho các tài khoản PostgreSQL:"
echo ""
read -s -p "Postgres password: " POSTGRES_PASSWORD
echo ""
read -s -p "Replicator password: " REPLICATOR_PASSWORD
echo ""
read -s -p "Admin password: " ADMIN_PASSWORD
echo ""
read -s -p "Percona password: " PERCONA_PASSWORD
echo ""
echo ""

# Kiểm tra password không được rỗng
if [ -z "$POSTGRES_PASSWORD" ] || [ -z "$REPLICATOR_PASSWORD" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$PERCONA_PASSWORD" ]; then
    echo "✗ Lỗi: Tất cả các password không được để trống!"
    exit 1
fi

# Xóa thư mục data PostgreSQL cũ nếu tồn tại
if [ -d "$DATA_DIR" ]; then
    echo ">> Xóa thư mục data PostgreSQL cũ..."
    rm -rf $DATA_DIR
fi

# Tạo các thư mục cần thiết
mkdir -p ${PATRONI_CONFIG_DIR}
mkdir -p ${PGSQL_DATA_DIR}
mkdir -p ${ARCHIVE_DIR}
chown -R postgres:postgres ${PGSQL_DATA_DIR}
chown -R postgres:postgres ${ARCHIVE_DIR}
chmod 700 ${PGSQL_DATA_DIR}

# Tạo file cấu hình Patroni
cat > ${PATRONI_CONFIG_DIR}/patroni.yml <<EOF
namespace: ${NAMESPACE}
scope: ${SCOPE}
name: ${NODE_NAME}

restapi:
    listen: 0.0.0.0:${PATRONI_PORT}
    connect_address: ${NODE_IP}:${PATRONI_PORT}

etcd3:
    host: ${NODE_IP}:${ETCD_CLIENT_PORT}

bootstrap:
  dcs:
      ttl: 30
      loop_wait: 10
      retry_timeout: 10
      maximum_lag_on_failover: 1048576

      postgresql:
          use_pg_rewind: true
          use_slots: true
          parameters:
              wal_level: replica
              hot_standby: "on"
              max_wal_senders: 5
              max_replication_slots: 10
              wal_log_hints: "on"
              logging_collector: 'on'
              max_wal_size: '10GB'
              archive_mode: "on"
              archive_timeout: 600s
              archive_command: "cp -f %p ${ARCHIVE_DIR}/%f"

  initdb:
      - encoding: UTF8
      - data-checksums

  pg_hba:
      - host replication replicator 127.0.0.1/32 trust
      - host replication replicator 0.0.0.0/0 md5
      - host all all 0.0.0.0/0 md5
      - host all all ::0/0 md5

  users:
      admin:
          password: ${ADMIN_PASSWORD}
          options:
              - createrole
              - createdb
      percona:
          password: ${PERCONA_PASSWORD}
          options:
              - createrole
              - createdb

postgresql:
    cluster_name: cluster_1
    listen: 0.0.0.0:${PG_PORT}
    connect_address: ${NODE_IP}:${PG_PORT}
    data_dir: ${DATA_DIR}
    bin_dir: ${PG_BIN_DIR}
    pgpass: ${PGSQL_DATA_DIR}/pgpass0
    authentication:
        replication:
            username: replicator
            password: ${REPLICATOR_PASSWORD}
        superuser:
            username: postgres
            password: ${POSTGRES_PASSWORD}
    parameters:
        unix_socket_directories: "/var/run/postgresql/"
    create_replica_methods:
        - basebackup
    basebackup:
        checkpoint: 'fast'

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
EOF

# Set quyền cho file cấu hình
chown postgres:postgres ${PATRONI_CONFIG_DIR}/patroni.yml
chmod 600 ${PATRONI_CONFIG_DIR}/patroni.yml

echo "✓ Đã tạo file cấu hình ${PATRONI_CONFIG_DIR}/patroni.yml"

# Khởi động Patroni
echo ">> Khởi động Patroni..."
systemctl enable patroni
systemctl start patroni

# Đợi Patroni khởi động
sleep 10

systemctl status patroni --no-pager

echo ""
echo "✓ Patroni đã được khởi động trên ${NODE_NAME}"
echo ""
echo "Kiểm tra cluster:"
sleep 5
patronictl -c ${PATRONI_CONFIG_DIR}/patroni.yml list ${SCOPE}

echo ""
echo "Kiểm tra qua REST API:"
curl -s http://${NODE_IP}:${PATRONI_PORT}/ | head -20

echo ""
echo "✓ Hoàn thành cấu hình Patroni cho ${NODE_NAME}"
