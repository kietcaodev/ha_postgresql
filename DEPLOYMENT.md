# Hướng dẫn Triển khai Chi tiết - PostgreSQL HA Cluster trên Debian 12

## Tổng quan

Tài liệu này hướng dẫn chi tiết cách triển khai cụm PostgreSQL High Availability với:
- **3 Database Nodes**: pg1, pg2, pg3
- **1 HAProxy Node**: Load balancer
- **Công nghệ**: Patroni, etcd, PGBouncer, HAProxy

## Kiến trúc

```
┌─────────────────────────────────────────────────────────┐
│                   HAProxy (<HAPROXY_IP>)              │
│                  Port 5000 (Primary)                    │
│                  Port 5001 (Replicas)                   │
└────────────┬────────────┬────────────┬──────────────────┘
             │            │            │
    ┌────────┴───┐   ┌────┴─────┐   ┌─┴─────────┐
    │   pg1      │   │   pg2    │   │   pg3     │
    │ <PG1_IP>   │   │ <PG2_IP> │   │ <PG3_IP>  │
    │            │   │          │   │           │
    │            │   │          │   │           │
    │ PostgreSQL │   │PostgreSQL│   │PostgreSQL │
    │ Patroni    │   │ Patroni  │   │ Patroni   │
    │ etcd       │   │ etcd     │   │ etcd      │
    │ PGBouncer  │   │PGBouncer │   │PGBouncer  │
    └────────────┘   └──────────┘   └───────────┘
```

## Yêu cầu hệ thống

### Phần cứng (mỗi node):
- CPU: 4 cores trở lên
- RAM: 8 GB trở lên
- Disk: 100 GB SSD (khuyến nghị)
- Network: 1 Gbps

### Phần mềm:
- OS: Debian 12 (Bookworm)
- Root access
- Network connectivity giữa các nodes

## Chuẩn bị trước khi triển khai

### 1. Cập nhật hostname cho từng node

**Trên pg1:**
```bash
hostnamectl set-hostname pg1
```

**Trên pg2:**
```bash
hostnamectl set-hostname pg2
```

**Trên pg3:**
```bash
hostnamectl set-hostname pg3
```

**Trên HAProxy node:**
```bash
hostnamectl set-hostname haproxy
```

### 2. Đồng bộ thời gian (NTP)

Trên tất cả các nodes:
```bash
apt install -y chrony
systemctl enable chrony
systemctl start chrony
```

### 4. Tải về scripts

Trên mỗi node, tải về hoặc sao chép tất cả các scripts vào thư mục `/opt/ha_postgres/`:

```bash
mkdir -p /opt/ha_postgres
cd /opt/ha_postgres

# Upload tất cả các file .sh vào đây
# Hoặc clone từ git repository

# Set quyền thực thi
chmod +x *.sh
```

## Bước 1: Triển khai Database Node 1 (pg1)

### Trên server pg1 (<PG1_IP>):

```bash
cd /opt/ha_postgres

# Chạy master script
./setup-master.sh

# Chọn option 1 (Database Node - pg1)
```

Script sẽ tự động:
1. Cấu hình /etc/hosts
2. Cài đặt PostgreSQL 18, Patroni, etcd
3. Cấu hình và khởi động etcd (node đầu tiên)
4. Cấu hình và khởi động Patroni
5. Cài đặt PGBouncer

### Kiểm tra sau khi cài đặt:

```bash
# Kiểm tra etcd
etcdctl --endpoints=http://<PG1_IP>:2379 member list

# Kiểm tra Patroni
patronictl -c /etc/patroni/patroni.yml list pg_cluster

# Kiểm tra PostgreSQL
psql -h localhost -U postgres -c "SELECT version();"
```

### Thêm pg2 vào etcd cluster:

```bash
etcdctl --endpoints=http://<PG1_IP>:2379 member add pg2 --peer-urls=http://<PG2_IP>:2380
```

Lưu lại output để tham khảo.

## Bước 2: Triển khai Database Node 2 (pg2)

### Trên server pg2 (<PG2_IP>):

```bash
cd /opt/ha_postgres

# Chạy master script
./setup-master.sh

# Chọn option 2 (Database Node - pg2)
```

Script sẽ hỏi xác nhận đã add member vào etcd. Nhập 'y' để tiếp tục.

### Kiểm tra:

```bash
# Kiểm tra etcd cluster
etcdctl --endpoints=http://<PG1_IP>:2379 member list

# Kiểm tra Patroni cluster
patronictl -c /etc/patroni/patroni.yml list pg_cluster
```

Bạn sẽ thấy 2 nodes: 1 Leader (pg1) và 1 Replica (pg2).

### Trên pg1, thêm pg3 vào etcd cluster:

```bash
etcdctl --endpoints=http://<PG1_IP>:2379 member add pg3 --peer-urls=http://<PG3_IP>:2380
```

## Bước 3: Triển khai Database Node 3 (pg3)

### Trên server pg3 (<PG3_IP>):

```bash
cd /opt/ha_postgres

# Chạy master script
./setup-master.sh

# Chọn option 3 (Database Node - pg3)
```

### Kiểm tra cluster hoàn chỉnh:

```bash
# Kiểm tra etcd cluster (3 nodes)
etcdctl endpoint status \
  --endpoints=<PG1_IP>:2379,<PG2_IP>:2379,<PG3_IP>:2379 \
  --write-out=table

# Kiểm tra Patroni cluster (3 nodes)
patronictl -c /etc/patroni/patroni.yml list pg_cluster
```

