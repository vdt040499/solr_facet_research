#!/bin/bash

# Script để build và push Solr image lên Docker Hub
# Có thể commit container với data hoặc build từ Dockerfile

# Màu sắc
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cấu hình
DOCKER_USERNAME="tanvd040499"
IMAGE_NAME="${IMAGE_NAME:-solr-vn-wordcloud}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
CONTAINER_NAME="${CONTAINER_NAME:-solr_local}"
BUILD_MODE="${BUILD_MODE:-commit}"  # commit: commit container, dockerfile: build từ Dockerfile, skip: skip build

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🐳 Build và Push Solr Image lên Docker Hub${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Kiểm tra Docker Hub username
if [ -z "$DOCKER_USERNAME" ]; then
    echo -e "${YELLOW}⚠️  DOCKER_USERNAME chưa được set${NC}"
    read -p "Nhập Docker Hub username: " DOCKER_USERNAME
    export DOCKER_USERNAME
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo -e "${BLUE}📋 Thông tin:${NC}"
echo "   Docker Hub Username: $DOCKER_USERNAME"
echo "   Image Name: $IMAGE_NAME"
echo "   Tag: $IMAGE_TAG"
echo "   Full Image Name: $FULL_IMAGE_NAME"
echo "   Build Mode: $BUILD_MODE"
echo "   Container Name: $CONTAINER_NAME"
echo ""

# Bước 1: Build hoặc commit container
if [ "$BUILD_MODE" = "commit" ]; then
    echo -e "${BLUE}📦 Bước 1: Commit container với data...${NC}"
    
    # Kiểm tra container có tồn tại không
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}❌ Container '$CONTAINER_NAME' không tồn tại!${NC}"
        echo -e "${YELLOW}💡 Các container có sẵn:${NC}"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | head -10
        echo ""
        echo -e "${YELLOW}💡 Cách sử dụng:${NC}"
        echo "   CONTAINER_NAME=your_container_name ./build_and_push.sh"
        echo "   hoặc BUILD_MODE=dockerfile để build từ Dockerfile"
        exit 1
    fi
    
    # Lấy image của container
    CONTAINER_IMAGE=$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}' 2>/dev/null)
    
    # Kiểm tra container có đang chạy không
    CONTAINER_STATUS=$(docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$" && echo "running" || echo "stopped")
    
    # Tìm volumes được mount vào container
    echo -e "${BLUE}   Đang tìm volumes được mount vào container...${NC}"
    VOLUME_MOUNTS=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}:{{.Destination}}{{println}}{{end}}{{end}}' 2>/dev/null)
    
    if [ -n "$VOLUME_MOUNTS" ]; then
        echo -e "${YELLOW}   ⚠️  Phát hiện volumes được mount vào container${NC}"
        echo -e "${YELLOW}   💡 Data trong volumes sẽ KHÔNG được commit vào image${NC}"
        echo -e "${BLUE}   💡 Đang copy data từ volumes vào container mới...${NC}"
        
        # Tạo container tạm từ image của container gốc
        TEMP_CONTAINER_NAME="temp_commit_${CONTAINER_NAME}_$$"
        echo -e "${BLUE}      Tạo container tạm: $TEMP_CONTAINER_NAME${NC}"
        
        # Commit container gốc trước để có image snapshot
        TEMP_IMAGE_NAME="${FULL_IMAGE_NAME}_temp_$$"
        docker commit "$CONTAINER_NAME" "$TEMP_IMAGE_NAME" > /dev/null 2>&1
        
        # Tạo container tạm từ image snapshot (phải chạy để có thể exec)
        docker run -d --name "$TEMP_CONTAINER_NAME" "$TEMP_IMAGE_NAME" sleep 3600 > /dev/null 2>&1
        
        if ! docker ps --format "{{.Names}}" | grep -q "^${TEMP_CONTAINER_NAME}$"; then
            echo -e "${RED}   ❌ Không thể tạo và chạy container tạm${NC}"
            docker rm -f "$TEMP_CONTAINER_NAME" > /dev/null 2>&1
            docker rmi "$TEMP_IMAGE_NAME" > /dev/null 2>&1
            exit 1
        fi
        
        echo -e "${GREEN}      ✅ Container tạm đã được tạo và đang chạy${NC}"
        
        # Copy data từ volumes vào container tạm (vào thư mục embedded, không phải mount point)
        # Parse volume mounts (tránh subshell trong while loop)
        IFS=$'\n'
        for VOLUME_LINE in $VOLUME_MOUNTS; do
            VOLUME_NAME=$(echo "$VOLUME_LINE" | cut -d: -f1)
            MOUNT_PATH=$(echo "$VOLUME_LINE" | cut -d: -f2-)
            
            if [ -n "$VOLUME_NAME" ] && [ -n "$MOUNT_PATH" ]; then
                echo -e "${BLUE}      Copying data từ volume '$VOLUME_NAME' -> embedded location...${NC}"
                
                # Sử dụng helper container để tar và copy
                # Copy vào /opt/solr/embedded_data${MOUNT_PATH} thay vì ${MOUNT_PATH} (tránh mount point)
                EMBEDDED_DEST="/opt/solr/embedded_data${MOUNT_PATH}"
                HELPER_NAME="helper_copy_${VOLUME_NAME}_$$"
                
                # Tạo helper container để tar data từ volume
                docker run --name "$HELPER_NAME" \
                    -v "$VOLUME_NAME":/source:ro \
                    alpine sh -c "tar czf /tmp/data.tar.gz -C /source ." > /dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    # Copy tar file vào container tạm
                    if docker cp "$HELPER_NAME:/tmp/data.tar.gz" "$TEMP_CONTAINER_NAME:/tmp/data.tar.gz" > /dev/null 2>&1; then
                        # Extract vào embedded location trong container tạm
                        if docker exec -u root "$TEMP_CONTAINER_NAME" sh -c "mkdir -p ${EMBEDDED_DEST} && cd ${EMBEDDED_DEST} && tar xzf /tmp/data.tar.gz && rm -f /tmp/data.tar.gz && chown -R solr:solr /opt/solr/embedded_data" > /dev/null 2>&1; then
                            echo -e "${GREEN}      ✅ Đã copy data từ volume '$VOLUME_NAME' vào embedded location${NC}"
                        else
                            echo -e "${YELLOW}      ⚠️  Không thể extract data trong container${NC}"
                        fi
                    else
                        echo -e "${YELLOW}      ⚠️  Không thể copy tar file vào container${NC}"
                    fi
                else
                    echo -e "${YELLOW}      ⚠️  Không thể tạo tar từ volume $VOLUME_NAME${NC}"
                fi
                
                # Cleanup helper
                docker rm -f "$HELPER_NAME" > /dev/null 2>&1
            fi
        done
        unset IFS
        
        # Copy bind mounts (configsets, etc.) vào container tạm
        BIND_MOUNTS=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{println}}{{end}}{{end}}' 2>/dev/null)
        
        if [ -n "$BIND_MOUNTS" ]; then
            echo -e "${BLUE}      Copying bind mounts (configsets, etc.) vào container tạm...${NC}"
            IFS=$'\n'
            for BIND_LINE in $BIND_MOUNTS; do
                BIND_SOURCE=$(echo "$BIND_LINE" | cut -d: -f1)
                BIND_DEST=$(echo "$BIND_LINE" | cut -d: -f2-)
                
                # Xử lý đường dẫn Windows (convert \\ thành /)
                BIND_SOURCE=$(echo "$BIND_SOURCE" | sed 's|\\\\|/|g' | sed 's|C:|/c|g' | sed 's|^/c/|/c/|')
                
                # Convert Windows path format cho docker cp
                if [[ "$BIND_SOURCE" =~ ^[A-Z]: ]]; then
                    # Windows absolute path (C:\Users\...)
                    BIND_SOURCE_WIN="$BIND_SOURCE"
                elif [[ "$BIND_SOURCE" =~ ^/c/ ]] || [[ "$BIND_SOURCE" =~ ^/C/ ]]; then
                    # Git Bash format (/c/Users/...)
                    BIND_SOURCE_WIN="$(echo "$BIND_SOURCE" | sed 's|^/c/|C:/|' | sed 's|^/C/|C:/|')"
                else
                    # Relative path hoặc Unix path
                    BIND_SOURCE_WIN="$BIND_SOURCE"
                fi
                
                if [ -n "$BIND_SOURCE" ] && [ -n "$BIND_DEST" ]; then
                    # Kiểm tra thư mục tồn tại (thử cả 2 format)
                    if [ -d "$BIND_SOURCE" ] || [ -d "$BIND_SOURCE_WIN" ]; then
                        echo -e "${BLUE}        Copying $BIND_SOURCE -> $BIND_DEST...${NC}"
                        
                        # Sử dụng tar method (ổn định hơn trên Windows)
                        HELPER_BIND="helper_bind_${CONTAINER_NAME}_$$"
                        
                        # Thử mount với cả 2 format đường dẫn
                        TAR_SUCCESS=false
                        if docker run --rm --name "$HELPER_BIND" -v "${BIND_SOURCE}:/source:ro" alpine sh -c "cd /source && tar czf /tmp/bind.tar.gz . && ls -lh /tmp/bind.tar.gz" > /dev/null 2>&1; then
                            # Copy tar file vào container tạm
                            if docker cp "${HELPER_BIND}:/tmp/bind.tar.gz" "$TEMP_CONTAINER_NAME:/tmp/bind.tar.gz" 2>/dev/null || \
                               docker exec -u root "$TEMP_CONTAINER_NAME" sh -c "mkdir -p ${BIND_DEST}" > /dev/null 2>&1; then
                                TAR_SUCCESS=true
                            fi
                        elif docker run --rm --name "$HELPER_BIND" -v "${BIND_SOURCE_WIN}:/source:ro" alpine sh -c "cd /source && tar czf /tmp/bind.tar.gz . && ls -lh /tmp/bind.tar.gz" > /dev/null 2>&1; then
                            if docker cp "${HELPER_BIND}:/tmp/bind.tar.gz" "$TEMP_CONTAINER_NAME:/tmp/bind.tar.gz" 2>/dev/null; then
                                TAR_SUCCESS=true
                            fi
                        fi
                        
                        # Fallback: thử docker cp trực tiếp
                        if [ "$TAR_SUCCESS" = false ]; then
                            if docker cp "$BIND_SOURCE/." "$TEMP_CONTAINER_NAME:${BIND_DEST}/" > /dev/null 2>&1 || \
                               docker cp "$BIND_SOURCE_WIN/." "$TEMP_CONTAINER_NAME:${BIND_DEST}/" > /dev/null 2>&1; then
                                TAR_SUCCESS=true
                            fi
                        fi
                        
                        # Extract và verify
                        if [ "$TAR_SUCCESS" = true ]; then
                            if docker exec -u root "$TEMP_CONTAINER_NAME" sh -c "mkdir -p ${BIND_DEST} && cd ${BIND_DEST} && tar xzf /tmp/bind.tar.gz 2>/dev/null && rm -f /tmp/bind.tar.gz && chown -R solr:solr ${BIND_DEST}" > /dev/null 2>&1 || \
                               docker exec "$TEMP_CONTAINER_NAME" test -d "${BIND_DEST}/conf" 2>/dev/null; then
                                
                                # Verify copy thành công
                                if docker exec "$TEMP_CONTAINER_NAME" test -d "${BIND_DEST}/conf" 2>/dev/null; then
                                    FILE_COUNT=$(docker exec "$TEMP_CONTAINER_NAME" find "${BIND_DEST}" -type f 2>/dev/null | wc -l | tr -d ' ')
                                    echo -e "${GREEN}        ✅ Đã copy ${BIND_DEST} (${FILE_COUNT} files, có conf folder)${NC}"
                                else
                                    echo -e "${YELLOW}        ⚠️  Đã copy nhưng không có conf folder${NC}"
                                fi
                            else
                                echo -e "${YELLOW}        ⚠️  Không thể extract trong container${NC}"
                            fi
                        else
                            echo -e "${RED}        ❌ Không thể copy ${BIND_DEST} (thử cả tar và docker cp đều fail)${NC}"
                            echo -e "${YELLOW}        💡 Kiểm tra đường dẫn: $BIND_SOURCE hoặc $BIND_SOURCE_WIN${NC}"
                        fi
                        
                        docker rm -f "$HELPER_BIND" > /dev/null 2>&1
                    else
                        echo -e "${YELLOW}        ⚠️  Thư mục không tồn tại: $BIND_SOURCE${NC}"
                    fi
                fi
            done
            unset IFS
        fi
        
        # Copy entrypoint script vào container tạm nếu chưa có
        if [ -f "docker-entrypoint.sh" ]; then
            echo -e "${BLUE}      Copying entrypoint script vào container tạm...${NC}"
            docker cp docker-entrypoint.sh "$TEMP_CONTAINER_NAME:/opt/solr/docker-entrypoint.sh" > /dev/null 2>&1
            docker exec -u root "$TEMP_CONTAINER_NAME" chmod +x /opt/solr/docker-entrypoint.sh > /dev/null 2>&1
            docker exec -u root "$TEMP_CONTAINER_NAME" chown solr:solr /opt/solr/docker-entrypoint.sh > /dev/null 2>&1
            echo -e "${GREEN}      ✅ Đã copy entrypoint script${NC}"
        else
            echo -e "${YELLOW}      ⚠️  Không tìm thấy docker-entrypoint.sh trong thư mục hiện tại${NC}"
        fi
        
        # Lấy ENTRYPOINT và CMD từ container gốc để giữ lại khi commit
        ORIGINAL_ENTRYPOINT=$(docker inspect "$CONTAINER_NAME" --format '{{json .Config.Entrypoint}}' 2>/dev/null || echo '["/opt/solr/docker-entrypoint.sh"]')
        ORIGINAL_CMD=$(docker inspect "$CONTAINER_NAME" --format '{{json .Config.Cmd}}' 2>/dev/null || echo 'null')
        
        # Nếu container gốc không có entrypoint, sử dụng entrypoint script của chúng ta
        if [ "$ORIGINAL_ENTRYPOINT" = "[]" ] || [ -z "$ORIGINAL_ENTRYPOINT" ] || [ "$ORIGINAL_ENTRYPOINT" = "null" ]; then
            ORIGINAL_ENTRYPOINT='["/opt/solr/docker-entrypoint.sh"]'
        fi
        
        # Đảm bảo entrypoint script tồn tại trong container tạm
        if ! docker exec "$TEMP_CONTAINER_NAME" test -f /opt/solr/docker-entrypoint.sh 2>/dev/null; then
            echo -e "${YELLOW}      ⚠️  Entrypoint script không tồn tại trong container tạm, sử dụng entrypoint mặc định của Solr${NC}"
            ORIGINAL_ENTRYPOINT='["docker-entrypoint.sh"]'
        fi
        
        # Commit container tạm thành image với đúng ENTRYPOINT
        echo -e "${BLUE}   Đang commit container tạm với data và đúng ENTRYPOINT...${NC}"
        if [ "$ORIGINAL_CMD" != "null" ] && [ -n "$ORIGINAL_CMD" ]; then
            docker commit \
                --change "ENTRYPOINT ${ORIGINAL_ENTRYPOINT}" \
                --change "CMD ${ORIGINAL_CMD}" \
                "$TEMP_CONTAINER_NAME" "$FULL_IMAGE_NAME" > /dev/null 2>&1
        else
            docker commit \
                --change "ENTRYPOINT ${ORIGINAL_ENTRYPOINT}" \
                "$TEMP_CONTAINER_NAME" "$FULL_IMAGE_NAME" > /dev/null 2>&1
        fi
        
        # Cleanup
        docker rm -f "$TEMP_CONTAINER_NAME" > /dev/null 2>&1
        docker rmi "$TEMP_IMAGE_NAME" > /dev/null 2>&1
        
        if docker images "$FULL_IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$FULL_IMAGE_NAME"; then
            echo -e "${GREEN}✅ Commit thành công! Image đã được tạo với data từ volumes${NC}"
            
            # Verify image có configset và embedded data
            echo -e "${BLUE}   Đang verify image...${NC}"
            VERIFY_CONTAINER="verify_${CONTAINER_NAME}_$$"
            docker run -d --name "$VERIFY_CONTAINER" "$FULL_IMAGE_NAME" sleep 60 > /dev/null 2>&1
            
            if docker ps --format "{{.Names}}" | grep -q "^${VERIFY_CONTAINER}$"; then
                # Check configset
                if docker exec "$VERIFY_CONTAINER" test -d /opt/solr/server/solr/configsets/wordcloud_config/conf 2>/dev/null; then
                    CONFIG_FILES=$(docker exec "$VERIFY_CONTAINER" find /opt/solr/server/solr/configsets/wordcloud_config -type f 2>/dev/null | wc -l | tr -d ' ')
                    echo -e "${GREEN}   ✅ Configset có đầy đủ (${CONFIG_FILES} files)${NC}"
                else
                    echo -e "${RED}   ❌ Configset KHÔNG có conf folder!${NC}"
                fi
                
                # Check embedded data
                if docker exec "$VERIFY_CONTAINER" test -d /opt/solr/embedded_data/var/solr 2>/dev/null; then
                    DATA_SIZE=$(docker exec "$VERIFY_CONTAINER" du -sh /opt/solr/embedded_data/var/solr 2>/dev/null | cut -f1)
                    echo -e "${GREEN}   ✅ Embedded data có đầy đủ (${DATA_SIZE})${NC}"
                else
                    echo -e "${YELLOW}   ⚠️  Embedded data không có${NC}"
                fi
                
                # Check entrypoint script
                if docker exec "$VERIFY_CONTAINER" test -f /opt/solr/docker-entrypoint.sh 2>/dev/null; then
                    echo -e "${GREEN}   ✅ Entrypoint script có đầy đủ${NC}"
                else
                    echo -e "${RED}   ❌ Entrypoint script KHÔNG có!${NC}"
                fi
                
                docker rm -f "$VERIFY_CONTAINER" > /dev/null 2>&1
            fi
        else
            echo -e "${RED}❌ Commit failed!${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}   ✅ Không có volumes được mount, data đã ở trong container filesystem${NC}"
        
        # Commit container gốc (giữ nguyên ENTRYPOINT/CMD)
        echo -e "${BLUE}   Đang commit container...${NC}"
        docker commit "$CONTAINER_NAME" "$FULL_IMAGE_NAME"
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Commit failed!${NC}"
            exit 1
        fi
        
        # Đảm bảo ENTRYPOINT đúng (container gốc có thể không có entrypoint script)
        docker commit \
            --change 'ENTRYPOINT ["/opt/solr/docker-entrypoint.sh"]' \
            "$CONTAINER_NAME" "$FULL_IMAGE_NAME" > /dev/null 2>&1
        
        echo -e "${GREEN}✅ Commit thành công! Image đã được tạo với tất cả data trong container${NC}"
    fi
    
