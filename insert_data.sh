#!/bin/bash

# Script để insert data vào cả 2 Solr containers và so sánh thời gian indexing

COLLECTION_NAME_8="${1:-topic_tanvd}"
COLLECTION_NAME_9="${2:-topic_tanvd_9}"
DATA_FILE="${3:-exported_data.json}"

# Cấu hình Solr 8.5.2
CONTAINER_8="solr_8_5_2"
SOLR_URL_8="http://localhost:8983/solr"

# Cấu hình Solr 9.11
CONTAINER_9="solr_9_11"
SOLR_URL_9="http://localhost:8984/solr"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📥 Insert Data vào cả 2 Solr Containers${NC}"
echo -e "${BLUE}⏱️  So sánh thời gian indexing${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Hàm insert data vào một Solr instance và đo thời gian
insert_data_to_solr() {
    local CONTAINER_NAME=$1
    local SOLR_URL=$2
    local COLLECTION_NAME=$3
    local SOLR_VERSION=$4
    local DATA_FILE=$5
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 Processing: ${SOLR_VERSION}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Kiểm tra Solr
    echo -e "${BLUE}📋 Kiểm tra Solr ${SOLR_VERSION}...${NC}"
    if ! curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
        echo -e "${RED}❌ Solr ${SOLR_VERSION} không chạy${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Solr ${SOLR_VERSION} đang chạy${NC}"
    
    # Kiểm tra collection
    echo -e "${BLUE}📋 Kiểm tra collection ${COLLECTION_NAME}...${NC}"
    STATUS=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
    if [ "$STATUS" -eq 0 ]; then
        echo -e "${RED}❌ Collection ${COLLECTION_NAME} không tồn tại trên ${SOLR_VERSION}${NC}"
        echo -e "${YELLOW}   Vui lòng chạy ./apply_schema.sh trước${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} tồn tại${NC}"
    echo ""
    
    # Xóa dữ liệu cũ
    echo -e "${BLUE}📋 Xóa dữ liệu cũ...${NC}"
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
    
    # Bắt đầu đo thời gian
    echo -e "${MAGENTA}⏱️  Bắt đầu insert data vào ${SOLR_VERSION}...${NC}"
    START_TIME=$(date +%s.%N)
    
    # Insert data
    response=$(curl -s -w "\n%{http_code}" --max-time 600 -X POST "${SOLR_URL}/${COLLECTION_NAME}/update?commit=true&overwrite=true" \
      -H 'Content-Type: application/json' \
      -d @"$DATA_FILE")
    
    END_TIME=$(date +%s.%N)
    ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)
    
    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ Đã insert data thành công vào ${SOLR_VERSION}!${NC}"
        echo -e "${MAGENTA}⏱️  Thời gian indexing: ${ELAPSED_TIME} giây${NC}"
        
        # Đếm số documents
        echo -e "${YELLOW}   Đang đếm số documents...${NC}"
        count=$(curl -s "${SOLR_URL}/${COLLECTION_NAME}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*')
        if [ ! -z "$count" ]; then
            echo -e "${GREEN}   Tổng số documents: $count${NC}"
        else
            echo -e "${YELLOW}   ⚠️  Không thể đếm số documents${NC}"
        fi
        
        # Trả về thời gian
        echo "$ELAPSED_TIME"
        return 0
    else
        echo -e "${RED}❌ Lỗi khi insert data vào ${SOLR_VERSION} (HTTP $http_code)${NC}"
        echo "Response: $response_body"
        return 1
    fi
}

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
            python remove_version_field.py "$DATA_FILE" "$CLEAN_FILE"
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

# Insert vào Solr 8.5.2
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 Bắt đầu insert vào Solr 8.5.2${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TIME_8=$(insert_data_to_solr "${CONTAINER_8}" "${SOLR_URL_8}" "${COLLECTION_NAME_8}" "Solr 8.5.2" "${DATA_FILE}")
RESULT_8=$?

echo ""
echo ""

# Insert vào Solr 9.11
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 Bắt đầu insert vào Solr 9.11${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

TIME_9=$(insert_data_to_solr "${CONTAINER_9}" "${SOLR_URL_9}" "${COLLECTION_NAME_9}" "Solr 9.11" "${DATA_FILE}")
RESULT_9=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}📊 KẾT QUẢ SO SÁNH THỜI GIAN INDEXING${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $RESULT_8 -eq 0 ] && [ $RESULT_9 -eq 0 ]; then
    echo -e "${GREEN}✅ Hoàn thành insert data cho cả 2 Solr containers!${NC}"
    echo ""
    echo -e "${CYAN}⏱️  Thời gian indexing:${NC}"
    
    if [ ! -z "$TIME_8" ] && [ ! -z "$TIME_9" ]; then
        TIME_8_FORMATTED=$(printf "%.2f" $TIME_8)
        TIME_9_FORMATTED=$(printf "%.2f" $TIME_9)
        
        echo -e "   ${BLUE}Solr 8.5.2:${NC} ${TIME_8_FORMATTED} giây"
        echo -e "   ${BLUE}Solr 9.11:${NC} ${TIME_9_FORMATTED} giây"
        echo ""
        
        # So sánh
        DIFF=$(echo "$TIME_8 - $TIME_9" | bc)
        DIFF_ABS=$(echo "if ($DIFF < 0) -($DIFF) else $DIFF" | bc)
        DIFF_PERCENT=$(echo "scale=2; ($DIFF_ABS / $TIME_8) * 100" | bc)
        
        if (( $(echo "$TIME_8 > $TIME_9" | bc -l) )); then
            echo -e "${GREEN}   🏆 Solr 9.11 nhanh hơn ${DIFF_ABS} giây (${DIFF_PERCENT}% nhanh hơn)${NC}"
        elif (( $(echo "$TIME_9 > $TIME_8" | bc -l) )); then
            echo -e "${GREEN}   🏆 Solr 8.5.2 nhanh hơn ${DIFF_ABS} giây (${DIFF_PERCENT}% nhanh hơn)${NC}"
        else
            echo -e "${YELLOW}   ⚖️  Thời gian indexing gần như bằng nhau${NC}"
        fi
    else
        echo -e "${YELLOW}   ⚠️  Không thể so sánh thời gian (thiếu dữ liệu)${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}📝 URLs:${NC}"
    echo -e "   ${GREEN}Solr 8.5.2:${NC} ${SOLR_URL_8}/${COLLECTION_NAME_8}"
    echo -e "   ${GREEN}Solr 9.11:${NC} ${SOLR_URL_9}/${COLLECTION_NAME_9}"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Có lỗi xảy ra khi insert data${NC}"
    if [ $RESULT_8 -ne 0 ]; then
        echo -e "${RED}   - Solr 8.5.2: FAILED${NC}"
    fi
    if [ $RESULT_9 -ne 0 ]; then
        echo -e "${RED}   - Solr 9.11: FAILED${NC}"
    fi
    echo ""
    exit 1
fi
