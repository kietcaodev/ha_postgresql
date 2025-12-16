# Hướng dẫn triển khai HA PostgreSQL trên Debian 12
## Patroni - etcd - HAProxy - PGBouncer

## Tổng quan kiến trúc

Hệ thống PostgreSQL High Availability cluster bao gồm:
- **3 Database Nodes**: PostgreSQL 18 + Patroni + etcd + PGBouncer
- **1 HAProxy Node**: Load balancer và connection router

> **Lưu ý**: Không còn hard-code IP addresses. Tất cả cấu hình được nhập qua interactive script.

## Về Placeholders trong Documentation

Trong các file tài liệu (DEPLOYMENT.md, COMMANDS.md, TROUBLESHOOTING.md), bạn sẽ thấy các placeholder như:
- `<PG1_IP>` - IP của Database Node 1
- `<PG2_IP>` - IP của Database Node 2
- `<PG3_IP>` - IP của Database Node 3
- `<HAPROXY_IP>` - IP của HAProxy Node

**Thay thế các placeholder này bằng IP thực tế mà bạn đã cấu hình trong bước 0.**

Ví dụ: Nếu PG1_IP của bạn là `192.168.1.10`, thay `<PG1_IP>` bằng `192.168.1.10` khi chạy lệnh.

## Các bước triển khai

### Bước 0: Thiết lập cấu hình (QUAN TRỌNG!)

**Chạy trên node đầu tiên hoặc trên máy local, sau đó copy sang các node:**

```bash
chmod +x *.sh
./00-setup-config.sh
```

Script này sẽ:
- Cho phép bạn nhập tất cả IP addresses của các nodes
- Cấu hình các ports (PostgreSQL, etcd, HAProxy, etc.)
- Xác nhận cấu hình trước khi lưu
- Cho phép nhập lại nếu sai
- Lưu vào file `/etc/ha_postgres/config.env`

**Copy config sang tất cả các nodes:**
```bash
scp /etc/ha_postgres/config.env root@<node_ip>:/etc/ha_postgres/config.env
```

Hoặc chạy `./00-setup-config.sh` trên từng node với cùng thông tin.

### Bước 1: Triển khai các nodes

Sau khi đã có config file, chạy trên từng node:

```bash
./setup-master.sh
```

Script `setup-master.sh` sẽ:
- Tự động detect node type dựa vào IP
- Hướng dẫn chi tiết từng bước
- Tự động chạy các scripts cài đặt theo đúng thứ tự

**Thứ tự triển khai:**
1. Chạy trên Database Node 1 (pg1)
2. Add pg2 vào etcd cluster (script sẽ hướng dẫn)
3. Chạy trên Database Node 2 (pg2)
4. Add pg3 vào etcd cluster
5. Chạy trên Database Node 3 (pg3)
6. Chạy trên HAProxy Node

### Bước 2: Kiểm tra cài đặt

Sau khi cài đặt xong tất cả các nodes:

```bash
./99-verify-cluster.sh
```

## Kiểm tra hệ thống

### Xem cấu hình hiện tại:
```bash
cat /etc/ha_postgres/config.env
```

### Kiểm tra etcd cluster:
```bash
# Load config để lấy IPs
source /etc/ha_postgres/config.env

etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member list
etcdctl endpoint status --endpoints=${PG1_IP}:${ETCD_CLIENT_PORT},${PG2_IP}:${ETCD_CLIENT_PORT},${PG3_IP}:${ETCD_CLIENT_PORT} --write-out=table
```

### Kiểm tra Patroni cluster:
```bash
source /etc/ha_postgres/config.env
patronictl -c /etc/patroni/patroni.yml list ${SCOPE}
```

### Kiểm tra HAProxy:
```bash
source /etc/ha_postgres/config.env
# Web UI
echo "http://${HAPROXY_IP}:${HAPROXY_STATS_PORT}/"

# Ports
echo "Primary: ${HAPROXY_IP}:${HAPROXY_PRIMARY_PORT}"
echo "Standby: ${HAPROXY_IP}:${HAPROXY_STANDBY_PORT}"
```

### Kết nối database:
```bash
source /etc/ha_postgres/config.env

# Primary (qua HAProxy)
psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U postgres

# Replica (qua HAProxy)
psql -h ${HAPROXY_IP} -p ${HAPROXY_STANDBY_PORT} -U postgres
```

## Lưu ý quan trọng

1. **Firewall**: Mở các port cần thiết:
   - PostgreSQL: 5432
   - PGBouncer: 6432
   - Patroni REST API: 8008
   - etcd client: 2379
   - etcd peer: 2380
   - HAProxy stats: 7000
   - HAProxy primary: 5000
   - HAProxy standby: 5001

2. **Passwords**: Thay đổi các password mặc định trong scripts trước khi triển khai production

3. **Backup**: Cấu hình pgBackRest để backup dữ liệu định kỳ

4. **Monitoring**: Cân nhắc triển khai Percona Monitoring and Management (PMM) để giám sát
