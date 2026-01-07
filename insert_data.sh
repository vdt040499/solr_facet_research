#!/bin/bash

# Script để insert data vào Solr collection

COLLECTION_NAME="${1:-topic_tanvd}"
SOLR_URL="http://localhost:8983/solr"
DATA_FILE="${2:-exported_data.json}"

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

# Kiểm tra xem file có chứa _version_ không
if grep -q '"_version_"' "$DATA_FILE"; then
    echo -e "${YELLOW}⚠️  File chứa field _version_ có thể gây version conflict${NC}"
    echo -e "${YELLOW}   Đang kiểm tra xem có file không có _version_ chưa...${NC}"
    
    # Tạo tên file mới không có _version_
    CLEAN_FILE="${DATA_FILE%.json}_no_version.json"
    
    if [ ! -f "$CLEAN_FILE" ]; then
        echo -e "${YELLOW}   File sạch chưa tồn tại, đang tạo...${NC}"
        if command -v python &> /dev/null; then
            python remove_version_field.py "$DATA_FILE" "$CLEAN_FILE"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}   ✅ Đã tạo file không có _version_: $CLEAN_FILE${NC}"
                DATA_FILE="$CLEAN_FILE"
            else
                echo -e "${RED}   ❌ Không thể tạo file sạch, sẽ thử insert với file gốc${NC}"
            fi
        else
            echo -e "${YELLOW}   ⚠️  Python không có sẵn, sẽ thử insert với file gốc${NC}"
            echo -e "${YELLOW}   💡 Nếu gặp lỗi version conflict, chạy:${NC}"
            echo -e "${YELLOW}      python remove_version_field.py $DATA_FILE $CLEAN_FILE${NC}"
        fi
    else
        echo -e "${GREEN}   ✅ Tìm thấy file không có _version_: $CLEAN_FILE${NC}"
        echo -e "${YELLOW}   Sử dụng file này để tránh version conflict${NC}"
        DATA_FILE="$CLEAN_FILE"
    fi
    echo ""
fi

# Hiển thị thông tin file
file_size=$(du -h "$DATA_FILE" | cut -f1)
record_count=$(grep -o '"id"' "$DATA_FILE" | wc -l)
echo -e "${GREEN}✅ Sử dụng file data: $DATA_FILE${NC}"
echo -e "${GREEN}   Kích thước: $file_size${NC}"
echo -e "${GREEN}   Số records (ước tính): $record_count${NC}"
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
echo -e "${YELLOW}   Đang upload và insert data (có thể mất vài phút với file lớn)...${NC}"
echo -e "${YELLOW}   Lưu ý: Sử dụng overwrite=true để tránh version conflict${NC}"

# Sử dụng --max-time để tránh timeout với file lớn
# Thêm overwrite=true để force overwrite documents (tránh version conflict)
response=$(curl -s -w "\n%{http_code}" --max-time 300 -X POST "${SOLR_URL}/${COLLECTION_NAME}/update?commit=true&overwrite=true" \
  -H 'Content-Type: application/json' \
  -d @"$DATA_FILE")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✅ Đã insert data thành công!${NC}"
    
    # Đếm số documents
    echo -e "${YELLOW}   Đang đếm số documents...${NC}"
    count=$(curl -s "${SOLR_URL}/${COLLECTION_NAME}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*')
    if [ ! -z "$count" ]; then
        echo -e "${GREEN}   Tổng số documents trong collection: $count${NC}"
    else
        echo -e "${YELLOW}   ⚠️  Không thể đếm số documents${NC}"
    fi
else
    echo -e "${RED}❌ Lỗi khi insert data (HTTP $http_code)${NC}"
    echo "Response: $response_body"
    exit 1
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Hoàn thành!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

