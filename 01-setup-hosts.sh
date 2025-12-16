#!/bin/bash

# Script: 01-setup-hosts.sh
# Mô tả: Cấu hình /etc/hosts cho cụm PostgreSQL HA
# Chạy trên: Tất cả nodes (pg1, pg2, pg3, haproxy)

set -e

CONFIG_FILE="/etc/ha_postgres/config.env"

echo "=== Cấu hình /etc/hosts ==="

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

# Backup file hosts hiện tại
cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)

# Xóa cấu hình cũ nếu có
sed -i '/# PostgreSQL HA Cluster/,/# End PostgreSQL HA Cluster/d' /etc/hosts

# Thêm hosts cho cụm PostgreSQL
cat >> /etc/hosts <<EOF

# PostgreSQL HA Cluster
${PG1_IP} pg1
${PG2_IP} pg2
${PG3_IP} pg3
${HAPROXY_IP} haproxy
# End PostgreSQL HA Cluster
EOF

echo "✓ Đã cấu hình /etc/hosts"
echo ""
echo "Nội dung /etc/hosts:"
grep -A 5 "# PostgreSQL HA Cluster" /etc/hosts
