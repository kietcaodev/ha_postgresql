# Troubleshooting Guide - PostgreSQL HA Cluster

## 1. Patroni không khởi động được

### Triệu chứng:
```bash
systemctl status patroni
# Active: failed
```

### Nguyên nhân và giải pháp:

**A. etcd không hoạt động:**
```bash
# Kiểm tra etcd
systemctl status etcd
etcdctl endpoint health

# Nếu etcd down, restart:
systemctl restart etcd
systemctl restart patroni
```

**B. Cấu hình Patroni sai:**
```bash
# Kiểm tra syntax config
cat /etc/patroni/patroni.yml

# Xem log chi tiết
journalctl -u patroni -n 100 --no-pager

# Thường gặp: path PostgreSQL binary sai
# Kiểm tra:
ls -la /usr/lib/postgresql/18/bin/postgres
```

**C. Data directory đã tồn tại:**
```bash
# Xóa data directory cũ nếu muốn init lại
rm -rf /var/lib/postgresql/18/main/*
systemctl restart patroni
```

---

## 2. Cluster không bầu được Leader

### Triệu chứng:
```bash
patronictl -c /etc/patroni/patroni.yml list pg_cluster
# Không có node nào ở trạng thái Leader
```

### Giải pháp:

**A. Kiểm tra etcd cluster:**
```bash
# Phải có quorum (2/3 nodes up)
etcdctl endpoint status --endpoints=<PG1_IP>:2379,<PG2_IP>:2379,<PG3_IP>:2379 --write-out=table

# Nếu < 2 nodes up, khởi động lại các node etcd
systemctl start etcd
```

**B. Initialize cluster thủ công:**
```bash
# Trên node muốn làm leader
patronictl -c /etc/patroni/patroni.yml reinit pg_cluster <node_name> --force
```

---

## 3. Replication lag cao

### Triệu chứng:
```sql
SELECT client_addr, state, 
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) as lag_bytes
FROM pg_stat_replication;
-- lag_bytes > 100MB
```

### Giải pháp:

**A. Kiểm tra network:**
```bash
# Test bandwidth giữa các node
iperf3 -s  # Trên node 1
iperf3 -c <PG1_IP>  # Trên node 2
```

**B. Tăng max_wal_senders:**
```sql
ALTER SYSTEM SET max_wal_senders = 10;
SELECT pg_reload_conf();
```

**C. Kiểm tra disk I/O:**
```bash
iostat -x 2 10
# Nếu %util gần 100%, disk bị bottleneck
```

---

## 4. Switchover/Failover thất bại

### Triệu chứng:
```bash
patronictl -c /etc/patroni/patroni.yml switchover pg_cluster
# Error: Switchover failed
```

### Giải pháp:

**A. Kiểm tra replication state:**
```bash
# Replica phải ở trạng thái "running"
patronictl -c /etc/patroni/patroni.yml list pg_cluster

# Kiểm tra replication trên primary
psql -h localhost -U postgres -c "SELECT * FROM pg_stat_replication;"
```

**B. Check DCS (etcd) connectivity:**
```bash
curl http://<PG1_IP>:2379/health
# Should return: {"health":"true"}
```

**C. Pause/Resume cluster:**
```bash
# Đôi khi cluster bị pause
patronictl -c /etc/patroni/patroni.yml resume pg_cluster
```

---

## 5. Split-brain scenario

### Triệu chứng:
Có 2 node cùng claim là Primary

### Giải pháp:

**A. Kiểm tra etcd cluster:**
```bash
etcdctl endpoint status --endpoints=<PG1_IP>:2379,<PG2_IP>:2379,<PG3_IP>:2379 --write-out=table
# Phải có leader trong etcd
```

**B. Reinit node sai:**
```bash
# Xác định node nào là primary thật (có nhiều data hơn)
# Reinit node sai:
patronictl -c /etc/patroni/patroni.yml reinit pg_cluster <wrong_node> --force
```

---

## 6. HAProxy không route đúng

### Triệu chứng:
```bash
psql -h <HAPROXY_IP> -p 5000 -U postgres
# Connection refused hoặc kết nối đến wrong node
```

