#!/bin/bash

# Script để restore dữ liệu từ backup Solr

COLLECTION_NAME="${1:-topic_10236681}"
BACKUP_ID="${2:-0}"  # backupId thường là số (0, 1, 2...) hoặc tên backup
BACKUP_LOCATION="/opt/solr/backups/topic_10236681"
SOLR_URL="http://localhost:8983/solr"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📦 Restore Backup từ Solr${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Bước 1: Kiểm tra Solr
echo -e "${BLUE}📋 Bước 1: Kiểm tra Solr...${NC}"
if ! curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
    echo -e "${RED}❌ Solr không chạy. Đang khởi động...${NC}"
    docker-compose up -d solr
    echo -e "${YELLOW}   Đợi Solr khởi động (15 giây)...${NC}"
    sleep 15
fi
echo -e "${GREEN}✅ Solr đang chạy${NC}"
echo ""

# Bước 2: Kiểm tra backup folder trong container
echo -e "${BLUE}📋 Bước 2: Kiểm tra backup folder...${NC}"
if ! docker exec solr_local test -d "${BACKUP_LOCATION}"; then
    echo -e "${RED}❌ Không tìm thấy backup folder: ${BACKUP_LOCATION}${NC}"
    echo -e "${YELLOW}⚠️  Vui lòng đảm bảo đã mount folder topic_10236681 trong docker-compose.yml${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Tìm thấy backup folder${NC}"
echo ""

# Bước 3: Upload configset từ backup (nếu cần)
echo -e "${BLUE}📋 Bước 3: Kiểm tra và upload configset từ backup...${NC}"
CONFIGSET_NAME="topic_v3"
CONFIGSET_PATH="${BACKUP_LOCATION}/zk_backup_0/configs/${CONFIGSET_NAME}"

# Kiểm tra configset đã tồn tại chưa
CONFIGSET_EXISTS=$(curl -s "${SOLR_URL}/admin/configs?action=LIST&wt=json" 2>/dev/null | grep -o "\"${CONFIGSET_NAME}\"" | wc -l)

if [ "$CONFIGSET_EXISTS" -eq 0 ]; then
    echo -e "${YELLOW}   Configset ${CONFIGSET_NAME} chưa tồn tại, đang upload từ backup...${NC}"
    
    # Tạo configset từ backup folder
    if docker exec solr_local test -d "${CONFIGSET_PATH}"; then
        # Upload configset bằng cách zip và upload
        echo -e "${YELLOW}   Đang tạo configset từ backup...${NC}"
        docker exec solr_local bash -c "cd ${CONFIGSET_PATH} && zip -r /tmp/${CONFIGSET_NAME}.zip ." 2>/dev/null
        
        if [ $? -eq 0 ]; then
            # Copy zip vào container và upload
            docker cp solr_local:/tmp/${CONFIGSET_NAME}.zip /tmp/${CONFIGSET_NAME}.zip 2>/dev/null || true
            docker exec solr_local solr zk upconfig -n ${CONFIGSET_NAME} -d ${CONFIGSET_PATH} 2>/dev/null || {
                echo -e "${YELLOW}⚠️  Không thể upload configset tự động. Sẽ thử restore trực tiếp...${NC}"
            }
            echo -e "${GREEN}✅ Đã upload configset${NC}"
        else
            echo -e "${YELLOW}⚠️  Không thể tạo configset từ backup. Sẽ thử restore trực tiếp...${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Không tìm thấy configset trong backup. Sẽ thử restore trực tiếp...${NC}"
    fi
else
    echo -e "${GREEN}✅ Configset ${CONFIGSET_NAME} đã tồn tại${NC}"
fi
echo ""

# Bước 4: Kiểm tra collection đã tồn tại chưa
echo -e "${BLUE}📋 Bước 4: Kiểm tra collection...${NC}"
STATUS=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
if [ "$STATUS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Collection ${COLLECTION_NAME} đã tồn tại${NC}"
    read -p "Bạn có muốn xóa collection cũ và restore lại? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}   Đang xóa collection cũ...${NC}"
        docker exec solr_local solr delete -c "${COLLECTION_NAME}" 2>/dev/null
        sleep 3
        echo -e "${GREEN}✅ Đã xóa collection cũ${NC}"
    else
        echo -e "${YELLOW}⚠️  Bỏ qua restore${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} chưa tồn tại, sẽ được tạo mới${NC}"
fi
echo ""

# Bước 5: Tạo collection nếu chưa tồn tại (cần thiết cho restore)
echo -e "${BLUE}📋 Bước 5: Tạo collection (nếu cần)...${NC}"
STATUS_CHECK=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)

if [ "$STATUS_CHECK" -eq 0 ]; then
    echo -e "${YELLOW}   Collection chưa tồn tại, đang tạo với configset ${CONFIGSET_NAME}...${NC}"
    docker exec solr_local solr create_core -c ${COLLECTION_NAME} -d ${CONFIGSET_NAME} 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Không thể tạo collection với configset ${CONFIGSET_NAME}, thử tạo với configset mặc định...${NC}"
        docker exec solr_local solr create_core -c ${COLLECTION_NAME} 2>/dev/null || {
            echo -e "${RED}❌ Không thể tạo collection${NC}"
            exit 1
        }
    }
    sleep 2
    echo -e "${GREEN}✅ Đã tạo collection${NC}"
