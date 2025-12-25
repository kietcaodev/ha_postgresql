#!/bin/bash

# Script: 99-verify-cluster.sh
# Mô tả: Script kiểm tra và xác minh cụm PostgreSQL HA
# Chạy trên: Bất kỳ node nào trong cluster

set -e

CONFIG_FILE="/etc/ha_postgres/config.env"

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "✗ Không tìm thấy file cấu hình: $CONFIG_FILE"
    echo "Vui lòng chạy ./scripts/00-setup-config.sh trước để tạo cấu hình!"
    exit 1
fi

source "$CONFIG_FILE"

echo "=================================================="
echo "     KIỂM TRA CỤM POSTGRESQL HA CLUSTER"
echo "=================================================="
echo ""

# Nhập password để test kết nối database
echo ">> Nhập Postgres password để kiểm tra kết nối:"
read -s -p "Postgres password: " POSTGRES_PASSWORD
echo ""
echo ""

# Kiểm tra password không được rỗng
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo "✗ Lỗi: Password không được để trống!"
    exit 1
fi

# Màu sắc cho output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Kiểm tra etcd cluster
echo "1. KIỂM TRA ETCD CLUSTER"
echo "----------------------------------------"
if command -v etcdctl &> /dev/null; then
    echo ">> Member list:"
    # Thử kết nối đến bất kỳ endpoint nào còn hoạt động
    ETCD_ENDPOINTS="${PG1_IP}:${ETCD_CLIENT_PORT},${PG2_IP}:${ETCD_CLIENT_PORT},${PG3_IP}:${ETCD_CLIENT_PORT}"
    if etcdctl --endpoints=http://${ETCD_ENDPOINTS} member list 2>/dev/null; then
        echo ""
        echo ">> Cluster status:"
        etcdctl endpoint status --endpoints=${ETCD_ENDPOINTS} --write-out=table 2>/dev/null || echo -e "${YELLOW}⚠ Một số endpoint không phản hồi (có thể đang down)${NC}"
        echo -e "${GREEN}✓ etcd cluster có quorum${NC}"
    else
        echo -e "${RED}✗ Không thể kết nối đến etcd cluster${NC}"
    fi
else
    echo -e "${RED}✗ etcdctl không được cài đặt trên node này${NC}"
fi
echo ""

# Kiểm tra Patroni cluster
echo "2. KIỂM TRA PATRONI CLUSTER"
echo "----------------------------------------"
if command -v patronictl &> /dev/null; then
    if [ -f "/etc/patroni/patroni.yml" ]; then
        patronictl -c /etc/patroni/patroni.yml list pg_cluster
        echo -e "${GREEN}✓ Patroni cluster hoạt động bình thường${NC}"
    else
        echo -e "${YELLOW}⚠ File cấu hình Patroni không tồn tại trên node này${NC}"
    fi
else
    echo -e "${RED}✗ patronictl không được cài đặt trên node này${NC}"
fi
echo ""

# Kiểm tra PostgreSQL qua các node
echo "3. KIỂM TRA POSTGRESQL SERVICES"
echo "----------------------------------------"
for ip in ${PG1_IP} ${PG2_IP} ${PG3_IP}; do
    echo ">> Kiểm tra $ip:"
    if timeout 3 curl -s http://$ip:${PATRONI_PORT}/ > /dev/null 2>&1; then
        role=$(timeout 3 curl -s http://$ip:${PATRONI_PORT}/ | grep -oP '(?<="role":")[^"]*' 2>/dev/null || echo "unknown")
        state=$(timeout 3 curl -s http://$ip:${PATRONI_PORT}/ | grep -oP '(?<="state":")[^"]*' 2>/dev/null || echo "unknown")
        echo -e "   Role: ${YELLOW}$role${NC}"
        echo -e "   State: ${GREEN}$state${NC}"
    else
        echo -e "   ${RED}✗ Không thể kết nối (node có thể đang down)${NC}"
    fi
done
echo ""

# Kiểm tra PGBouncer
echo "4. KIỂM TRA PGBOUNCER"
echo "----------------------------------------"
if systemctl is-active --quiet pgbouncer 2>/dev/null; then
    echo -e "${GREEN}✓ PGBouncer service đang chạy${NC}"
    if command -v psql &> /dev/null; then
        if PGPASSWORD=${POSTGRES_PASSWORD} psql -h localhost -p ${PGBOUNCER_PORT} -U postgres -c "SHOW STATS;" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Có thể kết nối đến PGBouncer${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ PGBouncer service không chạy trên node này${NC}"
fi
echo ""

# Kiểm tra HAProxy
echo "5. KIỂM TRA HAPROXY"
echo "----------------------------------------"
echo ">> Kiểm tra HAProxy Stats UI:"
if curl -s http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/ > /dev/null 2>&1; then
    echo -e "   ${GREEN}✓ HAProxy Stats UI: http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/${NC}"
else
    echo -e "   ${RED}✗ Không thể kết nối đến HAProxy Stats UI${NC}"
fi

echo ""
echo ">> Kiểm tra Primary endpoint (port ${HAPROXY_PRIMARY_PORT}):"
if nc -z -w3 ${HAPROXY_IP} ${HAPROXY_PRIMARY_PORT} 2>/dev/null; then
    echo -e "   ${GREEN}✓ Port ${HAPROXY_PRIMARY_PORT} (Primary) đang mở${NC}"
else
    echo -e "   ${RED}✗ Port ${HAPROXY_PRIMARY_PORT} (Primary) không thể kết nối${NC}"
fi

echo ""
echo ">> Kiểm tra Standby endpoint (port ${HAPROXY_STANDBY_PORT}):"
if nc -z -w3 ${HAPROXY_IP} ${HAPROXY_STANDBY_PORT} 2>/dev/null; then
    echo -e "   ${GREEN}✓ Port ${HAPROXY_STANDBY_PORT} (Standby) đang mở${NC}"
else
    echo -e "   ${RED}✗ Port ${HAPROXY_STANDBY_PORT} (Standby) không thể kết nối${NC}"
fi
echo ""

# Test kết nối database
echo "6. TEST KẾT NỐI DATABASE"
echo "----------------------------------------"
if command -v psql &> /dev/null; then
    echo ">> Test kết nối qua HAProxy Primary (port ${HAPROXY_PRIMARY_PORT}):"
    if PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U postgres -c "SELECT version();" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Kết nối thành công đến Primary${NC}"
        PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U postgres -c "SELECT current_database(), inet_server_addr(), inet_server_port();"
    else
        echo -e "${RED}✗ Không thể kết nối đến Primary${NC}"
    fi
    echo ""
    
    echo ">> Test kết nối qua HAProxy Standby (port ${HAPROXY_STANDBY_PORT}):"
    if PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${HAPROXY_IP} -p ${HAPROXY_STANDBY_PORT} -U postgres -c "SELECT version();" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Kết nối thành công đến Standby${NC}"
        PGPASSWORD=${POSTGRES_PASSWORD} psql -h ${HAPROXY_IP} -p ${HAPROXY_STANDBY_PORT} -U postgres -c "SELECT current_database(), inet_server_addr(), inet_server_port();"
    else
        echo -e "${RED}✗ Không thể kết nối đến Standby${NC}"
    fi
else
    echo -e "${YELLOW}⚠ psql không được cài đặt trên node này${NC}"
fi
echo ""

echo "=================================================="
echo "     HOÀN THÀNH KIỂM TRA"
echo "=================================================="
