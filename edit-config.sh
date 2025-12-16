#!/bin/bash

# Script: edit-config.sh
# Mô tả: Chỉnh sửa cấu hình cluster

CONFIG_FILE="/etc/ha_postgres/config.env"

# Màu sắc
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ Script này cần chạy với quyền root!${NC}" 
   exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Không tìm thấy file cấu hình: $CONFIG_FILE${NC}"
    echo "Vui lòng chạy ./00-setup-config.sh để tạo cấu hình mới!"
    exit 1
fi

echo -e "${YELLOW}⚠ CẢNH BÁO ⚠${NC}"
echo ""
echo "Việc chỉnh sửa cấu hình sau khi đã triển khai có thể gây lỗi cluster!"
echo ""
echo "Nếu bạn đã cài đặt các services (etcd, Patroni, HAProxy), bạn cần:"
echo "  1. Stop tất cả services"
echo "  2. Sửa config"
echo "  3. Cập nhật lại config files của từng service"
echo "  4. Restart services"
echo ""
read -p "Bạn có chắc chắn muốn chỉnh sửa? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Hủy bỏ."
    exit 0
fi

echo ""
echo "Chọn editor:"
echo "1) nano"
echo "2) vi"
echo "3) vim"
read -p "Chọn (1-3): " editor_choice

case $editor_choice in
    1)
        EDITOR="nano"
        ;;
    2)
        EDITOR="vi"
        ;;
    3)
        EDITOR="vim"
        ;;
    *)
        EDITOR="nano"
        ;;
esac

# Backup config trước khi edit
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

echo ""
echo "Đang mở editor..."
$EDITOR "$CONFIG_FILE"

echo ""
echo -e "${GREEN}✓ Đã lưu cấu hình${NC}"
echo ""
echo "File backup: ${CONFIG_FILE}.backup.*"
echo ""
echo -e "${YELLOW}Các bước tiếp theo:${NC}"
echo "1. Copy file config này sang tất cả các nodes:"
echo "   scp $CONFIG_FILE root@<node_ip>:$CONFIG_FILE"
echo ""
echo "2. Trên mỗi node, restart các services nếu cần:"
echo "   systemctl restart etcd"
echo "   systemctl restart patroni"
echo "   systemctl restart pgbouncer"
echo "   systemctl restart haproxy  # Trên HAProxy node"
echo ""
echo "3. Kiểm tra cluster:"
echo "   ./99-verify-cluster.sh"
echo ""
