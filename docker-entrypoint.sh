#!/bin/bash
set -e

CORE_NAME="${CORE_NAME:-my_core}"
DATA_FILE="${DATA_FILE:-/opt/solr/data/exported_data_no_version.json}"
SOLR_URL="http://localhost:8983/solr"
EMBEDDED_DATA_PATH="/opt/solr/embedded_data/var/solr"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Khởi động Solr với data được đóng gói sẵn"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Bước 0: Copy embedded data vào /var/solr nếu chưa có data
if [ -d "$EMBEDDED_DATA_PATH" ] && [ -n "$(ls -A "$EMBEDDED_DATA_PATH" 2>/dev/null)" ]; then
    # Kiểm tra xem /var/solr có data cores/collections đầy đủ hay chưa
    HAS_COMPLETE_DATA=false
    if [ -d "/var/solr/data" ] && [ -n "$(ls -A /var/solr/data 2>/dev/null)" ]; then
        # Kiểm tra xem có core nào với config files đầy đủ không
        for CORE_DIR in /var/solr/data/*/; do
            if [ -d "$CORE_DIR" ] && [ -d "$CORE_DIR/conf" ] && [ -f "$CORE_DIR/conf/solrconfig.xml" ]; then
                HAS_COMPLETE_DATA=true
                break
            fi
        done
    fi
    
    if [ "$HAS_COMPLETE_DATA" = false ]; then
        echo "📋 Bước 0: Phát hiện data embedded, đang copy vào /var/solr..."
        echo "   Source: $EMBEDDED_DATA_PATH"
        echo "   Destination: /var/solr"
        
        # Tạo thư mục nếu chưa có
        mkdir -p /var/solr 2>/dev/null || true
        
        # Copy data (chạy với quyền hiện tại, sau đó fix permissions)
        if cp -a "$EMBEDDED_DATA_PATH/." /var/solr/ 2>/dev/null; then
            echo "   ✅ Copy thành công"
        else
            # Thử với sudo nếu có
            if command -v sudo > /dev/null 2>&1 && sudo -n true 2>/dev/null; then
                sudo cp -a "$EMBEDDED_DATA_PATH/." /var/solr/
                echo "   ✅ Copy thành công với sudo"
            else
                echo "   ⚠️  Copy failed, thử cách khác..."
                # Fallback: Copy từng phần
                mkdir -p /var/solr/data /var/solr/logs 2>/dev/null
                if [ -d "$EMBEDDED_DATA_PATH/data" ]; then
                    cp -a "$EMBEDDED_DATA_PATH/data/." /var/solr/data/ 2>/dev/null || true
                fi
                if [ -d "$EMBEDDED_DATA_PATH/logs" ]; then
                    cp -a "$EMBEDDED_DATA_PATH/logs/." /var/solr/logs/ 2>/dev/null || true
                fi
            fi
        fi
        
        # Set permissions
        chown -R solr:solr /var/solr 2>/dev/null || \
        (command -v sudo > /dev/null 2>&1 && sudo chown -R solr:solr /var/solr 2>/dev/null) || true
        
        echo "✅ Đã copy embedded data vào /var/solr"
        
        # Verify copied data
        if [ -d "/var/solr/data" ] && [ -n "$(ls -A /var/solr/data 2>/dev/null)" ]; then
            echo "   📊 Số cores/collections sau khi copy: $(ls -d /var/solr/data/*/ 2>/dev/null | wc -l)"
        fi
    else
        echo "✅ /var/solr đã có data cores đầy đủ, bỏ qua copy embedded data"
    fi
else
    echo "ℹ️  Không có embedded data tại $EMBEDDED_DATA_PATH"
fi

# Bước 1: Tạo core trước khi khởi động Solr (chỉ nếu chưa có)
if [ ! -d "/var/solr/${CORE_NAME}" ]; then
    echo "📋 Bước 1: Tạo core ${CORE_NAME}..."
    solr-precreate "${CORE_NAME}" /opt/solr/server/solr/configsets/wordcloud_config
else
    echo "✅ Core ${CORE_NAME} đã tồn tại, bỏ qua tạo core"
fi

# Bước 2: Khởi động Solr
echo ""
echo "📋 Bước 2: Khởi động Solr..."
solr start

# Đợi Solr khởi động
echo "   Đợi Solr khởi động..."
for i in {1..60}; do
    if curl -s "${SOLR_URL}/admin/ping" > /dev/null 2>&1; then
        echo "   ✅ Solr đã sẵn sàng"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "   ❌ Solr không khởi động được sau 60 lần thử"
        exit 1
    fi
    sleep 2
done

# Bước 3: Kiểm tra và import data nếu core còn trống
echo ""
echo "📋 Bước 3: Kiểm tra data trong core..."
DOC_COUNT=$(curl -s "${SOLR_URL}/${CORE_NAME}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*' || echo "0")

if [ "$DOC_COUNT" = "0" ] || [ -z "$DOC_COUNT" ]; then
    if [ -f "$DATA_FILE" ]; then
        echo "   📥 Core còn trống, đang import data từ ${DATA_FILE}..."
        echo "   ⏳ Quá trình này có thể mất vài phút với file lớn..."
        
        # Import data
        RESPONSE=$(curl -s -w "\n%{http_code}" --max-time 600 -X POST \
            "${SOLR_URL}/${CORE_NAME}/update?commit=true&overwrite=true" \
            -H 'Content-Type: application/json' \
            -d @"${DATA_FILE}")
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            # Đếm lại số documents
            NEW_COUNT=$(curl -s "${SOLR_URL}/${CORE_NAME}/select?q=*:*&rows=0" | grep -o '"numFound":[0-9]*' | grep -o '[0-9]*' || echo "0")
            echo "   ✅ Đã import data thành công!"
            echo "   📊 Tổng số documents: ${NEW_COUNT}"
        else
            echo "   ⚠️  Lỗi khi import data (HTTP ${HTTP_CODE})"
            echo "   Response: $(echo "$RESPONSE" | sed '$d')"
        fi
    else
        echo "   ⚠️  File data không tồn tại: ${DATA_FILE}"
        echo "   Core sẽ được tạo nhưng không có data"
    fi
else
    echo "   ✅ Core đã có ${DOC_COUNT} documents, bỏ qua import"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Solr đã sẵn sàng!"
echo "   Core: ${CORE_NAME}"
echo "   URL: http://localhost:8983/solr"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Giữ container chạy - chờ Solr process
tail -f /var/solr/logs/solr.log

