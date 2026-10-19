# Solr Search Text Facet

Test tách cụm từ (wordcloud) trên **Solr 9.11** bằng plugin `VietnameseTokenizer`
(dùng VnCoreNLP, nạp qua `solr-vn-tokenizer/`).

## Cấu hình


| Container | Config                   | Port | Core             |
| --------- | ------------------------ | ---- | ---------------- |
| `solr_9`  | `wordcloud_config_solr/` | 8983 | `topic_10236707` |


## Workflow — theo đúng thứ tự dùng

```
01_export/   → kéo/chuẩn bị data đầu vào
02_schema/   → apply schema vào container đang chạy (mỗi khi sửa managed-schema.xml)
03_insert/   → nạp data vào container Solr 9
```

### Bước 0: Khởi động Solr

```bash
docker-compose up -d
```

### Bước 1 (nếu cần data mới): Export từ nguồn

```bash
# Kéo data từ môi trường staging thật
python 01_export/export_testing_data.py

# Hoặc dump lại data đang có trong container local (để chụp snapshot)
python 01_export/export_local_data.py --url http://localhost:8983/solr/topic_10236707 --output snapshot.json

# Nếu nguồn là JSONL, đổi sang JSON array trước
python 01_export/convert_jsonl_to_json.py input.jsonl output.json
```



### Bước 2: Apply schema (mỗi khi sửa managed-schema.xml / solrconfig.xml)

```bash
./02_schema/apply_schema.sh
```

Script sẽ xoá và tạo lại core để nạp config mới — **mất data đang có trên core đó**, phải insert lại sau bước này.

### Bước 3: Insert data

```bash
./03_insert/insert_data.sh                                    # dùng exported_data_10236707.json mặc định
./03_insert/insert_data.sh exported_data_10236707.json         # chỉ định file data


# Clear collections
curl -X POST "http://localhost:8983/solr/topic_140975/update?commit=true" \
  -H 'Content-Type: application/json' \
  -d '{"delete": {"query": "*:*"}}'
```



### Kiểm tra nhanh kết quả facet

```bash
curl "http://localhost:8983/solr/topic_10236707/select?q=*:*&rows=0&facet=true&facet.field=search_text_cloud&facet.sort=count&facet.limit=50&facet.mincount=1"
```

## Thư mục khác

- `solr-vn-tokenizer/` — source plugin `VietnameseTokenizer` (Maven). Xem `SOLR_9_MIGRATION_GUIDE.md` để build lại jar khi đổi phiên bản VnCoreNLP.
- `VnCoreNLP/` — source + jar của thư viện tách từ tiếng Việt (**GPL-3.0** — cần xác nhận Legal trước khi dùng trong sản phẩm thương mại).
- `lib/` — bản copy thủ công các jar dùng để deploy nhanh (không tự động sync với `solr-vn-tokenizer/target/`).



## Yêu cầu

- Docker và Docker Compose
- Python 3, thư viện: `requests` (`pip install requests`)
- JDK 11+ và Maven — chỉ cần khi build lại `solr-vn-tokenizer` (đổi phiên bản VnCoreNLP, sửa tokenizer)

