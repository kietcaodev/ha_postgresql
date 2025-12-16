#!/bin/bash

# Script: setup-master.sh
# Mô tả: Master script để triển khai toàn bộ PostgreSQL HA Cluster
# Sử dụng: Chạy trên từng node với parameter tương ứng

set -e

# Màu sắc
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   PostgreSQL High Availability Cluster Setup             ║
║   Patroni + etcd + HAProxy + PGBouncer                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ Script này cần chạy với quyền root!${NC}" 
   exit 1
fi

# Kiểm tra config file
CONFIG_FILE="/etc/ha_postgres/config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Không tìm thấy file cấu hình: $CONFIG_FILE${NC}"
    echo ""
    echo "Vui lòng chạy ./scripts/00-setup-config.sh trước để tạo cấu hình!"
    exit 1
fi

# Load config
source "$CONFIG_FILE"

echo -e "${GREEN}Đã load cấu hình từ: $CONFIG_FILE${NC}"
echo ""

# Menu chọn node type
echo -e "${YELLOW}Chọn loại node cần cài đặt:${NC}"
echo "1) Database Node - pg1 (${PG1_IP})"
echo "2) Database Node - pg2 (${PG2_IP})"
echo "3) Database Node - pg3 (${PG3_IP})"
echo "4) HAProxy Node (${HAPROXY_IP})"
echo "5) Exit"
echo ""
read -p "Nhập lựa chọn (1-5): " choice

case $choice in
    1)
        NODE_TYPE="db"
        NODE_NAME="pg1"
        NODE_IP="$PG1_IP"
        ;;
    2)
        NODE_TYPE="db"
        NODE_NAME="pg2"
        NODE_IP="$PG2_IP"
        ;;
    3)
        NODE_TYPE="db"
        NODE_NAME="pg3"
        NODE_IP="$PG3_IP"
        ;;
    4)
        NODE_TYPE="haproxy"
        NODE_NAME="haproxy"
        NODE_IP="$HAPROXY_IP"
        ;;
    5)
        echo "Thoát."
        exit 0
        ;;
    *)
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Đã chọn: $NODE_NAME ($NODE_IP)${NC}"
echo ""

if [ "$NODE_TYPE" = "db" ]; then
    echo "=== BẮT ĐẦU CÀI ĐẶT DATABASE NODE: $NODE_NAME ==="
    echo ""
    
    # Bước 1: Setup hosts
    echo -e "${BLUE}[1/5] Cấu hình /etc/hosts...${NC}"
    ./scripts/01-setup-hosts.sh
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    # Bước 2: Install packages
    echo -e "${BLUE}[2/5] Cài đặt packages (PostgreSQL, Patroni, etcd)...${NC}"
    ./scripts/02-install-packages.sh
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    # Bước 3: Cấu hình etcd
    echo -e "${BLUE}[3/5] Cấu hình etcd...${NC}"
    if [ "$NODE_NAME" = "pg1" ]; then
        ./scripts/03-config-etcd-pg1.sh
    elif [ "$NODE_NAME" = "pg2" ]; then
        echo -e "${YELLOW}⚠ Trước khi tiếp tục, cần thực hiện trên pg1:${NC}"
        echo "   etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg2 --peer-urls=http://${PG2_IP}:${ETCD_PEER_PORT}"
        echo ""
        read -p "Đã thực hiện chưa? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Vui lòng thực hiện lệnh trên pg1 trước!${NC}"
            exit 1
        fi
        ./scripts/03-config-etcd-pg2.sh
    else
        echo -e "${YELLOW}⚠ Trước khi tiếp tục, cần thực hiện trên pg1:${NC}"
        echo "   etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg3 --peer-urls=http://${PG3_IP}:${ETCD_PEER_PORT}"
        echo ""
        read -p "Đã thực hiện chưa? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}Vui lòng thực hiện lệnh trên pg1 trước!${NC}"
            exit 1
        fi
        ./scripts/03-config-etcd-pg3.sh
    fi
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    # Bước 4: Cấu hình Patroni
    echo -e "${BLUE}[4/5] Cấu hình Patroni...${NC}"
    ./scripts/04-config-patroni.sh
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    # Bước 5: Cài đặt PGBouncer
    echo -e "${BLUE}[5/5] Cài đặt PGBouncer...${NC}"
    ./scripts/05-install-pgbouncer.sh
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ✓ HOÀN THÀNH CÀI ĐẶT DATABASE NODE: $NODE_NAME"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "Các bước tiếp theo:"
    if [ "$NODE_NAME" = "pg1" ]; then
        echo "1. Thêm pg2 vào etcd cluster:"
        echo "   etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg2 --peer-urls=http://${PG2_IP}:${ETCD_PEER_PORT}"
        echo ""
        echo "2. Chạy script này trên pg2"
        echo ""
        echo "3. Sau khi pg2 xong, thêm pg3:"
        echo "   etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg3 --peer-urls=http://${PG3_IP}:${ETCD_PEER_PORT}"
        echo ""
        echo "4. Chạy script này trên pg3"
        echo ""
        echo "5. Cài đặt HAProxy trên node ${HAPROXY_IP}"
    else
        echo "1. Kiểm tra cluster:"
        echo "   patronictl -c /etc/patroni/patroni.yml list ${SCOPE}"
        echo ""
        echo "2. Nếu đây là node cuối, cài đặt HAProxy"
    fi
    
elif [ "$NODE_TYPE" = "haproxy" ]; then
    echo "=== BẮT ĐẦU CÀI ĐẶT HAPROXY NODE ==="
    echo ""
    
    # Setup hosts
    echo -e "${BLUE}[1/2] Cấu hình /etc/hosts...${NC}"
    ./scripts/01-setup-hosts.sh
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    # Install HAProxy
    echo -e "${BLUE}[2/2] Cài đặt HAProxy...${NC}"
    ./scripts/06-install-haproxy.sh
    echo -e "${GREEN}✓ Hoàn thành${NC}"
    echo ""
    
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ✓ HOÀN THÀNH CÀI ĐẶT HAPROXY NODE"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "HAProxy Stats UI: http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/"
    echo "Primary endpoint: ${HAPROXY_IP}:${HAPROXY_PRIMARY_PORT}"
    echo "Replica endpoint: ${HAPROXY_IP}:${HAPROXY_STANDBY_PORT}"
fi

echo ""
echo -e "${YELLOW}Để kiểm tra toàn bộ hệ thống, chạy:${NC}"
echo "  ./99-verify-cluster.sh"
echo ""
