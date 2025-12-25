#!/bin/bash

# Script: 06-install-haproxy.sh
# Mô tả: Cài đặt và cấu hình HAProxy
# Chạy trên: Node HAProxy

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

echo "=== Cài đặt và cấu hình HAProxy ==="

# Cài đặt HAProxy
echo ">> Cài đặt HAProxy..."
apt update
apt install -y haproxy

# Backup file cấu hình gốc
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup.$(date +%Y%m%d_%H%M%S)

# Tạo file cấu hình HAProxy
cat > /etc/haproxy/haproxy.cfg <<EOF
global
    maxconn 2000
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    retries 2
    timeout client 3600s
    timeout connect 5s
    timeout server 3600s
    timeout check 5s

listen stats
    mode http
    bind *:${HAPROXY_STATS_PORT}
    stats enable
    stats uri /
    stats refresh 10s
    stats show-legends
    stats show-node

listen primary
    bind *:${HAPROXY_PRIMARY_PORT}
    mode tcp
    balance leastconn
    
    # Health check qua Patroni REST API (HTTP)
    option httpchk GET /primary
    http-check expect status 200
    
    default-server inter 10s fall 3 rise 2
    
    server pg1 ${PG1_IP}:${PGBOUNCER_PORT} maxconn 500 check port ${PATRONI_PORT}
    server pg2 ${PG2_IP}:${PGBOUNCER_PORT} maxconn 500 check port ${PATRONI_PORT}
    server pg3 ${PG3_IP}:${PGBOUNCER_PORT} maxconn 500 check port ${PATRONI_PORT}

listen standbys
    bind *:${HAPROXY_STANDBY_PORT}
    mode tcp
    balance roundrobin
    
    # Health check qua Patroni REST API (HTTP)
    option httpchk GET /replica
    http-check expect status 200
    
    default-server inter 10s fall 3 rise 2
    
    server pg1 ${PG1_IP}:${PGBOUNCER_PORT} maxconn 500 check port ${PATRONI_PORT}
    server pg2 ${PG2_IP}:${PGBOUNCER_PORT} maxconn 500 check port ${PATRONI_PORT}
    server pg3 ${PG3_IP}:${PGBOUNCER_PORT} maxconn 500 check port ${PATRONI_PORT}
EOF

echo "✓ Đã tạo file cấu hình /etc/haproxy/haproxy.cfg"

# Kiểm tra cú pháp cấu hình
echo ">> Kiểm tra cấu hình HAProxy..."
haproxy -c -f /etc/haproxy/haproxy.cfg

# Khởi động HAProxy
echo ">> Khởi động HAProxy..."
systemctl enable haproxy
systemctl restart haproxy
systemctl status haproxy --no-pager

echo ""
echo "✓ HAProxy đã được cài đặt và khởi động"
echo ""
echo "=== Thông tin kết nối ==="
echo ""
echo "HAProxy Stats UI:"
echo "  http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/"
echo ""
echo "PostgreSQL Primary (Read-Write):"
echo "  Host: ${HAPROXY_IP}"
echo "  Port: ${HAPROXY_PRIMARY_PORT}"
echo "  psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U postgres"
echo ""
echo "PostgreSQL Replicas (Read-Only):"
echo "  Host: ${HAPROXY_IP}"
echo "  Port: ${HAPROXY_STANDBY_PORT}"
echo "  psql -h ${HAPROXY_IP} -p ${HAPROXY_STANDBY_PORT} -U postgres"
echo ""
echo "Lưu ý: Sử dụng password đã được cấu hình trong các bước trước"
