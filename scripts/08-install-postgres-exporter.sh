#!/bin/bash

# Script: 08-install-postgres-exporter.sh
# Mô tả: Cài đặt postgres_exporter để expose metrics cho Prometheus
# Chạy trên: Từng Database Node (pg1, pg2, pg3)

set -e

CONFIG_FILE="/etc/ha_postgres/config.env"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "✗ Script này cần chạy với quyền root!" 
   exit 1
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "✗ Không tìm thấy file cấu hình: $CONFIG_FILE"
    echo "Vui lòng chạy ./00-setup-config.sh trước!"
    exit 1
fi

source "$CONFIG_FILE"

echo "=== Cài đặt postgres_exporter ==="

# Biến cấu hình
EXPORTER_VERSION="0.15.0"
EXPORTER_PORT="9187"
EXPORTER_USER="postgres_exporter"
EXPORTER_PASSWORD="exporter_password_$(openssl rand -hex 8)"

echo ">> Tạo database user cho monitoring..."
sudo -u postgres psql -c "DROP USER IF EXISTS ${EXPORTER_USER};" 2>/dev/null || true
sudo -u postgres psql <<EOF
CREATE USER ${EXPORTER_USER} WITH PASSWORD '${EXPORTER_PASSWORD}';
ALTER USER ${EXPORTER_USER} SET SEARCH_PATH TO ${EXPORTER_USER},pg_catalog;
GRANT pg_monitor TO ${EXPORTER_USER};
GRANT CONNECT ON DATABASE postgres TO ${EXPORTER_USER};
EOF
echo "✓ Database user created: ${EXPORTER_USER}"

# Download postgres_exporter
echo ">> Download postgres_exporter v${EXPORTER_VERSION}..."
cd /tmp
wget -q https://github.com/prometheus-community/postgres_exporter/releases/download/v${EXPORTER_VERSION}/postgres_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz
tar xzf postgres_exporter-${EXPORTER_VERSION}.linux-amd64.tar.gz
sudo mv postgres_exporter-${EXPORTER_VERSION}.linux-amd64/postgres_exporter /usr/local/bin/
sudo chmod +x /usr/local/bin/postgres_exporter
rm -rf postgres_exporter-${EXPORTER_VERSION}*
echo "✓ Binary installed to /usr/local/bin/postgres_exporter"

# Tạo system user
echo ">> Tạo system user..."
sudo useradd --system --no-create-home --shell /bin/false ${EXPORTER_USER} 2>/dev/null || echo "User already exists"

# Tạo environment file
echo ">> Tạo configuration..."
sudo mkdir -p /etc/postgres_exporter
cat <<EOF | sudo tee /etc/postgres_exporter/postgres_exporter.env
DATA_SOURCE_NAME="postgresql://${EXPORTER_USER}:${EXPORTER_PASSWORD}@localhost:${PG_PORT}/postgres?sslmode=disable"
EOF

sudo chmod 600 /etc/postgres_exporter/postgres_exporter.env
sudo chown ${EXPORTER_USER}:${EXPORTER_USER} /etc/postgres_exporter/postgres_exporter.env

# Lưu password vào file config (để backup)
echo "POSTGRES_EXPORTER_PASSWORD=\"${EXPORTER_PASSWORD}\"" | sudo tee -a ${CONFIG_FILE} > /dev/null
echo "✓ Configuration saved"

# Tạo systemd service
echo ">> Tạo systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/postgres_exporter.service
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=${EXPORTER_USER}
Group=${EXPORTER_USER}
EnvironmentFile=/etc/postgres_exporter/postgres_exporter.env
ExecStart=/usr/local/bin/postgres_exporter \\
  --web.listen-address=:${EXPORTER_PORT} \\
  --web.telemetry-path=/metrics \\
  --log.level=info
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable và start service
echo ">> Khởi động service..."
sudo systemctl daemon-reload
sudo systemctl enable postgres_exporter
sudo systemctl restart postgres_exporter

# Đợi service khởi động
sleep 2

# Kiểm tra status
if systemctl is-active --quiet postgres_exporter; then
    echo "✓ postgres_exporter đang chạy"
else
    echo "✗ postgres_exporter không khởi động được!"
    sudo systemctl status postgres_exporter --no-pager
    exit 1
fi

# Test metrics endpoint
echo ""
echo ">> Kiểm tra metrics endpoint..."
if curl -s http://localhost:${EXPORTER_PORT}/metrics > /dev/null; then
    echo "✓ Metrics endpoint hoạt động: http://localhost:${EXPORTER_PORT}/metrics"
else
    echo "✗ Không thể truy cập metrics endpoint"
    exit 1
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  ✓ HOÀN THÀNH CÀI ĐẶT POSTGRES_EXPORTER"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Thông tin kết nối:"
echo "  Metrics URL: http://$(hostname -I | awk '{print $1}'):${EXPORTER_PORT}/metrics"
echo "  Port: ${EXPORTER_PORT}"
echo ""
echo "Thêm vào Prometheus scrape config của bạn:"
echo ""
cat <<EOF
  - job_name: 'postgresql-ha'
    static_configs:
      - targets: 
        - '${PG1_IP}:${EXPORTER_PORT}'
        - '${PG2_IP}:${EXPORTER_PORT}'
        - '${PG3_IP}:${EXPORTER_PORT}'
        labels:
          cluster: '${SCOPE}'
EOF
echo ""
echo "Kiểm tra metrics:"
echo "  curl http://localhost:${EXPORTER_PORT}/metrics | grep pg_up"
echo ""
