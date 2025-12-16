# Quick Start Guide - PostgreSQL HA Cluster

## 🚀 Triển khai nhanh trong 6 bước

### Bước 1: Setup Configuration (Chỉ làm 1 lần)

**Trên máy đầu tiên hoặc local workstation:**

```bash
cd /opt/ha_postgres
chmod +x *.sh scripts/*.sh

# Chạy script cấu hình
./scripts/00-setup-config.sh
```

**Nhập thông tin khi được hỏi:**
- IP của 3 database nodes (pg1, pg2, pg3)
- IP của HAProxy node
- Các ports (hoặc giữ mặc định)
- Namespace và scope name

**Xác nhận cấu hình:**
- Script sẽ hiển thị tất cả thông tin
- Nhập `y` nếu đúng, `n` để nhập lại

**Config sẽ được lưu tại:** `/etc/ha_postgres/config.env`

---

### Bước 2: Copy Config sang tất cả nodes

```bash
# Copy sang pg1
scp /etc/ha_postgres/config.env root@<pg1_ip>:/etc/ha_postgres/

# Copy sang pg2
scp /etc/ha_postgres/config.env root@<pg2_ip>:/etc/ha_postgres/

# Copy sang pg3
scp /etc/ha_postgres/config.env root@<pg3_ip>:/etc/ha_postgres/

# Copy sang haproxy
scp /etc/ha_postgres/config.env root@<haproxy_ip>:/etc/ha_postgres/
```

**Hoặc:** Chạy `./scripts/00-setup-config.sh` trên mỗi node với cùng thông tin

---

### Bước 3: Deploy Database Node 1 (pg1)

**SSH vào pg1:**
```bash
ssh root@<pg1_ip>
cd /opt/ha_postgres

# Copy scripts sang nếu chưa có
# ...

# Chạy setup
./setup-master.sh
# Chọn: 1) Database Node - pg1
```

**Script sẽ tự động:**
- Setup /etc/hosts
- Install PostgreSQL 18, Patroni, etcd
- Configure etcd (first node)
- Configure Patroni
- Install PGBouncer

**Sau khi xong, thực hiện add pg2:**
```bash
source /etc/ha_postgres/config.env
etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg2 \
  --peer-urls=http://${PG2_IP}:${ETCD_PEER_PORT}
```

---

### Bước 4: Deploy Database Node 2 (pg2)

**SSH vào pg2:**
```bash
ssh root@<pg2_ip>
cd /opt/ha_postgres

./setup-master.sh
# Chọn: 2) Database Node - pg2
# Confirm đã add member: y
```

**Sau khi xong, thực hiện add pg3 từ pg1:**
```bash
# Trên pg1
source /etc/ha_postgres/config.env
etcdctl --endpoints=http://${PG1_IP}:${ETCD_CLIENT_PORT} member add pg3 \
  --peer-urls=http://${PG3_IP}:${ETCD_PEER_PORT}
```

---

### Bước 5: Deploy Database Node 3 (pg3)

**SSH vào pg3:**
```bash
ssh root@<pg3_ip>
cd /opt/ha_postgres

./setup-master.sh
# Chọn: 3) Database Node - pg3
# Confirm đã add member: y
```

**Kiểm tra cluster:**
```bash
source /etc/ha_postgres/config.env
patronictl -c /etc/patroni/patroni.yml list ${SCOPE}
```

Bạn sẽ thấy:
- 1 Leader (primary)
- 2 Replicas (standby)

---

### Bước 6: Deploy HAProxy Node

**SSH vào haproxy node:**
```bash
ssh root@<haproxy_ip>
cd /opt/ha_postgres

./setup-master.sh
# Chọn: 4) HAProxy Node
```

---

## ✅ Kiểm tra hoàn tất

**Chạy script verification:**
```bash
./99-verify-cluster.sh
```

**Hoặc kiểm tra thủ công:**

```bash
# 1. Xem config
./show-config.sh

# 2. Kiểm tra etcd
source /etc/ha_postgres/config.env
etcdctl endpoint status \
  --endpoints=${PG1_IP}:${ETCD_CLIENT_PORT},${PG2_IP}:${ETCD_CLIENT_PORT},${PG3_IP}:${ETCD_CLIENT_PORT} \
  --write-out=table

# 3. Kiểm tra Patroni
patronictl -c /etc/patroni/patroni.yml list ${SCOPE}

# 4. HAProxy Stats
# Mở browser: http://<haproxy_ip>:7000/

# 5. Test kết nối database
psql -h ${HAPROXY_IP} -p ${HAPROXY_PRIMARY_PORT} -U postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

---

## 🎯 Test Failover

```bash
./test-failover.sh
```

Script này sẽ:
- Hiển thị primary hiện tại
- Thực hiện switchover
- Xác nhận primary mới

---

## 📊 Connection Information

Sau khi hoàn tất, sử dụng thông tin sau để kết nối:

```bash
source /etc/ha_postgres/config.env

# Primary (Read-Write)
Host: $HAPROXY_IP
Port: $HAPROXY_PRIMARY_PORT
User: postgres
Password: <password_bạn_đã_nhập_khi_cấu_hình>

# Standby (Read-Only)
Host: $HAPROXY_IP
Port: $HAPROXY_STANDBY_PORT
User: postgres
Password: <password_bạn_đã_nhập_khi_cấu_hình>
```

**HAProxy Stats UI:**
```
http://$HAPROXY_IP:$HAPROXY_STATS_PORT/
```

---

## 🔧 Useful Scripts

- `./show-config.sh` - Hiển thị cấu hình hiện tại
- `./edit-config.sh` - Chỉnh sửa cấu hình (cẩn thận!)
- `./99-verify-cluster.sh` - Kiểm tra toàn bộ cluster
- `./test-failover.sh` - Test failover mechanism

---

## 📝 Next Steps

1. **Lưu ý về passwords**: Bạn đã nhập các password trong quá trình cài đặt, hãy lưu giữ chúng an toàn
2. **Setup backup** với pgBackRest
3. **Configure monitoring** với Prometheus/Grafana
4. **Setup firewall rules**
5. **Configure SSL/TLS** cho connections

Xem [DEPLOYMENT.md](DEPLOYMENT.md) để biết chi tiết.

---

## ❓ Troubleshooting

Nếu gặp vấn đề, xem:
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- [COMMANDS.md](COMMANDS.md)

Hoặc kiểm tra logs:
```bash
journalctl -u patroni -f
journalctl -u etcd -f
systemctl status postgresql
```

---

**Chúc mừng! Bạn đã triển khai thành công PostgreSQL HA Cluster! 🎉**
