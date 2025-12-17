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

# Directories
LOG_DIR="/var/log/ha_postgres"
CHECKPOINT_DIR="/var/lib/ha_postgres/checkpoints"
LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d_%H%M%S).log"
CHECKPOINT_FILE="${CHECKPOINT_DIR}/setup.checkpoint"

# Tạo directories
mkdir -p "$LOG_DIR"
mkdir -p "$CHECKPOINT_DIR"

# Logging functions
log_info() {
    local msg="$1"
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${msg}${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: ${msg}${NC}" | tee -a "$LOG_FILE"
}

log_step() {
    local msg="$1"
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] STEP: ${msg}${NC}" | tee -a "$LOG_FILE"
}

# Checkpoint functions
save_checkpoint() {
    local step="$1"
    echo "$step" >> "$CHECKPOINT_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$step|completed" >> "${CHECKPOINT_FILE}.log"
    log_info "Checkpoint saved: $step"
}

is_step_completed() {
    local step="$1"
    if [ -f "$CHECKPOINT_FILE" ]; then
        grep -q "^${step}$" "$CHECKPOINT_FILE" 2>/dev/null
        return $?
    fi
    return 1
}

reset_checkpoints() {
    rm -f "$CHECKPOINT_FILE" "${CHECKPOINT_FILE}.log"
    log_warning "Checkpoints reset"
}

show_checkpoints() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        echo -e "${BLUE}Các bước đã hoàn thành:${NC}"
        cat "$CHECKPOINT_FILE" | nl
    else
        echo "Chưa có bước nào hoàn thành."
    fi
}

# Banner
log_info "Starting PostgreSQL HA Cluster Setup"
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
log_info "Loaded configuration from: $CONFIG_FILE"

echo -e "${GREEN}Đã load cấu hình từ: $CONFIG_FILE${NC}"
echo -e "${GREEN}Log file: $LOG_FILE${NC}"
echo ""

# Kiểm tra checkpoints
if [ -f "$CHECKPOINT_FILE" ]; then
    echo -e "${YELLOW}⚠ Phát hiện checkpoint từ lần cài đặt trước${NC}"
    show_checkpoints
    echo ""
    echo "Tùy chọn:"
    echo "1) Tiếp tục từ checkpoint (skip các bước đã hoàn thành)"
    echo "2) Reset và cài đặt lại từ đầu"
    echo "3) Xem log và thoát"
    read -p "Chọn (1-3): " checkpoint_choice
    
    case $checkpoint_choice in
        1)
            log_info "Resuming from checkpoint"
            echo "Sẽ skip các bước đã hoàn thành"
            ;;
        2)
            reset_checkpoints
            echo "Đã reset checkpoint, sẽ cài đặt từ đầu"
            ;;
        3)
            if [ -f "${CHECKPOINT_FILE}.log" ]; then
                cat "${CHECKPOINT_FILE}.log"
            fi
            exit 0
            ;;
    esac
    echo ""
fi

# Menu chọn node type
echo -e "${YELLOW}Chọn loại node cần cài đặt:${NC}"
echo "1) Database Node - pg1 (${PG1_IP})"
echo "2) Database Node - pg2 (${PG2_IP})"
echo "3) Database Node - pg3 (${PG3_IP})"
echo "4) HAProxy Node (${HAPROXY_IP})"
echo "5) Install postgres_exporter (trên node hiện tại)"
echo "6) Exit"
echo ""
read -p "Nhập lựa chọn (1-6): " choice

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
        NODE_TYPE="exporter"
        NODE_NAME="postgres_exporter"
        ;;
    6)
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
log_info "Selected node: $NODE_NAME ($NODE_IP), Type: $NODE_TYPE"
echo ""