elif [ "$BUILD_MODE" = "dockerfile" ]; then
    echo -e "${BLUE}📦 Bước 1: Build Docker image từ Dockerfile...${NC}"
    docker build -t "$FULL_IMAGE_NAME" .
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Build failed!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Build thành công!${NC}"
    
elif [ "$BUILD_MODE" = "skip" ]; then
    echo -e "${BLUE}📦 Bước 1: Skip build, sử dụng image hiện có...${NC}"
    
    # Kiểm tra image có tồn tại không
    if ! docker images "$FULL_IMAGE_NAME" --format "{{.Repository}}:{{.Tag}}" | grep -q "$FULL_IMAGE_NAME"; then
        echo -e "${RED}❌ Image $FULL_IMAGE_NAME không tồn tại!${NC}"
        echo -e "${YELLOW}💡 Các image có sẵn:${NC}"
        docker images | grep "$IMAGE_NAME" || echo "   Không có image nào"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Image $FULL_IMAGE_NAME đã tồn tại${NC}"
else
    echo -e "${RED}❌ BUILD_MODE không hợp lệ: $BUILD_MODE${NC}"
    echo -e "${YELLOW}💡 BUILD_MODE có thể là: commit, dockerfile, hoặc skip${NC}"
    exit 1
fi
echo ""

