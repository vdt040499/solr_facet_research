# Hướng dẫn Restore Backup Solr

Script này giúp restore dữ liệu từ backup folder `topic_10236681/` vào Solr collection.

## Các bước thực hiện

### 1. Đảm bảo docker-compose.yml đã mount backup folder

File `docker-compose.yml` đã được cập nhật để mount folder backup:
```yaml
- ./topic_10236681:/opt/solr/backups/topic_10236681
```

### 2. Restart Solr container để áp dụng thay đổi

```bash
docker-compose restart solr
```

Hoặc nếu Solr chưa chạy:
```bash
docker-compose up -d solr
```

Đợi khoảng 15-20 giây để Solr khởi động hoàn toàn.

### 3. Chạy script restore

```bash
./restore_backup.sh
```

Hoặc với tham số tùy chỉnh:
```bash
./restore_backup.sh <collection_name> <backup_id>
```

Ví dụ:
```bash
./restore_backup.sh topic_10236681 0
```

**Tham số:**
- `collection_name` (mặc định: `topic_10236681`): Tên collection muốn restore
- `backup_id` (mặc định: `0`): ID của backup (thường là số 0, 1, 2... tương ứng với backup_0, backup_1...)

### 4. Kiểm tra kết quả

Sau khi restore xong, bạn có thể:
- Truy cập Solr Admin UI: http://localhost:8983/solr/#/topic_10236681/query
- Kiểm tra số documents đã được restore
- Thực hiện các query test

## Lưu ý

1. **Configset**: Script sẽ tự động upload configset `topic_v3` từ backup nếu chưa tồn tại
2. **Collection đã tồn tại**: Nếu collection đã tồn tại, script sẽ hỏi bạn có muốn xóa và restore lại không
3. **Thời gian restore**: Tùy vào kích thước backup, quá trình restore có thể mất vài phút
4. **Backup location**: Backup folder phải được mount vào container tại `/opt/solr/backups/topic_10236681`

## Troubleshooting

### Lỗi: "Không tìm thấy backup folder"
- Kiểm tra docker-compose.yml đã mount folder chưa
- Restart Solr container sau khi cập nhật docker-compose.yml

### Lỗi: "Collection không tồn tại"
- Script sẽ tự động tạo collection, nhưng nếu configset chưa có, có thể cần upload configset thủ công

### Lỗi: "Configset không tồn tại"
- Script sẽ cố gắng upload configset từ backup, nhưng nếu thất bại, bạn có thể upload thủ công:
```bash
docker exec solr_local solr zk upconfig -n topic_v3 -d /opt/solr/backups/topic_10236681/zk_backup_0/configs/topic_v3
```

