#!/bin/bash

# Script tổng hợp cài đặt solr-vn-tokenizer plugin
# Tự động thực hiện: build plugin, copy jar files, setup Docker container, và load plugin

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Biến cấu hình
CONTAINER_NAME="solr_local"
CORE_NAME="my_core"
SOLR_URL="http://localhost:8983/solr"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${CYAN}🚀 Cài đặt tự động solr-vn-tokenizer Plugin${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# BƯỚC 1: Build plugin (nếu chưa build)
# ============================================================
echo -e "${BLUE}📋 Bước 1: Kiểm tra và build plugin...${NC}"
PLUGIN_JAR="solr-vn-tokenizer/target/solr-vn-analyzer-1.0.jar"
if [ ! -f "$PLUGIN_JAR" ]; then
    echo -e "${YELLOW}   ⚠️  Plugin chưa được build!${NC}"
    echo -e "${YELLOW}   🔨 Đang build plugin...${NC}"
    cd solr-vn-tokenizer
    mvn package
    if [ $? -ne 0 ]; then
        echo -e "${RED}   ❌ Lỗi khi build plugin!${NC}"
        echo -e "${RED}   💡 Kiểm tra: Java và Maven đã được cài đặt chưa?${NC}"
        exit 1
    fi
    cd ..
    echo -e "${GREEN}   ✅ Plugin đã được build thành công${NC}"
else
    echo -e "${GREEN}   ✅ Plugin đã được build${NC}"
fi
echo ""

# ============================================================
# BƯỚC 2: Copy jar files từ target vào lib/
# ============================================================
echo -e "${BLUE}📋 Bước 2: Copy jar files vào thư mục lib/...${NC}"

# Tạo thư mục lib nếu chưa có
mkdir -p lib

# Danh sách các jar files cần copy
JAR_FILES=(
    "solr-vn-tokenizer/target/solr-vn-analyzer-1.0.jar"
    "solr-vn-tokenizer/target/lib/VnCoreNLP-1.1.1.jar"
    "solr-vn-tokenizer/target/lib/commons-io-2.7.jar"
    "solr-vn-tokenizer/target/lib/activation-1.1.1.jar"
)

# Copy các jar files chính
for jar in "${JAR_FILES[@]}"; do
    if [ -f "$jar" ]; then
        filename=$(basename "$jar")
        cp "$jar" lib/
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}   ✅ Đã copy $filename${NC}"
        else
            echo -e "${RED}   ❌ Lỗi khi copy $filename${NC}"
            exit 1
        fi
    else
        echo -e "${RED}   ❌ Không tìm thấy file: $jar${NC}"
        exit 1
    fi
done

# Copy các jar files jaxb-*
echo -e "${YELLOW}   📄 Copying jaxb-*.jar files...${NC}"
JAXB_COUNT=0
for jar in solr-vn-tokenizer/target/lib/jaxb-*.jar; do
    if [ -f "$jar" ]; then
        filename=$(basename "$jar")
        cp "$jar" lib/
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}   ✅ Đã copy $filename${NC}"
            ((JAXB_COUNT++))
        fi
    fi
done

if [ $JAXB_COUNT -eq 0 ]; then
    echo -e "${YELLOW}   ⚠️  Không tìm thấy jaxb-*.jar files${NC}"
fi

echo ""
echo -e "${GREEN}✅ Đã copy tất cả jar files vào lib/${NC}"
echo -e "${CYAN}   📦 Tổng số jar files: $(ls -1 lib/*.jar 2>/dev/null | wc -l)${NC}"
echo ""

# ============================================================
# BƯỚC 3: Kiểm tra và khởi động Docker container
# ============================================================
echo -e "${BLUE}📋 Bước 3: Kiểm tra Docker container...${NC}"

# Kiểm tra Docker có đang chạy không
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}   ❌ Docker không đang chạy!${NC}"
    echo -e "${YELLOW}   💡 Hãy khởi động Docker và thử lại${NC}"
    exit 1
fi