Output mong đợi:
```
+ Cluster: pg_cluster -------+---------+---------+----+-----------+
| Member | Host            | Role    | State   | TL | Lag in MB |
+--------+-----------------+---------+---------+----+-----------+
| pg1    | <PG1_IP>        | Leader  | running |  1 |           |
| pg2    | <PG2_IP>        | Replica | running |  1 |         0 |
| pg3    | <PG3_IP>        | Replica | running |  1 |         0 |
+--------+-----------------+---------+---------+----+-----------+
```

## Bước 4: Triển khai HAProxy

### Trên server HAProxy (<HAPROXY_IP>):

```bash
cd /opt/ha_postgres

# Chạy master script
./setup-master.sh

# Chọn option 4 (HAProxy Node)
```

### Kiểm tra HAProxy:

1. **Truy cập Stats UI**: http://<HAPROXY_IP>:7000/
   - Bạn sẽ thấy 2 backend: `primary` và `standbys`
   - Kiểm tra status của các server (màu xanh = UP)

2. **Test kết nối Primary**:
```bash
PGPASSWORD=<your_password> psql -h <HAPROXY_IP> -p 5000 -U postgres -c "SELECT inet_server_addr();"
# Sẽ trả về IP của primary node
# Thay <your_password> bằng password bạn đã nhập khi cấu hình Patroni
```

3. **Test kết nối Replica**:
```bash
PGPASSWORD=<your_password> psql -h <HAPROXY_IP> -p 5001 -U postgres -c "SELECT inet_server_addr();"
# Sẽ trả về IP của một replica node (round-robin)
# Thay <your_password> bằng password bạn đã nhập khi cấu hình Patroni
```

## Bước 5: Kiểm tra toàn diện

### Chạy script kiểm tra:

```bash
cd /opt/ha_postgres
./99-verify-cluster.sh
```

Script này sẽ kiểm tra:
- etcd cluster health
- Patroni cluster status
- PostgreSQL services
- PGBouncer connections
- HAProxy endpoints
- Database connectivity

### Test Failover:

```bash
./test-failover.sh
```

Script này sẽ thực hiện switchover (chuyển primary sang node khác) và xác minh.

## Bước 6: Cấu hình bảo mật (Khuyến nghị)

### 1. Thay đổi passwords mặc định

**Trên Primary node:**
```sql
psql -h localhost -U postgres

-- Thay đổi password postgres
ALTER USER postgres WITH PASSWORD 'your_strong_password';

-- Thay đổi password replicator
ALTER USER replicator WITH PASSWORD 'your_replication_password';

-- Thay đổi password các user khác
ALTER USER admin WITH PASSWORD 'your_admin_password';
ALTER USER percona WITH PASSWORD 'your_percona_password';
```

**Cập nhật trong Patroni config** trên tất cả nodes:
```bash
vi /etc/patroni/patroni.yml
# Cập nhật passwords trong sections:
# - postgresql.authentication
# - bootstrap.users

systemctl restart patroni
```

**Cập nhật trong PGBouncer** trên tất cả DB nodes:
```bash
vi /etc/pgbouncer/userlist.txt
# Cập nhật passwords

systemctl restart pgbouncer
```

### 2. Cấu hình SSL/TLS (Tùy chọn)

Để bảo mật kết nối PostgreSQL, tham khảo tài liệu PostgreSQL về SSL configuration.

### 3. Giới hạn truy cập IP

Sửa `pg_hba.conf` nếu cần giới hạn IP được phép kết nối.

## Vận hành hàng ngày

### Kết nối đến database:

**Qua HAProxy (khuyến nghị):**
```bash
# Write operations (Primary)
psql -h <HAPROXY_IP> -p 5000 -U postgres -d mydb

# Read operations (Replicas)
psql -h <HAPROXY_IP> -p 5001 -U postgres -d mydb
```

**Trực tiếp đến node:**
```bash
psql -h <PG1_IP> -p 5432 -U postgres -d mydb
```

### Giám sát cluster:

```bash
# Xem status cluster
patronictl -c /etc/patroni/patroni.yml list pg_cluster

# Xem topology
patronictl -c /etc/patroni/patroni.yml topology pg_cluster

# Xem logs
journalctl -u patroni -f
```

### Switchover (planned):

```bash
# Chuyển primary sang node khác
patronictl -c /etc/patroni/patroni.yml switchover pg_cluster --force
```

## Backup và Recovery

### Backup thủ công:

```bash
# Logical backup
pg_dump -h <HAPROXY_IP> -p 5000 -U postgres -d mydb > mydb_backup.sql

# Physical backup
pg_basebackup -h <PG1_IP> -U replicator -D /backup/pgbackup -Fp -Xs -P
```

### Restore:

```bash
# Restore logical backup
psql -h <HAPROXY_IP> -p 5000 -U postgres -d mydb < mydb_backup.sql
```

## Khắc phục sự cố

Tham khảo file [TROUBLESHOOTING.md](TROUBLESHOOTING.md) để biết chi tiết.

### Các vấn đề thường gặp:

1. **etcd không thể kết nối**: Kiểm tra firewall, restart etcd
2. **Patroni không bầu được leader**: Kiểm tra etcd quorum
3. **Replication lag cao**: Kiểm tra network, disk I/O
4. **HAProxy route sai**: Kiểm tra Patroni REST API endpoints

## Nâng cấp

### PostgreSQL minor version:

```bash
apt update
apt upgrade postgresql-18
systemctl restart patroni
```

### Patroni/etcd:

```bash
pip3 install --upgrade patroni[etcd3]
systemctl restart patroni
```

## Liên hệ hỗ trợ

- Tài liệu gốc: `Nội bộ 2-R&D-HƯỚNG DẪN HA POSTGRE-SQL.docx.txt`
- PostgreSQL Docs: https://www.postgresql.org/docs/
- Patroni Docs: https://patroni.readthedocs.io/

---

**Chúc bạn triển khai thành công!** 🚀
