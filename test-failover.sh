#!/bin/bash

# Script: test-failover.sh
# Mô tả: Script test failover của Patroni
# Chạy trên: Bất kỳ node DB nào

set -e

SCOPE="pg_cluster"

echo "=================================================="
echo "     TEST FAILOVER PATRONI CLUSTER"
echo "=================================================="
echo ""

# Kiểm tra cluster hiện tại
echo "1. TRẠNG THÁI CLUSTER HIỆN TẠI:"
echo "----------------------------------------"
patronictl -c /etc/patroni/patroni.yml list $SCOPE
echo ""

# Lấy leader hiện tại
CURRENT_LEADER=$(patronictl -c /etc/patroni/patroni.yml list $SCOPE | grep Leader | awk '{print $2}')
echo "Primary hiện tại: $CURRENT_LEADER"
echo ""

# Xác nhận thực hiện failover
read -p "Bạn có muốn thực hiện switchover? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Hủy bỏ failover test."
    exit 0
fi

echo ""
echo "2. THỰC HIỆN SWITCHOVER (PLANNED FAILOVER):"
echo "----------------------------------------"
echo "Chuyển primary sang node khác một cách có kế hoạch..."
patronictl -c /etc/patroni/patroni.yml switchover $SCOPE --force

echo ""
echo "Đợi 10 giây để cluster ổn định..."
sleep 10

echo ""
echo "3. TRẠNG THÁI CLUSTER SAU SWITCHOVER:"
echo "----------------------------------------"
patronictl -c /etc/patroni/patroni.yml list $SCOPE

NEW_LEADER=$(patronictl -c /etc/patroni/patroni.yml list $SCOPE | grep Leader | awk '{print $2}')
echo ""
echo "Primary cũ: $CURRENT_LEADER"
echo "Primary mới: $NEW_LEADER"

if [ "$CURRENT_LEADER" != "$NEW_LEADER" ]; then
    echo ""
    echo "✓ Switchover thành công! Primary đã chuyển từ $CURRENT_LEADER sang $NEW_LEADER"
else
    echo ""
    echo "⚠ Switchover không thành công hoặc cluster giữ nguyên primary"
fi

echo ""
echo "=================================================="
echo "     HOÀN THÀNH TEST FAILOVER"
echo "=================================================="
