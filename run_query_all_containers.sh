#!/bin/bash

# Script để chạy query Solr trên cả 3 containers
# Query: facet search với id filter
#
# Cách sử dụng:
#   ./run_query_all_containers.sh [id]
#
# Tham số:
#   id: ID để filter (mặc định: 0034f7e7-7c85-5ae4-8c30-145cb0aecfae)
#
# Ví dụ:
#   ./run_query_all_containers.sh
#   ./run_query_all_containers.sh 0034f7e7-7c85-5ae4-8c30-145cb0aecfae

ID="${1:-0034f7e7-7c85-5ae4-8c30-145cb0aecfae}"

# Base query parameters
QUERY_PARAMS="q=*:*&fq=id:${ID}&facet=true&facet.field=search_text_cloud&facet.sort=count&rows=0&wt=json&indent=true&facet.limit=1000&facet.mincount=1"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔍 Running Solr Query on All Containers${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${CYAN}ID Filter: ${ID}${NC}"
echo ""

# Hàm chạy query trên một container
run_query() {
    local CONTAINER_NAME=$1
    local PORT=$2
    local CORE=$3
    local SOLR_VERSION=$4
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 Container: ${SOLR_VERSION}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    URL="http://localhost:${PORT}/solr/${CORE}/select?${QUERY_PARAMS}"
    echo -e "${BLUE}URL: ${URL}${NC}"
    echo ""
    
    # Chạy query trực tiếp (không cần ping trước)
    RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 30 "${URL}" 2>&1)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')
    
    # Kiểm tra nếu có lỗi kết nối
    if echo "$RESPONSE_BODY" | grep -q "Connection refused\|Failed to connect\|Could not resolve host"; then
        echo -e "${RED}❌ Không thể kết nối đến Solr ${SOLR_VERSION} trên port ${PORT}${NC}"
        echo -e "${YELLOW}   Hãy kiểm tra container có đang chạy không:${NC}"
        echo -e "${YELLOW}   docker ps | grep ${CONTAINER_NAME}${NC}"
        echo -e "${YELLOW}   Hoặc khởi động containers: docker-compose up -d${NC}"
        return 1
    fi
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "$RESPONSE_BODY" | python -m json.tool 2>/dev/null || echo "$RESPONSE_BODY"
        echo ""
        echo -e "${GREEN}✅ Query thành công${NC}"
        return 0
    else
        echo -e "${RED}❌ Lỗi HTTP ${HTTP_CODE}${NC}"
        echo "$RESPONSE_BODY"
        return 1
    fi
}

# Container 1: solr_8_5_2_1_1 (port 8983)
run_query "solr_8_5_2_1_1" "8983" "topic_tanvd" "Solr 8.5.2 (VnCoreNLP 1.1.1)"
RESULT_1=$?
echo ""
echo ""

# Container 2: solr_8_5_2_1_2 (port 8984)
run_query "solr_8_5_2_1_2" "8984" "topic_tanvd" "Solr 8.5.2 (VnCoreNLP 1.2)"
RESULT_2=$?
echo ""
echo ""

# Container 3: solr_9_11 (port 8985) - Note: core name is topic_tanvd_9
run_query "solr_9_11" "8985" "topic_tanvd_9" "Solr 9.11"
RESULT_3=$?
echo ""
echo ""

# Tóm tắt kết quả
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}📊 Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $RESULT_1 -eq 0 ]; then
    echo -e "${GREEN}✅ Solr 8.5.2 (VnCoreNLP 1.1.1): SUCCESS${NC}"
else
    echo -e "${RED}❌ Solr 8.5.2 (VnCoreNLP 1.1.1): FAILED${NC}"
fi

if [ $RESULT_2 -eq 0 ]; then
    echo -e "${GREEN}✅ Solr 8.5.2 (VnCoreNLP 1.2): SUCCESS${NC}"
else
    echo -e "${RED}❌ Solr 8.5.2 (VnCoreNLP 1.2): FAILED${NC}"
fi

if [ $RESULT_3 -eq 0 ]; then
    echo -e "${GREEN}✅ Solr 9.11: SUCCESS${NC}"
else
    echo -e "${RED}❌ Solr 9.11: FAILED${NC}"
fi

echo ""

if [ $RESULT_1 -eq 0 ] && [ $RESULT_2 -eq 0 ] && [ $RESULT_3 -eq 0 ]; then
    exit 0
else
    exit 1
fi