# Bước 2: Kiểm tra và Login Docker Hub
echo -e "${BLUE}🔐 Bước 2: Kiểm tra login Docker Hub...${NC}"

# Kiểm tra xem đã login chưa
if ! docker info 2>/dev/null | grep -q "Username"; then
    echo -e "${YELLOW}   Chưa login, đang login...${NC}"
    echo -e "${YELLOW}   Vui lòng nhập Docker Hub password${NC}"
    docker login -u "$DOCKER_USERNAME"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Login failed!${NC}"
        echo -e "${YELLOW}💡 Thử login thủ công: docker login -u $DOCKER_USERNAME${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Login thành công!${NC}"
else
    CURRENT_USER=$(docker info 2>/dev/null | grep "Username" | awk '{print $2}')
    echo -e "${GREEN}✅ Đã login với user: $CURRENT_USER${NC}"
    if [ "$CURRENT_USER" != "$DOCKER_USERNAME" ]; then
        echo -e "${YELLOW}⚠️  Username hiện tại ($CURRENT_USER) khác với username trong script ($DOCKER_USERNAME)${NC}"
        read -p "Bạn có muốn logout và login lại với $DOCKER_USERNAME? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker logout
            docker login -u "$DOCKER_USERNAME"
            if [ $? -ne 0 ]; then
                echo -e "${RED}❌ Login failed!${NC}"
                exit 1
            fi
        fi
    fi