# Kiểm tra container có đang chạy không
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${YELLOW}   ⚠️  Container $CONTAINER_NAME không đang chạy${NC}"
    echo -e "${YELLOW}   🚀 Đang khởi động container...${NC}"
    docker-compose up -d
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}   ❌ Lỗi khi khởi động container!${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}   ⏳ Đợi Solr khởi động (20 giây)...${NC}"
    sleep 20
    
    # Kiểm tra Solr đã sẵn sàng chưa
    for i in {1..10}; do
        if curl -s "$SOLR_URL/admin/ping" > /dev/null 2>&1; then
            echo -e "${GREEN}   ✅ Solr đã sẵn sàng${NC}"
            break
        fi
        if [ $i -eq 10 ]; then
            echo -e "${RED}   ❌ Solr chưa sẵn sàng sau 10 lần thử${NC}"
            echo -e "${YELLOW}   💡 Kiểm tra logs: docker logs $CONTAINER_NAME${NC}"
            exit 1
        fi
        sleep 3
    done
else
    echo -e "${GREEN}   ✅ Container $CONTAINER_NAME đang chạy${NC}"
fi
echo ""

# ============================================================
# BƯỚC 4: Copy jar files vào container
# ============================================================
echo -e "${BLUE}📋 Bước 4: Copy jar files vào container Solr...${NC}"

# Kiểm tra thư mục ext/ có jar files không
if [ ! -d "lib" ] || [ -z "$(ls -A lib/*.jar 2>/dev/null)" ]; then
    echo -e "${RED}   ❌ Không tìm thấy jar files trong thư mục lib/${NC}"
    exit 1
fi

# Copy các jar files từ ext/ vào lib/ trong container
echo -e "${YELLOW}   📦 Đang copy jar files vào container...${NC}"
docker exec -u root "$CONTAINER_NAME" sh -c "cp /opt/solr/server/lib/ext/*.jar /opt/solr/server/lib/ 2>&1"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✅ Đã copy jar files vào container thành công${NC}"
    
    # Liệt kê các jar files đã copy
    echo -e "${CYAN}   📋 Các jar files đã được copy:${NC}"
    docker exec "$CONTAINER_NAME" sh -c "ls -lh /opt/solr/server/lib/*.jar 2>/dev/null | grep -E '(solr-vn|VnCoreNLP|commons-io|activation|jaxb)'" | while read line; do
        echo -e "${CYAN}      $line${NC}"
    done
else
    echo -e "${RED}   ❌ Lỗi khi copy jar files vào container${NC}"
    exit 1
fi

# Kiểm tra và tải commons-logging.jar nếu thiếu
echo -e "${YELLOW}   🔍 Kiểm tra commons-logging.jar...${NC}"
docker exec -u root "$CONTAINER_NAME" sh -c "
    if [ ! -f /opt/solr/server/lib/commons-logging-1.2.jar ]; then
        echo '⚠️  commons-logging.jar không tìm thấy, đang tải...'
        curl -s -o /opt/solr/server/lib/commons-logging-1.2.jar https://repo1.maven.org/maven2/commons-logging/commons-logging/1.2/commons-logging-1.2.jar
        if [ \$? -eq 0 ]; then
            echo '✅ Đã tải commons-logging-1.2.jar'
        else
            echo '❌ Lỗi khi tải commons-logging.jar'
            exit 1
        fi
    else
        echo '✅ commons-logging-1.2.jar đã có'
    fi
" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}   ⚠️  Không thể tải commons-logging.jar, nhưng có thể tiếp tục${NC}"
fi
echo ""

# ============================================================
# BƯỚC 5: Restart Solr để load plugin
# ============================================================
echo -e "${BLUE}📋 Bước 5: Restart Solr để load plugin...${NC}"
echo -e "${YELLOW}   🔄 Đang restart Solr...${NC}"
docker-compose restart solr

if [ $? -ne 0 ]; then
    echo -e "${RED}   ❌ Lỗi khi restart Solr!${NC}"
    exit 1
fi

echo -e "${YELLOW}   ⏳ Đợi Solr khởi động lại (20 giây)...${NC}"
sleep 20

