# Các lệnh quản lý Patroni Cluster

## 1. Kiểm tra trạng thái cluster
```bash
# Xem danh sách các node trong cluster
patronictl -c /etc/patroni/patroni.yml list pg_cluster

# Xem topology của cluster
patronictl -c /etc/patroni/patroni.yml topology pg_cluster

# Kiểm tra chi tiết một node
curl -s http://<PG1_IP>:8008/ | jq
```

## 2. Switchover (chuyển primary có kế hoạch)
```bash
# Switchover sang node cụ thể
patronictl -c /etc/patroni/patroni.yml switchover pg_cluster --master pg1 --candidate pg2

# Switchover tự động chọn candidate
patronictl -c /etc/patroni/patroni.yml switchover pg_cluster --force
```

## 3. Failover (khi primary bị lỗi)
```bash
# Patroni tự động failover khi phát hiện primary down
# Có thể trigger thủ công:
patronictl -c /etc/patroni/patroni.yml failover pg_cluster --force
```

## 4. Quản lý node
```bash
# Reinitialize một node (xóa data và clone lại từ primary)
patronictl -c /etc/patroni/patroni.yml reinit pg_cluster pg2

# Restart một node
patronictl -c /etc/patroni/patroni.yml restart pg_cluster pg2

# Reload cấu hình
patronictl -c /etc/patroni/patroni.yml reload pg_cluster pg2
```

## 5. Pause/Resume cluster
```bash
# Pause cluster (tạm dừng tự động failover)
patronictl -c /etc/patroni/patroni.yml pause pg_cluster

# Resume cluster
patronictl -c /etc/patroni/patroni.yml resume pg_cluster
```

## 6. Cấu hình cluster
```bash
# Xem cấu hình hiện tại
patronictl -c /etc/patroni/patroni.yml show-config pg_cluster

# Edit cấu hình cluster
patronictl -c /etc/patroni/patroni.yml edit-config pg_cluster
```

## 7. Kiểm tra etcd
```bash
# Xem tất cả keys trong etcd
etcdctl --endpoints=http://<PG1_IP>:2379 get --prefix /

# Xem cấu hình cluster trong etcd
etcdctl --endpoints=http://<PG1_IP>:2379 get --prefix /pg_percona/pg_cluster/

# Kiểm tra member list
etcdctl --endpoints=http://<PG1_IP>:2379 member list

# Kiểm tra health
etcdctl endpoint health --endpoints=<PG1_IP>:2379,<PG2_IP>:2379,<PG3_IP>:2379
```

## 8. Kiểm tra PostgreSQL
```bash
# Kết nối trực tiếp đến PostgreSQL
psql -h localhost -p 5432 -U postgres

# Kết nối qua PGBouncer
psql -h localhost -p 6432 -U postgres

# Kết nối qua HAProxy (Primary)
psql -h <HAPROXY_IP> -p 5000 -U postgres

# Kết nối qua HAProxy (Replica)
psql -h <HAPROXY_IP> -p 5001 -U postgres

# Kiểm tra replication status
psql -h localhost -p 5432 -U postgres -c "SELECT * FROM pg_stat_replication;"

# Kiểm tra replication slots
psql -h localhost -p 5432 -U postgres -c "SELECT * FROM pg_replication_slots;"
```

## 9. Logs
```bash
# Xem log Patroni
journalctl -u patroni -f

# Xem log PostgreSQL
tail -f /var/log/postgresql/postgresql-18-main.log

# Xem log etcd
journalctl -u etcd -f

# Xem log PGBouncer
tail -f /var/log/postgresql/pgbouncer.log

# Xem log HAProxy
tail -f /var/log/haproxy.log
```

## 10. Troubleshooting
```bash
# Kiểm tra service status
systemctl status patroni
systemctl status postgresql
systemctl status etcd
systemctl status pgbouncer

# Restart các services
systemctl restart patroni
systemctl restart etcd
systemctl restart pgbouncer

# Kiểm tra port đang lắng nghe
netstat -tlnp | grep -E '5432|6432|8008|2379|2380'
```

## 11. Backup và Restore
```bash
# Backup sử dụng pg_basebackup
pg_basebackup -h localhost -U replicator -D /backup/pg_backup -Fp -Xs -P

# Backup sử dụng pg_dump (logical backup)
pg_dump -h localhost -U postgres -d mydatabase > mydatabase.sql

# Restore từ logical backup
psql -h localhost -U postgres -d mydatabase < mydatabase.sql
```

## 12. Monitoring queries
```sql
-- Kiểm tra xem node là primary hay replica
SELECT pg_is_in_recovery();

-- Xem replication lag
SELECT 
    client_addr,
    state,
    pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) as pending_bytes,
    pg_wal_lsn_diff(sent_lsn, write_lsn) as write_lag_bytes,
    pg_wal_lsn_diff(write_lsn, flush_lsn) as flush_lag_bytes,
    pg_wal_lsn_diff(flush_lsn, replay_lsn) as replay_lag_bytes
FROM pg_stat_replication;

-- Xem kích thước databases
SELECT 
    datname,
    pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- Xem active connections
SELECT 
    datname,
    usename,
    application_name,
    client_addr,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle';
```

## 13. Maintenance mode
```bash
# Đưa node vào maintenance (không failover)
patronictl -c /etc/patroni/patroni.yml edit-config pg_cluster
# Thêm: nofailover: true cho node cần maintenance

# Hoặc tag trực tiếp
curl -s -XPATCH -d '{"tags":{"nofailover": true}}' http://<PG1_IP>:8008/config
```

## 14. Scale down/up
```bash
# Tạm thời remove một replica khỏi cluster
systemctl stop patroni

# Thêm lại vào cluster
systemctl start patroni
# Patroni sẽ tự động rejoin và resync
```
