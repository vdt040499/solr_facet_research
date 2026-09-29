#!/bin/bash

# Script để insert data vào container Solr 9 duy nhất.
#
# Cách sử dụng:
#   ./insert_data.sh [data_file]
#
# Tham số:
#   data_file: đường dẫn đến file JSON (mặc định: exported_data_10236707.json ở repo root)
#
# Ví dụ:
#   ./insert_data.sh
#   ./insert_data.sh ../exported_data_10236707.json

# Resolve thư mục chứa chính script này, để gọi được bulk_insert.py / remove_version_field.py
# dù script được chạy từ đâu (repo root hay chính trong 03_insert/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DATA_FILE_INPUT="${1:-${REPO_ROOT}/exported_data_10236707.json}"

# Xử lý tên file (thêm .json nếu cần)
if [ -f "$DATA_FILE_INPUT" ]; then
    DATA_FILE="$DATA_FILE_INPUT"
elif [ -f "${DATA_FILE_INPUT}.json" ]; then
    DATA_FILE="${DATA_FILE_INPUT}.json"
else
    DATA_FILE="$DATA_FILE_INPUT"
fi

# Cấu hình Solr 9
CONTAINER_NAME="solr_9"
SOLR_URL="http://localhost:8983/solr"
COLLECTION_NAME="topic_10236707"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📥 Insert Data vào Solr 9${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Bước 1: Kiểm tra file data
echo -e "${BLUE}📋 Bước 1: Kiểm tra file data...${NC}"
if [ ! -f "$DATA_FILE" ]; then
    echo -e "${RED}❌ Không tìm thấy file data: $DATA_FILE${NC}"
    exit 1
fi

# Kiểm tra xem file có chứa _version_ không
if grep -q '"_version_"' "$DATA_FILE"; then
    echo -e "${YELLOW}⚠️  File chứa field _version_ có thể gây version conflict${NC}"
    echo -e "${YELLOW}   Đang kiểm tra xem có file không có _version_ chưa...${NC}"

    CLEAN_FILE="${DATA_FILE%.json}_no_version.json"

    if [ ! -f "$CLEAN_FILE" ]; then
        echo -e "${YELLOW}   File sạch chưa tồn tại, đang tạo...${NC}"
        if command -v python &> /dev/null; then
            python "${SCRIPT_DIR}/remove_version_field.py" "$DATA_FILE" "$CLEAN_FILE"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}   ✅ Đã tạo file không có _version_: $CLEAN_FILE${NC}"
                DATA_FILE="$CLEAN_FILE"
            else
                echo -e "${RED}   ❌ Không thể tạo file sạch, sẽ thử insert với file gốc${NC}"
            fi
        else
            echo -e "${YELLOW}   ⚠️  Python không có sẵn, sẽ thử insert với file gốc${NC}"
        fi
    else
        echo -e "${GREEN}   ✅ Tìm thấy file không có _version_: $CLEAN_FILE${NC}"
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

# Bước 2: Kiểm tra Solr
echo -e "${BLUE}📋 Bước 2: Kiểm tra Solr...${NC}"
if ! curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
    echo -e "${RED}❌ Solr không chạy${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Solr đang chạy${NC}"

# Kiểm tra collection
echo -e "${BLUE}📋 Kiểm tra collection ${COLLECTION_NAME}...${NC}"
STATUS=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
if [ "$STATUS" -eq 0 ]; then
    echo -e "${RED}❌ Collection ${COLLECTION_NAME} không tồn tại${NC}"
    echo -e "${YELLOW}   Vui lòng chạy 02_schema/apply_schema.sh trước${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} tồn tại${NC}"
echo ""

# Bước 3: Xóa dữ liệu cũ
echo -e "${BLUE}📋 Bước 3: Xóa dữ liệu cũ...${NC}"
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

# Bước 4: Insert data
echo -e "${MAGENTA}⏱️  Bắt đầu insert data...${NC}"
START_TIME=$(date +%s.%N)

if command -v python &> /dev/null; then
    python "${SCRIPT_DIR}/bulk_insert.py" "$DATA_FILE" "$SOLR_URL" "$COLLECTION_NAME" 2000 "$record_count"
    EXIT_CODE=$?
else
    echo -e "${YELLOW}⚠️  Python không có sẵn, sử dụng curl (không có progress bar)...${NC}"
    response=$(curl -s -w "\n%{http_code}" --max-time 3600 -X POST "${SOLR_URL}/${COLLECTION_NAME}/update?commit=true&overwrite=true" \
      -H 'Content-Type: application/json' \
      -d @"$DATA_FILE")

    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        EXIT_CODE=0
    else
        echo "Response: $response_body"
        EXIT_CODE=1
    fi
fi

END_TIME=$(date +%s.%N)
# Dùng awk thay vì bc — bc không có sẵn trên môi trường này (Git Bash Windows)
ELAPSED_TIME=$(awk "BEGIN {printf \"%.2f\", ${END_TIME} - ${START_TIME}}")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$EXIT_CODE" -eq 0 ]; then
    echo -e "${GREEN}✅ Đã insert data thành công!${NC}"
    echo -e "${MAGENTA}⏱️  Thời gian indexing: ${ELAPSED_TIME} giây${NC}"

    count=$(curl -s "${SOLR_URL}/${COLLECTION_NAME}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*')
    if [ ! -z "$count" ]; then
        echo -e "${GREEN}   Tổng số documents: $count${NC}"
    fi
    echo ""
    echo -e "${BLUE}📝 URL: ${SOLR_URL}/${COLLECTION_NAME}${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Lỗi khi insert data${NC}"
    echo ""
    exit 1
fi
