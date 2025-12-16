#!/bin/bash

# Script: show-config.sh
# Mô tả: Hiển thị cấu hình hiện tại của cluster

CONFIG_FILE="/etc/ha_postgres/config.env"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -f "$CONFIG_FILE" ]; then
    echo "✗ Không tìm thấy file cấu hình: $CONFIG_FILE"
    echo "Vui lòng chạy ./scripts/00-setup-config.sh trước!"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║     PostgreSQL HA Cluster - Configuration Info           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${GREEN}═══ Database Nodes ═══${NC}"
echo "  pg1: ${PG1_IP}"
echo "  pg2: ${PG2_IP}"
echo "  pg3: ${PG3_IP}"
echo ""

echo -e "${GREEN}═══ HAProxy Node ═══${NC}"
echo "  haproxy: ${HAPROXY_IP}"
echo ""

echo -e "${GREEN}═══ Cluster Settings ═══${NC}"
echo "  Namespace: ${NAMESPACE}"
echo "  Scope: ${SCOPE}"
echo "  PostgreSQL Version: ${PG_VERSION}"
echo "  Data Directory: ${DATA_DIR}"
echo "  Binary Directory: ${PG_BIN_DIR}"
echo ""

echo -e "${GREEN}═══ Network Ports ═══${NC}"
echo "  PostgreSQL: ${PG_PORT}"
echo "  PGBouncer: ${PGBOUNCER_PORT}"
echo "  Patroni REST API: ${PATRONI_PORT}"
echo "  etcd Client: ${ETCD_CLIENT_PORT}"
echo "  etcd Peer: ${ETCD_PEER_PORT}"
echo "  HAProxy Primary: ${HAPROXY_PRIMARY_PORT}"
echo "  HAProxy Standby: ${HAPROXY_STANDBY_PORT}"
echo "  HAProxy Stats: ${HAPROXY_STATS_PORT}"
echo ""

echo -e "${GREEN}═══ Important Directories ═══${NC}"
echo "  Patroni Config: ${PATRONI_CONFIG_DIR}"
echo "  etcd Config: ${ETCD_CONFIG_DIR}"
echo "  etcd Data: ${ETCD_DATA_DIR}"
echo "  PostgreSQL Data: ${PGSQL_DATA_DIR}"
echo "  Archive: ${ARCHIVE_DIR}"
echo ""

echo -e "${YELLOW}═══ Connection Examples ═══${NC}"
echo ""
echo "Primary (Read-Write):"
echo "  psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U postgres"
echo ""
echo "Standby (Read-Only):"
echo "  psql -h ${HAPROXY_IP} -p ${HAPROXY_STANDBY_PORT} -U postgres"
echo ""
echo "HAProxy Stats:"
echo "  http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/"
echo ""

echo -e "${YELLOW}═══ Useful Commands ═══${NC}"
echo ""
echo "Check etcd cluster:"
echo "  etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member list"
echo ""
echo "Check Patroni cluster:"
echo "  patronictl -c ${PATRONI_CONFIG_DIR}/patroni.yml list ${SCOPE}"
echo ""
echo "Config file location:"
echo "  ${CONFIG_FILE}"
echo ""