fi
echo ""

# Bước 3: Kiểm tra repository tồn tại
echo -e "${BLUE}📋 Bước 3: Kiểm tra repository trên Docker Hub...${NC}"
echo -e "${YELLOW}   Lưu ý: Repository sẽ được tạo tự động khi push lần đầu${NC}"
echo -e "${YELLOW}   Nếu gặp lỗi, vui lòng tạo repository tại:${NC}"
echo -e "${YELLOW}   https://hub.docker.com/repositories/new${NC}"
echo ""

# Bước 4: Push image
echo -e "${BLUE}📤 Bước 4: Push image lên Docker Hub...${NC}"
echo -e "${YELLOW}   Image: $FULL_IMAGE_NAME${NC}"
echo -e "${YELLOW}   Đang push (có thể mất vài phút)...${NC}"

docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Push failed!${NC}"
    echo ""
    echo -e "${YELLOW}💡 Các nguyên nhân có thể:${NC}"
    echo "   1. Repository chưa tồn tại trên Docker Hub"
    echo "      → Tạo tại: https://hub.docker.com/repositories/new"
    echo "      → Repository name: $IMAGE_NAME"
    echo "   2. Chưa login hoặc token hết hạn"
    echo "      → Chạy: docker login -u $DOCKER_USERNAME"
    echo "   3. Không có quyền push vào repository"
    echo "      → Kiểm tra quyền trên Docker Hub"
    echo ""
    echo -e "${BLUE}💡 Thử các bước sau:${NC}"
    echo "   1. Tạo repository trên Docker Hub:"
    echo "      https://hub.docker.com/repositories/new"
    echo "      Name: $IMAGE_NAME"
    echo "      Visibility: Public hoặc Private"
    echo ""
    echo "   2. Login lại:"
    echo "      docker logout"
    echo "      docker login -u $DOCKER_USERNAME"
    echo ""
    echo "   3. Thử push lại:"
    echo "      docker push $FULL_IMAGE_NAME"
    echo ""
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Hoàn thành!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}📦 Image đã được push:${NC}"
echo "   $FULL_IMAGE_NAME"
echo ""
echo -e "${BLUE}💡 Để sử dụng image:${NC}"
echo "   docker pull $FULL_IMAGE_NAME"
if [ "$BUILD_MODE" = "commit" ]; then
    echo "   MSYS_NO_PATHCONV=1 docker run -d -p 8983:8983 --name solr_vn $FULL_IMAGE_NAME"
else
    echo "   MSYS_NO_PATHCONV=1 docker run -d -p 8983:8983 --name solr_vn $FULL_IMAGE_NAME solr-precreate my_core /opt/solr/server/solr/configsets/wordcloud_config"
fi
echo ""
echo -e "${BLUE}💡 Các cách sử dụng script:${NC}"
echo "   1. Commit container với data (mặc định):"
echo "      ./build_and_push.sh"
echo "      hoặc: BUILD_MODE=commit CONTAINER_NAME=solr_local ./build_and_push.sh"
echo ""
echo "   2. Build từ Dockerfile:"
echo "      BUILD_MODE=dockerfile ./build_and_push.sh"
echo ""
echo "   3. Skip build (sử dụng image đã có):"
echo "      BUILD_MODE=skip ./build_and_push.sh"
echo ""

