#!/bin/bash

# Script để apply lại schema cho cả 2 Solr containers (8.5.2 và 9.11)

COLLECTION_NAME_8="${1:-topic_tanvd}"
COLLECTION_NAME_9="${2:-topic_tanvd_9}"

# Cấu hình Solr 8.5.2
SERVICE_8="solr_8"              # Service name trong docker-compose
CONTAINER_8="solr_8_5_2"        # Container name
SOLR_URL_8="http://localhost:8983/solr"
CONFIGSET_8="wordcloud_config"

# Cấu hình Solr 9.11
SERVICE_9="solr_9"              # Service name trong docker-compose
CONTAINER_9="solr_9_11"        # Container name
SOLR_URL_9="http://localhost:8984/solr"
CONFIGSET_9="wordcloud_config"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔄 Apply Schema cho cả 2 Solr Containers${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Hàm apply schema cho một Solr instance
apply_schema_to_solr() {
    local SERVICE_NAME=$1
    local CONTAINER_NAME=$2
    local SOLR_URL=$3
    local COLLECTION_NAME=$4
    local CONFIGSET=$5
    local SOLR_VERSION=$6
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 Processing: ${SOLR_VERSION}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Bước 1: Kiểm tra Solr
    echo -e "${BLUE}📋 Bước 1: Kiểm tra Solr ${SOLR_VERSION}...${NC}"
    if ! curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
        echo -e "${RED}❌ Solr ${SOLR_VERSION} không chạy. Đang khởi động...${NC}"
        docker-compose up -d ${SERVICE_NAME}
        echo -e "${YELLOW}   Đợi Solr khởi động (15 giây)...${NC}"
        sleep 15
    fi
    echo -e "${GREEN}✅ Solr ${SOLR_VERSION} đang chạy${NC}"
    echo ""
    
    # Bước 2: Xóa collection cũ TRƯỚC KHI restart (nếu có)
    echo -e "${BLUE}📋 Bước 2: Xóa collection cũ (nếu có) trước khi restart...${NC}"
    CORE_CHECK_BEFORE=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null)
    if echo "$CORE_CHECK_BEFORE" | grep -q "\"name\":\"${COLLECTION_NAME}\"" || \
       curl -s "${SOLR_URL}/admin/cores?action=STATUS" 2>/dev/null | grep -q "\"${COLLECTION_NAME}\""; then
        echo -e "${YELLOW}⚠️  Tìm thấy collection cũ: ${COLLECTION_NAME}. Đang xóa...${NC}"
        curl -s "${SOLR_URL}/admin/cores?action=UNLOAD&core=${COLLECTION_NAME}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" > /dev/null 2>&1
        sleep 2
        echo -e "${GREEN}✅ Đã xóa collection cũ${NC}"
    else
        echo -e "${GREEN}✅ Không có collection cũ nào${NC}"
    fi
    echo ""
    
    # Bước 3: Restart Solr để load schema mới
    echo -e "${BLUE}📋 Bước 2: Restart Solr để load schema mới...${NC}"
    echo -e "${YELLOW}   Đang restart ${SOLR_VERSION}...${NC}"
    docker-compose restart ${SERVICE_NAME}
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Lỗi khi restart ${SOLR_VERSION}${NC}"
        return 1
    fi
    echo -e "${YELLOW}   Đợi Solr khởi động lại (20 giây)...${NC}"
    sleep 20
    
    # Kiểm tra Solr đã sẵn sàng
    for i in {1..10}; do
        if curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Solr ${SOLR_VERSION} đã sẵn sàng${NC}"
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}❌ Solr ${SOLR_VERSION} chưa sẵn sàng sau 10 lần thử${NC}"
            return 1
        fi
        echo -e "${YELLOW}   Đợi... ($i/10)${NC}"
        sleep 3
    done
    echo ""
    
    # Bước 4: Xóa collection cũ (sau khi restart, solr-precreate đã tạo lại core với schema cũ nếu core đã tồn tại)
    echo -e "${BLUE}📋 Bước 4: Xóa collection cũ để tạo lại với schema mới...${NC}"
    
    # Kiểm tra core có tồn tại không
    CORE_CHECK=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null)
    if echo "$CORE_CHECK" | grep -q "\"name\":\"${COLLECTION_NAME}\"" || \
       curl -s "${SOLR_URL}/admin/cores?action=STATUS" 2>/dev/null | grep -q "\"${COLLECTION_NAME}\""; then
        echo -e "${YELLOW}⚠️  Tìm thấy collection: ${COLLECTION_NAME}. Đang xóa...${NC}"
        
        # Xóa bằng API (cách đáng tin cậy nhất)
        curl -s "${SOLR_URL}/admin/cores?action=UNLOAD&core=${COLLECTION_NAME}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" > /dev/null 2>&1
        
        # Thử xóa bằng solr command nếu có
        if [ "$SOLR_VERSION" = "Solr 9.11" ]; then
            docker exec ${CONTAINER_NAME} solr delete -c "${COLLECTION_NAME}" --solr-url "${SOLR_URL}" 2>&1 | grep -v "ERROR" || true
        else
            docker exec ${CONTAINER_NAME} solr delete -c "${COLLECTION_NAME}" 2>&1 | grep -v "ERROR" || true
        fi
        
        echo -e "${YELLOW}   Đợi collection được xóa hoàn toàn (5 giây)...${NC}"
        sleep 5
        
        # Kiểm tra lại
        CORE_CHECK_AFTER=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null)
        if echo "$CORE_CHECK_AFTER" | grep -q "\"name\":\"${COLLECTION_NAME}\""; then
            echo -e "${YELLOW}⚠️  Core vẫn còn, thử xóa lại...${NC}"
            curl -s "${SOLR_URL}/admin/cores?action=UNLOAD&core=${COLLECTION_NAME}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" > /dev/null 2>&1
            sleep 3
        fi
        
        echo -e "${GREEN}✅ Đã xóa collection cũ${NC}"
    else
        echo -e "${GREEN}✅ Không có collection cũ nào${NC}"
    fi
    echo ""
    
    # Bước 5: Tạo lại collection
    echo -e "${BLUE}📋 Bước 5: Tạo lại collection ${COLLECTION_NAME}...${NC}"
    
    # Tạo core với đúng URL cho Solr 9
    CREATE_OUTPUT=""
    if [ "$SOLR_VERSION" = "Solr 9.11" ]; then
        CREATE_OUTPUT=$(docker exec ${CONTAINER_NAME} solr create_core -c ${COLLECTION_NAME} -d ${CONFIGSET} --solr-url "${SOLR_URL}" 2>&1)
    else
        CREATE_OUTPUT=$(docker exec ${CONTAINER_NAME} solr create_core -c ${COLLECTION_NAME} -d ${CONFIGSET} 2>&1)
    fi
    
    CREATE_RESULT=$?
    echo "$CREATE_OUTPUT"
    
    # Nếu lỗi do core đã tồn tại, thử xóa và tạo lại
    if [ $CREATE_RESULT -ne 0 ]; then
        if echo "$CREATE_OUTPUT" | grep -qi "already exists"; then
            echo -e "${YELLOW}⚠️  Core đã tồn tại, đang xóa và tạo lại...${NC}"
            curl -s "${SOLR_URL}/admin/cores?action=UNLOAD&core=${COLLECTION_NAME}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" > /dev/null 2>&1
            sleep 3
            
            if [ "$SOLR_VERSION" = "Solr 9.11" ]; then
                CREATE_OUTPUT=$(docker exec ${CONTAINER_NAME} solr create_core -c ${COLLECTION_NAME} -d ${CONFIGSET} --solr-url "${SOLR_URL}" 2>&1)
            else
                CREATE_OUTPUT=$(docker exec ${CONTAINER_NAME} solr create_core -c ${COLLECTION_NAME} -d ${CONFIGSET} 2>&1)
            fi
            CREATE_RESULT=$?
            echo "$CREATE_OUTPUT"
        fi
    fi
    
    if [ $CREATE_RESULT -ne 0 ]; then
        echo -e "${RED}❌ Có lỗi xảy ra khi tạo collection cho ${SOLR_VERSION}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Đã tạo collection thành công cho ${SOLR_VERSION}!${NC}"
    echo ""
    
    # Bước 6: Kiểm tra kết quả
    echo -e "${BLUE}📋 Bước 6: Kiểm tra kết quả...${NC}"
    STATUS_CHECK=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null | grep -o "\"name\":\"${COLLECTION_NAME}\"" | wc -l)
    if [ "$STATUS_CHECK" -gt 0 ]; then
        echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} đã được tạo thành công trên ${SOLR_VERSION}${NC}"
        return 0
    else
        echo -e "${RED}❌ Collection ${COLLECTION_NAME} chưa được tạo trên ${SOLR_VERSION}${NC}"
        return 1
    fi
}