### Giải pháp:

**A. Kiểm tra HAProxy stats:**
```bash
# Truy cập: http://<HAPROXY_IP>:7000/
# Xem node nào UP/DOWN
```

**B. Test Patroni REST API:**
```bash
# Primary endpoint
curl http://<PG1_IP>:8008/primary
# HTTP 200 nếu node là primary

# Replica endpoint
curl http://<PG1_IP>:8008/replica
# HTTP 200 nếu node là replica
```

**C. Restart HAProxy:**
```bash
systemctl restart haproxy
```

---

## 7. PGBouncer connection pool exhausted

### Triệu chứng:
```
FATAL: no more connections allowed
```

### Giải pháp:

**A. Tăng connection limits:**
```bash
vi /etc/pgbouncer/pgbouncer.ini
# Tăng:
# default_pool_size = 50
# max_client_conn = 2000

systemctl restart pgbouncer
```

**B. Kiểm tra connections:**
```bash
psql -h localhost -p 6432 -U postgres -c "SHOW POOLS;"
psql -h localhost -p 6432 -U postgres -c "SHOW CLIENTS;"
```

---

## 8. Node không thể rejoin cluster

### Triệu chứng:
```bash
systemctl status patroni
# Node stuck trong trạng thái "starting"
```

### Giải pháp:

**A. Reinitialize node:**
```bash
systemctl stop patroni
rm -rf /var/lib/postgresql/18/main/*
systemctl start patroni
# Patroni sẽ tự động clone từ primary
```

**B. Kiểm tra pg_rewind:**
```bash
# Nếu timeline mismatch, cần pg_rewind
journalctl -u patroni -n 100 | grep rewind

# Đảm bảo wal_log_hints = on
psql -h localhost -U postgres -c "SHOW wal_log_hints;"
```

---

## 9. etcd data corruption

### Triệu chứng:
```bash
etcdctl member list
# Error: etcdserver: mvcc: database space exceeded
```

### Giải pháp:

**A. Defrag etcd:**
```bash
etcdctl defrag --endpoints=<PG1_IP>:2379
etcdctl defrag --endpoints=<PG2_IP>:2379
etcdctl defrag --endpoints=<PG3_IP>:2379
```

**B. Compact old revisions:**
```bash
# Lấy current revision
REV=$(etcdctl --endpoints=<PG1_IP>:2379 endpoint status --write-out="json" | jq '.[0].Status.header.revision')

# Compact
etcdctl compact $REV
etcdctl defrag
```

**C. Tăng quota (nếu cần):**
```bash
# Trong /etc/etcd/etcd.conf thêm:
ETCD_QUOTA_BACKEND_BYTES=8589934592  # 8GB
systemctl restart etcd
```

---

## 10. Performance issues

### A. Kiểm tra slow queries:
```sql
-- Enable pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Top 10 slow queries
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### B. Kiểm tra indexes:
```sql
-- Missing indexes
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    seq_tup_read / seq_scan as avg_seq_tup
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_scan DESC;
```

### C. Vacuum và Analyze:
```sql
-- Xem tables cần vacuum
SELECT 
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    round(n_dead_tup::numeric / NULLIF(n_live_tup, 0), 3) as dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;

-- Chạy vacuum
VACUUM ANALYZE;
```

---

## Các lệnh hữu ích khi troubleshoot

```bash
# Xem tất cả connections
netstat -tlnp | grep -E '5432|6432|8008|2379|2380'

# Xem logs realtime
tail -f /var/log/postgresql/postgresql-18-main.log
journalctl -u patroni -f
journalctl -u etcd -f

# Kill hung processes
ps aux | grep postgres
kill -9 <PID>

# Restart toàn bộ stack
systemctl restart etcd
sleep 5
systemctl restart patroni
sleep 5
systemctl restart pgbouncer

# Emergency: Disable auto-failover
patronictl -c /etc/patroni/patroni.yml pause pg_cluster
```

---

## Contacts và Resources

- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Patroni Documentation: https://patroni.readthedocs.io/
- etcd Documentation: https://etcd.io/docs/
