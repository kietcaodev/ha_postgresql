#!/bin/bash

# Script: 03-config-etcd-pg2.sh
# Mô tả: Cấu hình etcd cho node pg2
# Chạy trên: Node pg2
# Yêu cầu: Đã thêm pg2 vào cluster từ pg1

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

NODE_NAME="pg2"
NODE_IP="$PG2_IP"

echo "=== Cấu hình etcd cho node ${NODE_NAME} (${NODE_IP}) ==="

echo "⚠ QUAN TRỌNG: Trước khi chạy script này, cần thực hiện trên pg1:"
echo "  etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg2 --peer-urls=http://${PG2_IP}:${ETCD_PEER_PORT}"
echo ""
read -p "Đã thực hiện lệnh trên chưa? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Vui lòng thực hiện lệnh add member trên pg1 trước!"
    exit 1
fi

# Tạo file cấu hình etcd
cat > /etc/etcd/etcd.conf <<EOF
ETCD_NAME=${NODE_NAME}
ETCD_DATA_DIR=${ETCD_DATA_DIR}
ETCD_LISTEN_PEER_URLS=http://${NODE_IP}:${ETCD_PEER_PORT}
ETCD_LISTEN_CLIENT_URLS=http://${NODE_IP}:${ETCD_CLIENT_PORT},http://127.0.0.1:${ETCD_CLIENT_PORT}
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${NODE_IP}:${ETCD_PEER_PORT}
ETCD_ADVERTISE_CLIENT_URLS=http://${NODE_IP}:${ETCD_CLIENT_PORT}
ETCD_INITIAL_CLUSTER=pg1=http://${PG1_IP}:${ETCD_PEER_PORT},pg2=http://${PG2_IP}:${ETCD_PEER_PORT}
ETCD_INITIAL_CLUSTER_TOKEN=${SCOPE}
ETCD_INITIAL_CLUSTER_STATE=existing
EOF

echo "✓ Đã tạo file cấu hình /etc/etcd/etcd.conf"

# Đảm bảo thư mục data có quyền đúng
mkdir -p ${ETCD_DATA_DIR}
chown -R etcd:etcd ${ETCD_DATA_DIR}

# Khởi động etcd
echo ">> Khởi động etcd..."
systemctl enable etcd
systemctl start etcd
systemctl status etcd --no-pager

echo ""
echo "✓ etcd đã được khởi động trên ${NODE_NAME}"
echo ""
echo "Kiểm tra member list:"
sleep 3
etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member list

echo ""
echo "=== Hướng dẫn thêm node pg3 ==="
echo ""
echo "Trên node pg1, chạy lệnh sau để thêm pg3:"
echo "  etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg3 --peer-urls=http://${PG3_IP}:${ETCD_PEER_PORT}"
echo ""
echo "Sau đó chạy script 03-config-etcd-pg3.sh trên node pg3"
