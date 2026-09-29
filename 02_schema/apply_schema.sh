#!/bin/bash

# Script để apply lại schema cho container Solr 9 duy nhất.
# Dùng khi bạn sửa managed-schema.xml/solrconfig.xml trong wordcloud_config_solr/
# và muốn container đang chạy nạp lại config đó (mount configset không tự
# reload — phải xóa và tạo lại core).
#
# LƯU Ý QUAN TRỌNG: core này dùng fieldType nạp từ jar ngoài
# (org.apache.lucene.analysis.vi.VietnameseAnalyzer, xem solr-vn-tokenizer/).
# Solr 9 có bug: gọi CoreAdmin API "action=CREATE" để tạo core mới trong lúc
# JVM đang chạy sẽ báo "Error loading class ...VietnameseAnalyzer" dù đúng
# jar đã mount sẵn — cùng jar đó lại load được bình thường lúc container
# khởi động (CorePropertiesLocator tự phát hiện core có sẵn trên đĩa).
# Nên script này KHÔNG gọi "solr create_core" qua API — nó tạo core thẳng
# trên đĩa bằng precreate-core (chỉ copy file, không đụng JVM đang chạy)
# rồi restart container để JVM tự phát hiện và load, đúng con đường chạy được.

# Tắt path conversion của Git Bash/MSYS trên Windows — không có biến này,
# đường dẫn Unix truyền cho `docker exec` (vd. /opt/solr/...) bị MSYS tự
# đổi thành đường dẫn Windows (C:/Program Files/Git/opt/solr/...) trước khi
# vào container, làm lệnh bên trong container luôn báo "no such file".
# Biến này không có tác dụng gì trên Linux/macOS, an toàn để luôn set.
export MSYS_NO_PATHCONV=1

# Resolve repo root để docker-compose luôn tìm đúng docker-compose.yml,
# dù script được gọi từ đâu (repo root hay chính trong 02_schema/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

COLLECTION_NAME="${1:-topic_10236707}"

# Cấu hình Solr 9
SERVICE_NAME="solr_9"           # Service name trong docker-compose
CONTAINER_NAME="solr_9"         # Container name
SOLR_URL="http://localhost:8983/solr"
CONFIGSET_PATH="/opt/solr/server/solr/configsets/wordcloud_config"

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔄 Apply Schema cho Solr 9${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Bước 1: Kiểm tra Solr, khởi động nếu chưa chạy
echo -e "${BLUE}📋 Bước 1: Kiểm tra Solr...${NC}"
if ! curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Solr không chạy. Đang khởi động...${NC}"
    docker-compose up -d ${SERVICE_NAME}
    echo -e "${YELLOW}   Đợi Solr khởi động (15 giây)...${NC}"
    sleep 15
fi
echo -e "${GREEN}✅ Solr đang chạy${NC}"
echo ""

# Bước 2: Xóa collection cũ (nếu có) — cần deleteInstanceDir để dọn sạch
# lib/ và models/ cũ trên đĩa, không thì precreate-core ở bước 3 sẽ báo lỗi
# "already exists" hoặc giữ lại file rác từ config cũ.
echo -e "${BLUE}📋 Bước 2: Xóa collection cũ (nếu có)...${NC}"
CORE_CHECK=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null)
if echo "$CORE_CHECK" | grep -q "\"name\":\"${COLLECTION_NAME}\""; then
    echo -e "${YELLOW}⚠️  Tìm thấy collection cũ: ${COLLECTION_NAME}. Đang xóa...${NC}"
    curl -s "${SOLR_URL}/admin/cores?action=UNLOAD&core=${COLLECTION_NAME}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true" > /dev/null 2>&1
    sleep 3
    echo -e "${GREEN}✅ Đã xóa collection cũ${NC}"
else
    echo -e "${GREEN}✅ Không có collection cũ nào${NC}"
fi
echo ""

# Bước 3: Tạo core mới trên đĩa (KHÔNG qua CoreAdmin API — xem lý do ở đầu file)
echo -e "${BLUE}📋 Bước 3: Tạo core ${COLLECTION_NAME} trên đĩa từ configset mới nhất...${NC}"
CREATE_OUTPUT=$(docker exec ${CONTAINER_NAME} /opt/solr/docker/scripts/precreate-core "${COLLECTION_NAME}" "${CONFIGSET_PATH}" 2>&1)
echo "$CREATE_OUTPUT"
if ! echo "$CREATE_OUTPUT" | grep -qi "^Created\|already exists"; then
    echo -e "${RED}❌ precreate-core lỗi, dừng lại${NC}"
    exit 1
fi
echo ""

# Bước 4: Restart để JVM tự phát hiện và load core vừa tạo
echo -e "${BLUE}📋 Bước 4: Restart Solr để load core với schema mới...${NC}"
docker-compose restart ${SERVICE_NAME}
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Lỗi khi restart Solr${NC}"
    exit 1
fi
echo -e "${YELLOW}   Đợi Solr khởi động lại (20 giây)...${NC}"
sleep 20

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
echo ""

# Bước 5: Kiểm tra kết quả — phải xem cả initFailures, không chỉ STATUS
# (core "tồn tại" trong STATUS không có nghĩa là load thành công; lỗi
# classloader/schema parse nằm ở initFailures của cùng response này)
echo -e "${BLUE}📋 Bước 5: Kiểm tra kết quả...${NC}"
STATUS_RESPONSE=$(curl -s "${SOLR_URL}/admin/cores?action=STATUS&core=${COLLECTION_NAME}" 2>/dev/null)
if echo "$STATUS_RESPONSE" | grep -q "\"initFailures\":{ *}" ; then
    echo -e "${GREEN}✅ Collection ${COLLECTION_NAME} đã load thành công, không lỗi${NC}"
    echo ""
    echo -e "${CYAN}📝 URL: ${SOLR_URL}/${COLLECTION_NAME}${NC}"
    echo ""
    echo -e "${BLUE}📝 Để insert data, chạy:${NC}"
    echo "   ./03_insert/insert_data.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Collection ${COLLECTION_NAME} có lỗi khi load — xem initFailures:${NC}"
    echo "$STATUS_RESPONSE"
    echo ""
    echo -e "${YELLOW}   Xem log chi tiết: docker logs ${CONTAINER_NAME} --tail 50${NC}"
    exit 1
fi