# Kiểm tra Solr đã sẵn sàng chưa
for i in {1..10}; do
    if curl -s "$SOLR_URL/admin/ping" > /dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Solr đã khởi động lại thành công${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${RED}   ❌ Solr chưa sẵn sàng sau 10 lần thử${NC}"
        echo -e "${YELLOW}   💡 Kiểm tra logs: docker logs $CONTAINER_NAME${NC}"
        exit 1
    fi
    sleep 3
done
echo ""

# ============================================================
# BƯỚC 6: Kiểm tra plugin đã load thành công
# ============================================================
echo -e "${BLUE}📋 Bước 6: Kiểm tra plugin đã load thành công...${NC}"

# Kiểm tra fieldType text_cloud_vn có trong schema không
echo -e "${YELLOW}   🔍 Kiểm tra fieldType text_cloud_vn trong schema...${NC}"
SCHEMA_CHECK=$(curl -s "$SOLR_URL/$CORE_NAME/admin/luke?show=schema&fl=*&wt=json" 2>/dev/null | grep -i "text_cloud_vn" | wc -l)

if [ "$SCHEMA_CHECK" -gt 0 ]; then
    echo -e "${GREEN}   ✅ FieldType text_cloud_vn đã có trong schema${NC}"
else
    echo -e "${YELLOW}   ⚠️  FieldType text_cloud_vn chưa có trong schema${NC}"
    echo -e "${YELLOW}   💡 Hãy kiểm tra file: wordcloud_config/conf/managed-schema.xml${NC}"
fi

# Test analyzer
echo -e "${YELLOW}   🧪 Test VietnameseAnalyzer...${NC}"
TEST_TEXT="Tôi đang học lập trình"
TEST_RESULT=$(curl -s "$SOLR_URL/$CORE_NAME/analysis/field?analysis.fieldtype=text_cloud_vn&analysis.fieldvalue=$TEST_TEXT" 2>/dev/null)

if echo "$TEST_RESULT" | grep -q "VietnameseAnalyzer\|org.apache.lucene.analysis.vi"; then
    echo -e "${GREEN}   ✅ VietnameseAnalyzer đã được load thành công${NC}"
elif echo "$TEST_RESULT" | grep -q "ClassNotFoundException\|NoClassDefFoundError"; then
    echo -e "${RED}   ❌ Lỗi: Plugin chưa được load đúng cách${NC}"
    echo -e "${YELLOW}   💡 Kiểm tra logs: docker logs $CONTAINER_NAME | grep -i error${NC}"
else
    echo -e "${YELLOW}   ⚠️  Không thể xác nhận analyzer (có thể fieldType chưa được tạo)${NC}"
fi
echo ""

# ============================================================
# TÓM TẮT
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Hoàn thành cài đặt solr-vn-tokenizer!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${CYAN}📝 Tóm tắt:${NC}"
echo -e "   ✅ Plugin đã được build"
echo -e "   ✅ Jar files đã được copy vào lib/"
echo -e "   ✅ Jar files đã được copy vào container"
echo -e "   ✅ Solr đã được restart"
echo ""
echo -e "${BLUE}📚 Các bước tiếp theo:${NC}"
echo ""
echo -e "${YELLOW}1. Sử dụng fieldType text_cloud_vn trong schema:${NC}"
echo "   <field name=\"content_vn\" type=\"text_cloud_vn\" indexed=\"true\" stored=\"true\"/>"
echo ""
echo -e "${YELLOW}2. Test analyzer:${NC}"
echo "   curl \"$SOLR_URL/$CORE_NAME/analysis/field?analysis.fieldtype=text_cloud_vn&analysis.fieldvalue=Tôi%20đang%20học\""
echo ""
echo -e "${YELLOW}3. Xem schema:${NC}"
echo "   curl \"$SOLR_URL/$CORE_NAME/schema/fieldtypes\""
echo ""
echo -e "${CYAN}💡 Lưu ý:${NC}"
echo "   - Sau mỗi lần restart container, chạy lại script này để copy jar files"
echo "   - Hoặc chạy riêng: docker exec -u root $CONTAINER_NAME sh -c \"cp /opt/solr/server/lib/ext/*.jar /opt/solr/server/lib/\""
echo ""

