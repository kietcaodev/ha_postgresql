#!/bin/bash

# Script: 00-setup-config.sh
# Mô tả: Thiết lập cấu hình cho PostgreSQL HA Cluster
# Chạy đầu tiên để cấu hình IP addresses và thông tin cluster

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
║   PostgreSQL HA Cluster - Configuration Setup            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ Script này cần chạy với quyền root!${NC}" 
   exit 1
fi

# Tạo thư mục config
mkdir -p /etc/ha_postgres

# Function để validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function để nhập IP với validation
input_ip() {
    local prompt=$1
    local default=$2
    local ip
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$prompt [$default]: " ip
            ip=${ip:-$default}
        else
            read -p "$prompt: " ip
        fi
        
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        else
            echo -e "${RED}✗ IP không hợp lệ! Vui lòng nhập lại.${NC}"
        fi
    done
}

# Function để hiển thị cấu hình và xác nhận
confirm_config() {
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║           THÔNG TIN CẤU HÌNH                              ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Database Nodes:${NC}"
    echo "  pg1: $PG1_IP"
    echo "  pg2: $PG2_IP"
    echo "  pg3: $PG3_IP"
    echo ""
    echo -e "${GREEN}HAProxy Node:${NC}"
    echo "  haproxy: $HAPROXY_IP"
    echo ""
    echo -e "${GREEN}Cluster Configuration:${NC}"
    echo "  Namespace: $NAMESPACE"
    echo "  Scope: $SCOPE"
    echo "  PostgreSQL Version: $PG_VERSION"
    echo "  Data Directory: $DATA_DIR"
    echo ""
    echo -e "${GREEN}Network Ports:${NC}"
    echo "  PostgreSQL: $PG_PORT"
    echo "  PGBouncer: $PGBOUNCER_PORT"
    echo "  Patroni REST API: $PATRONI_PORT"
    echo "  etcd Client: $ETCD_CLIENT_PORT"
    echo "  etcd Peer: $ETCD_PEER_PORT"
    echo "  HAProxy Primary: $HAPROXY_PRIMARY_PORT"
    echo "  HAProxy Standby: $HAPROXY_STANDBY_PORT"
    echo "  HAProxy Stats: $HAPROXY_STATS_PORT"
    echo ""
    
    read -p "Cấu hình này có đúng không? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Kiểm tra xem đã có config chưa
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠ Đã tồn tại file cấu hình: $CONFIG_FILE${NC}"
    echo ""
    cat "$CONFIG_FILE"
    echo ""
    read -p "Bạn có muốn tạo cấu hình mới? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Giữ nguyên cấu hình hiện tại."
        exit 0
    fi
fi

# Loop cho đến khi user xác nhận cấu hình đúng
while true; do
    echo ""
    echo -e "${BLUE}═══ Nhập thông tin IP Addresses ═══${NC}"
    echo ""
    
    PG1_IP=$(input_ip "Nhập IP cho Database Node 1 (pg1)" "")
    PG2_IP=$(input_ip "Nhập IP cho Database Node 2 (pg2)" "")
    PG3_IP=$(input_ip "Nhập IP cho Database Node 3 (pg3)" "")
    HAPROXY_IP=$(input_ip "Nhập IP cho HAProxy Node" "")
    
    echo ""
    echo -e "${BLUE}═══ Cấu hình Cluster ═══${NC}"
    echo ""
    
    read -p "Nhập Namespace [pg_percona]: " NAMESPACE
    NAMESPACE=${NAMESPACE:-pg_percona}
    
    read -p "Nhập Scope/Cluster Name [pg_cluster]: " SCOPE
    SCOPE=${SCOPE:-pg_cluster}
    
    read -p "Nhập PostgreSQL Version [18]: " PG_VERSION
    PG_VERSION=${PG_VERSION:-18}
    
    read -p "Nhập Data Directory [/var/lib/postgresql/${PG_VERSION}/main]: " DATA_DIR
    DATA_DIR=${DATA_DIR:-/var/lib/postgresql/${PG_VERSION}/main}
    
    echo ""
    echo -e "${BLUE}═══ Cấu hình Network Ports ═══${NC}"
    echo ""
    
    read -p "PostgreSQL Port [5432]: " PG_PORT
    PG_PORT=${PG_PORT:-5432}
    
    read -p "PGBouncer Port [6432]: " PGBOUNCER_PORT
    PGBOUNCER_PORT=${PGBOUNCER_PORT:-6432}
    
    read -p "Patroni REST API Port [8008]: " PATRONI_PORT
    PATRONI_PORT=${PATRONI_PORT:-8008}
    
    read -p "etcd Client Port [2379]: " ETCD_CLIENT_PORT
    ETCD_CLIENT_PORT=${ETCD_CLIENT_PORT:-2379}
    
    read -p "etcd Peer Port [2380]: " ETCD_PEER_PORT
    ETCD_PEER_PORT=${ETCD_PEER_PORT:-2380}
    
    read -p "HAProxy Primary Port [5000]: " HAPROXY_PRIMARY_PORT
    HAPROXY_PRIMARY_PORT=${HAPROXY_PRIMARY_PORT:-5000}
    
    read -p "HAProxy Standby Port [5001]: " HAPROXY_STANDBY_PORT
    HAPROXY_STANDBY_PORT=${HAPROXY_STANDBY_PORT:-5001}
    
    read -p "HAProxy Stats Port [7000]: " HAPROXY_STATS_PORT
    HAPROXY_STATS_PORT=${HAPROXY_STATS_PORT:-7000}
    
    # Hiển thị và xác nhận
    if confirm_config; then
        break
    else
        echo -e "${YELLOW}Nhập lại cấu hình...${NC}"
    fi
done

# Lưu cấu hình vào file
cat > "$CONFIG_FILE" <<EOF
# PostgreSQL HA Cluster Configuration
# Generated on $(date)

# Database Nodes
PG1_IP="$PG1_IP"
PG2_IP="$PG2_IP"
PG3_IP="$PG3_IP"

# HAProxy Node
HAPROXY_IP="$HAPROXY_IP"

# Cluster Configuration
NAMESPACE="$NAMESPACE"
SCOPE="$SCOPE"
PG_VERSION="$PG_VERSION"
DATA_DIR="$DATA_DIR"
PG_BIN_DIR="/usr/lib/postgresql/${PG_VERSION}/bin"

# Network Ports
PG_PORT="$PG_PORT"
PGBOUNCER_PORT="$PGBOUNCER_PORT"
PATRONI_PORT="$PATRONI_PORT"
ETCD_CLIENT_PORT="$ETCD_CLIENT_PORT"
ETCD_PEER_PORT="$ETCD_PEER_PORT"
HAPROXY_PRIMARY_PORT="$HAPROXY_PRIMARY_PORT"
HAPROXY_STANDBY_PORT="$HAPROXY_STANDBY_PORT"
HAPROXY_STATS_PORT="$HAPROXY_STATS_PORT"

# Directories
PATRONI_CONFIG_DIR="/etc/patroni"
ETCD_CONFIG_DIR="/etc/etcd"
ETCD_DATA_DIR="/var/lib/etcd"
PGSQL_DATA_DIR="/data/pgsql"
ARCHIVE_DIR="/var/lib/postgresql/archived"
EOF

# Set permissions
chmod 644 "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✓ Đã lưu cấu hình vào: $CONFIG_FILE${NC}"
echo ""
echo -e "${YELLOW}Các bước tiếp theo:${NC}"
echo "1. Copy file config này sang tất cả các nodes:"
echo "   scp $CONFIG_FILE root@<node_ip>:$CONFIG_FILE"
echo ""
echo "2. Hoặc chạy script này trên từng node với cùng thông tin"
echo ""
echo "3. Sau đó chạy: ./setup-master.sh để bắt đầu cài đặt"
echo ""
