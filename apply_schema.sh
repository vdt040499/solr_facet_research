#!/bin/bash

# Script để apply lại schema cho Solr collection

COLLECTION_NAME="${1:-topic_tanvd}"
SOLR_URL="http://localhost:8983/solr"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔄 Apply Schema cho Solr${NC}"
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

# Bước 2: Xóa tất cả collections cũ
echo -e "${BLUE}📋 Bước 2: Xóa tất cả collections cũ...${NC}"

# Lấy danh sách tất cả collections
COLLECTIONS=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS" 2>/dev/null | grep -o '"name":"[^"]*"' | grep -o '"[^"]*"' | tr -d '"')

if [ ! -z "$COLLECTIONS" ]; then
    echo -e "${YELLOW}⚠️  Tìm thấy các collections cũ. Đang xóa...${NC}"
    for collection in $COLLECTIONS; do
        echo -e "${YELLOW}   Đang xóa collection: $collection${NC}"
        docker exec solr_local solr delete -c "$collection" 2>/dev/null
    done
    echo -e "${YELLOW}   Đợi collections được xóa hoàn toàn (3 giây)...${NC}"
    sleep 3
    echo -e "${GREEN}✅ Đã xóa tất cả collections cũ${NC}"
else
    echo -e "${GREEN}✅ Không có collection cũ nào${NC}"
fi
echo ""

# Bước 3: Tạo lại collection với config mới
echo -e "${BLUE}📋 Bước 3: Tạo lại collection với schema mới...${NC}"
echo -e "${YELLOW}⚠️  Schema được load từ wordcloud_config/conf/managed-schema.xml${NC}"

# Restart Solr để load schema mới
echo -e "${YELLOW}   Đang restart Solr để load schema mới...${NC}"
docker-compose restart solr
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Lỗi khi restart Solr${NC}"
    exit 1
fi
echo -e "${YELLOW}   Đợi Solr khởi động lại (20 giây)...${NC}"
sleep 20

# Kiểm tra Solr đã sẵn sàng
for i in {1..10}; do
    if curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Solr đã sẵn sàng${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${RED}❌ Solr chưa sẵn sàng sau 10 lần thử${NC}"
        exit 1
    fi
    echo -e "${YELLOW}   Đợi... ($i/10)${NC}"
    sleep 3
done

# Tạo lại collection
echo -e "${BLUE}   Đang tạo lại collection ${COLLECTION_NAME}...${NC}"
docker exec solr_local solr create_core -c ${COLLECTION_NAME} -d wordcloud_config

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Có lỗi xảy ra khi tạo collection${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Đã tạo lại collection thành công!${NC}"
echo ""

# Bước 4: Kiểm tra kết quả
echo -e "${BLUE}📋 Bước 4: Kiểm tra kết quả...${NC}"
STATUS_CHECK=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
if [ "$STATUS_CHECK" -gt 0 ]; then
    echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} đã được tạo thành công${NC}"
else
    echo -e "${RED}❌ Collection ${COLLECTION_NAME} chưa được tạo${NC}"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Hoàn thành! Schema đã được apply${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📝 Để insert data, chạy:${NC}"
echo "   ./insert_data.sh"
echo ""