if [ "$NODE_TYPE" = "db" ]; then
    echo "=== BẮT ĐẦU CÀI ĐẶT DATABASE NODE: $NODE_NAME ==="
    log_info "Starting database node installation: $NODE_NAME"
    echo ""
    
    # Bước 1: Setup hosts
    STEP="db_${NODE_NAME}_hosts"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Setup hosts - SKIPPING"
        echo -e "${YELLOW}⊘ [1/6] Cấu hình /etc/hosts... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[1/6] Configuring /etc/hosts for $NODE_NAME"
        echo -e "${BLUE}[1/6] Cấu hình /etc/hosts...${NC}"
        ./scripts/01-setup-hosts.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    # Bước 2: Install packages
    STEP="db_${NODE_NAME}_packages"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Install packages - SKIPPING"
        echo -e "${YELLOW}⊘ [2/6] Cài đặt packages... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[2/6] Installing packages (PostgreSQL, Patroni, etcd)"
        echo -e "${BLUE}[2/6] Cài đặt packages (PostgreSQL, Patroni, etcd)...${NC}"
        ./scripts/02-install-packages.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    # Bước 3: Cấu hình etcd
    STEP="db_${NODE_NAME}_etcd"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Configure etcd - SKIPPING"
        echo -e "${YELLOW}⊘ [3/6] Cấu hình etcd... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[3/6] Configuring etcd for $NODE_NAME"
        echo -e "${BLUE}[3/6] Cấu hình etcd...${NC}"
        if [ "$NODE_NAME" = "pg1" ]; then
            ./scripts/03-config-etcd-pg1.sh 2>&1 | tee -a "$LOG_FILE"
        elif [ "$NODE_NAME" = "pg2" ]; then
            echo -e "${YELLOW}⚠ Trước khi tiếp tục, cần thực hiện trên pg1:${NC}"
            echo "   etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg2 --peer-urls=http://${PG2_IP}:${ETCD_PEER_PORT}"
            log_warning "Waiting for manual etcd member add on pg1"
            echo ""
            read -p "Đã thực hiện chưa? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "User did not complete etcd member add on pg1"
                echo -e "${RED}Vui lòng thực hiện lệnh trên pg1 trước!${NC}"
                exit 1
            fi
            ./scripts/03-config-etcd-pg2.sh 2>&1 | tee -a "$LOG_FILE"
        else
            echo -e "${YELLOW}⚠ Trước khi tiếp tục, cần thực hiện trên pg1:${NC}"
            echo "   etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg3 --peer-urls=http://${PG3_IP}:${ETCD_PEER_PORT}"
            log_warning "Waiting for manual etcd member add on pg1"
            echo ""
            read -p "Đã thực hiện chưa? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "User did not complete etcd member add on pg1"
                echo -e "${RED}Vui lòng thực hiện lệnh trên pg1 trước!${NC}"
                exit 1
            fi
            ./scripts/03-config-etcd-pg3.sh 2>&1 | tee -a "$LOG_FILE"
        fi
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    # Bước 4: Cấu hình Patroni
    STEP="db_${NODE_NAME}_patroni"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Configure Patroni - SKIPPING"
        echo -e "${YELLOW}⊘ [4/6] Cấu hình Patroni... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[4/6] Configuring Patroni"
        echo -e "${BLUE}[4/6] Cấu hình Patroni...${NC}"
        ./scripts/04-config-patroni.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    # Bước 5: Cài đặt PGBouncer
    STEP="db_${NODE_NAME}_pgbouncer"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Install PGBouncer - SKIPPING"
        echo -e "${YELLOW}⊘ [5/6] Cài đặt PGBouncer... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[5/6] Installing PGBouncer"
        echo -e "${BLUE}[5/6] Cài đặt PGBouncer...${NC}"
        ./scripts/05-install-pgbouncer.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    # Bước 6: Cài đặt postgres_exporter
    STEP="db_${NODE_NAME}_exporter"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Install postgres_exporter - SKIPPING"
        echo -e "${YELLOW}⊘ [6/6] Cài đặt postgres_exporter... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[6/6] Installing postgres_exporter"
        echo -e "${BLUE}[6/6] Cài đặt postgres_exporter...${NC}"
        ./scripts/08-install-postgres-exporter.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    log_info "Database node installation completed: $NODE_NAME"
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ✓ HOÀN THÀNH CÀI ĐẶT DATABASE NODE: $NODE_NAME"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "Log file: $LOG_FILE"
    echo ""
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
    log_info "Starting HAProxy node installation"
    echo ""
    
    # Setup hosts
    STEP="haproxy_hosts"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Setup hosts - SKIPPING"
        echo -e "${YELLOW}⊘ [1/2] Cấu hình /etc/hosts... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[1/2] Configuring /etc/hosts for HAProxy"
        echo -e "${BLUE}[1/2] Cấu hình /etc/hosts...${NC}"
        ./scripts/01-setup-hosts.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    # Install HAProxy
    STEP="haproxy_install"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Install HAProxy - SKIPPING"
        echo -e "${YELLOW}⊘ [2/2] Cài đặt HAProxy... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "[2/2] Installing HAProxy"
        echo -e "${BLUE}[2/2] Cài đặt HAProxy...${NC}"
        ./scripts/06-install-haproxy.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
        echo -e "${GREEN}✓ Hoàn thành${NC}"
    fi
    echo ""
    
    log_info "HAProxy node installation completed"
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  ✓ HOÀN THÀNH CÀI ĐẶT HAPROXY NODE"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo "Log file: $LOG_FILE"
    echo ""
    echo "HAProxy Stats UI: http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/"
    echo "Primary endpoint: ${HAPROXY_IP}:${HAPROXY_PRIMARY_PORT}"
    echo "Replica endpoint: ${HAPROXY_IP}:${HAPROXY_STANDBY_PORT}"

elif [ "$NODE_TYPE" = "exporter" ]; then
    echo "=== CÀI ĐẶT POSTGRES_EXPORTER ==="
    log_info "Installing postgres_exporter on current node"
    echo ""
    
    STEP="exporter_install"
    if is_step_completed "$STEP"; then
        log_warning "Step already completed: Install postgres_exporter - SKIPPING"
        echo -e "${YELLOW}⊘ postgres_exporter... (đã hoàn thành, bỏ qua)${NC}"
    else
        log_step "Installing postgres_exporter"
        ./scripts/08-install-postgres-exporter.sh 2>&1 | tee -a "$LOG_FILE"
        save_checkpoint "$STEP"
    fi
    
    log_info "postgres_exporter installation completed"
    echo ""
    echo "Log file: $LOG_FILE"
fi

echo ""
echo -e "${YELLOW}Để kiểm tra toàn bộ hệ thống, chạy:${NC}"
echo "  ./99-verify-cluster.sh"
echo ""
