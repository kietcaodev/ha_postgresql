#!/bin/bash

# Script: 02-install-packages.sh
# Mô tả: Cài đặt PostgreSQL 18, Patroni, etcd trên Debian 12
# Chạy trên: Tất cả 3 node DB (pg1, pg2, pg3)

set -e

echo "=== Cài đặt PostgreSQL 18, Patroni, etcd trên Debian 12 ==="

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Script này cần chạy với quyền root!" 
   exit 1
fi

# Update system
echo ">> Cập nhật hệ thống..."
apt update
apt upgrade -y

# Cài đặt các gói dependencies
echo ">> Cài đặt dependencies..."
apt install -y curl wget gnupg2 lsb-release apt-transport-https ca-certificates \
    python3 python3-pip python3-dev python3-psycopg2 \
    build-essential libssl-dev libffi-dev net-tools

# Thêm PostgreSQL APT repository
echo ">> Thêm PostgreSQL repository..."
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Update sau khi thêm repo
apt update

# Cài đặt PostgreSQL 18
echo ">> Cài đặt PostgreSQL 18..."
apt install -y postgresql-18 postgresql-contrib-18 postgresql-server-dev-18

# Stop PostgreSQL service (sẽ để Patroni quản lý)
systemctl stop postgresql
systemctl disable postgresql

# Cài đặt etcd
echo ">> Cài đặt etcd..."
ETCD_VERSION="3.5.11"
wget https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
tar xzf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
mv etcd-v${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/
rm -rf etcd-v${ETCD_VERSION}-linux-amd64*

# Tạo user và thư mục cho etcd
useradd -r -s /bin/false etcd || true
mkdir -p /var/lib/etcd
chown -R etcd:etcd /var/lib/etcd

# Tạo systemd service cho etcd
cat > /etc/systemd/system/etcd.service <<'EOF'
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
Type=notify
User=etcd
Environment=ETCD_DATA_DIR=/var/lib/etcd
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF

# Tạo thư mục cấu hình etcd
mkdir -p /etc/etcd

# Cài đặt Patroni
echo ">> Cài đặt Patroni..."
pip3 install --upgrade pip setuptools wheel --break-system-packages
pip3 install patroni[etcd3] python-etcd --break-system-packages

# Tạo thư mục cho Patroni
mkdir -p /etc/patroni
mkdir -p /data/pgsql
chown -R postgres:postgres /data/pgsql
chmod 700 /data/pgsql

# Tạo systemd service cho Patroni
cat > /etc/systemd/system/patroni.service <<'EOF'
[Unit]
Description=Patroni PostgreSQL HA
After=syslog.target network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -s HUP $MAINPID
KillMode=process
TimeoutSec=30
Restart=no

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Tạo thư mục cho archive WAL
mkdir -p /var/lib/postgresql/archived
chown -R postgres:postgres /var/lib/postgresql/archived

echo ""
echo "✓ Đã cài đặt thành công:"
echo "  - PostgreSQL 18"
echo "  - etcd v${ETCD_VERSION}"
echo "  - Patroni"
echo ""
echo "Phiên bản PostgreSQL:"
su - postgres -c "/usr/lib/postgresql/18/bin/postgres --version"
echo ""
echo "Phiên bản etcd:"
etcd --version | head -1
echo ""
echo "Phiên bản Patroni:"
patroni --version
echo ""
echo "⚠ Lưu ý: Chưa khởi động các service. Cần cấu hình trước khi start."