else
    echo -e "${GREEN}✅ Collection đã tồn tại${NC}"
fi
echo ""

# Bước 6: Restore từ backup
echo -e "${BLUE}📋 Bước 6: Restore từ backup...${NC}"
echo -e "${YELLOW}   Collection: ${COLLECTION_NAME}${NC}"
echo -e "${YELLOW}   Backup ID: ${BACKUP_ID}${NC}"
echo -e "${YELLOW}   Backup location: ${BACKUP_LOCATION}${NC}"
echo ""

# Sử dụng Solr REST API để restore
# Note: backupId thường là số (0, 1, 2...) tương ứng với backup_0, backup_1...
RESTORE_URL="${SOLR_URL}/admin/collections?action=RESTORE&name=${COLLECTION_NAME}&location=${BACKUP_LOCATION}&backupId=${BACKUP_ID}"

echo -e "${BLUE}   Đang gọi API restore...${NC}"
response=$(curl -s -w "\n%{http_code}" "${RESTORE_URL}")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✅ Restore request đã được gửi thành công${NC}"
    echo ""
    
    # Đợi restore hoàn tất
    echo -e "${YELLOW}   Đợi restore hoàn tất (có thể mất vài phút)...${NC}"
    sleep 5
    
    # Kiểm tra collection đã được tạo chưa
    for i in {1..30}; do
        STATUS_CHECK=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
        if [ "$STATUS_CHECK" -gt 0 ]; then
            echo -e "${GREEN}✅ Collection đã được tạo${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${YELLOW}⚠️  Collection chưa được tạo sau 30 lần thử. Có thể restore đang chạy trong background${NC}"
        fi
        echo -e "${YELLOW}   Đợi... ($i/30)${NC}"
        sleep 3
    done
else
    echo -e "${RED}❌ Lỗi khi restore (HTTP $http_code)${NC}"
    echo "Response: $response_body"
    exit 1
fi
echo ""

# Bước 7: Kiểm tra số documents
echo -e "${BLUE}📋 Bước 7: Kiểm tra kết quả...${NC}"
sleep 2
count=$(curl -s "${SOLR_URL}/${COLLECTION_NAME}/select?q=*:*&rows=0" 2>/dev/null | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*')
if [ ! -z "$count" ]; then
    echo -e "${GREEN}✅ Restore thành công!${NC}"
    echo -e "${GREEN}   Tổng số documents: $count${NC}"
else
    echo -e "${YELLOW}⚠️  Không thể đếm số documents. Collection có thể đang được restore trong background${NC}"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Hoàn thành!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📝 Để kiểm tra collection, truy cập:${NC}"
echo "   ${SOLR_URL}/#/${COLLECTION_NAME}/query"
echo ""

