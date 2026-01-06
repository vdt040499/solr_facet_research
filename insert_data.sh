#!/bin/bash

# Script để insert data vào Solr collection

COLLECTION_NAME="${1:-topic_tanvd}"
SOLR_URL="http://localhost:8983/solr"
DATA_FILE="${2:-demo_data_topic_tanvd.json}"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📥 Insert Data vào Solr${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Bước 1: Kiểm tra Solr
echo -e "${BLUE}📋 Bước 1: Kiểm tra Solr...${NC}"
if ! curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
    echo -e "${RED}❌ Solr không chạy. Vui lòng khởi động Solr trước${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Solr đang chạy${NC}"
echo ""

# Bước 2: Kiểm tra collection
echo -e "${BLUE}📋 Bước 2: Kiểm tra collection...${NC}"
STATUS=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
if [ "$STATUS" -eq 0 ]; then
    echo -e "${RED}❌ Collection ${COLLECTION_NAME} không tồn tại${NC}"
    echo -e "${YELLOW}   Vui lòng chạy ./apply_schema.sh trước${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} tồn tại${NC}"
echo ""

# Bước 3: Kiểm tra file data
echo -e "${BLUE}📋 Bước 3: Kiểm tra file data...${NC}"
if [ ! -f "$DATA_FILE" ]; then
    echo -e "${RED}❌ Không tìm thấy file data: $DATA_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Tìm thấy file data: $DATA_FILE${NC}"
echo ""

# Bước 4: Xóa dữ liệu cũ (optional)
echo -e "${BLUE}📋 Bước 4: Xóa dữ liệu cũ...${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST "${SOLR_URL}/${COLLECTION_NAME}/update?commit=true" \
  -H 'Content-Type: application/json' \
  -d '{"delete": {"query": "*:*"}}')

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✅ Đã xóa dữ liệu cũ${NC}"
else
    echo -e "${YELLOW}⚠️  Có thể collection đã trống${NC}"
fi
echo ""

# Bước 5: Insert data
echo -e "${BLUE}📋 Bước 5: Insert data từ $DATA_FILE...${NC}"
response=$(curl -s -w "\n%{http_code}" -X POST "${SOLR_URL}/${COLLECTION_NAME}/update?commit=true" \
  -H 'Content-Type: application/json' \
  -d @"$DATA_FILE")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✅ Đã insert data thành công!${NC}"
    
    # Đếm số documents
    count=$(curl -s "${SOLR_URL}/${COLLECTION_NAME}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*')
    echo -e "${GREEN}   Tổng số documents: $count${NC}"
else
    echo -e "${RED}❌ Lỗi khi insert data (HTTP $http_code)${NC}"
    echo "Response: $(echo "$response" | sed '$d')"
    exit 1
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Hoàn thành!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