# Apply schema cho Solr 8.5.2
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 Bắt đầu apply schema cho Solr 8.5.2${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

apply_schema_to_solr "${SERVICE_8}" "${CONTAINER_8}" "${SOLR_URL_8}" "${COLLECTION_NAME_8}" "${CONFIGSET_8}" "Solr 8.5.2"
RESULT_8=$?

echo ""
echo ""

# Apply schema cho Solr 9.11
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 Bắt đầu apply schema cho Solr 9.11${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

apply_schema_to_solr "${SERVICE_9}" "${CONTAINER_9}" "${SOLR_URL_9}" "${COLLECTION_NAME_9}" "${CONFIGSET_9}" "Solr 9.11"
RESULT_9=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $RESULT_8 -eq 0 ] && [ $RESULT_9 -eq 0 ]; then
    echo -e "${GREEN}✅ Hoàn thành! Schema đã được apply cho cả 2 Solr containers${NC}"
    echo ""
    echo -e "${CYAN}📊 Tóm tắt:${NC}"
    echo -e "   ${GREEN}✅ Solr 8.5.2:${NC} ${SOLR_URL_8}/${COLLECTION_NAME_8}"
    echo -e "   ${GREEN}✅ Solr 9.11:${NC} ${SOLR_URL_9}/${COLLECTION_NAME_9}"
    echo ""
    echo -e "${BLUE}📝 Để insert data, chạy:${NC}"
    echo "   ./insert_data.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Có lỗi xảy ra khi apply schema${NC}"
    if [ $RESULT_8 -ne 0 ]; then
        echo -e "${RED}   - Solr 8.5.2: FAILED${NC}"
    fi
    if [ $RESULT_9 -ne 0 ]; then
        echo -e "${RED}   - Solr 9.11: FAILED${NC}"
    fi
    echo ""
    exit 1
fi
