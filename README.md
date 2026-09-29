# Solr Search Text Facet

Test tách cụm từ (wordcloud) trên **Solr 9.11** bằng plugin `VietnameseTokenizer`
(dùng VnCoreNLP, nạp qua `solr-vn-tokenizer/`).

## Cấu hình

| Container | Config | Port | Core |
|---|---|---|---|
| `solr_9` | `wordcloud_config_solr/` | 8983 | `topic_10236707` |

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
```

### Kiểm tra nhanh kết quả facet

```bash
curl "http://localhost:8983/solr/topic_10236707/select?q=*:*&rows=0&facet=true&facet.field=search_text_cloud&facet.sort=count&facet.limit=50&facet.mincount=1"
```

## Lỗi đã biết: `Token ... should appear in the text` khi bật `HTMLStripCharFilter` cho `text_cloud_vn`

### Triệu chứng

Document có thẻ HTML bị Solr từ chối **cả document** khi index vào core dùng `text_cloud_vn`:

```text
Exception writing document id <id> to the index; possible analysis error:
Token `giữa` should appear in the text: <toàn bộ văn bản đã strip>
```

Đây là `IllegalArgumentException` từ `VietnameseTokenizer.incrementToken()`. Chuỗi thông báo này chỉ có trong
class đó, không có trong bất kỳ TokenFilter nào của Lucene/Solr.

Hệ quả với `03_insert/bulk_insert.py`: mỗi document lỗi làm cả batch bị từ chối, script phải gửi lại batch sau mỗi
lần loại 1 doc lỗi. Lần chạy đầu mất khoảng 10 giờ cho ~120K doc (theo báo cáo lúc chạy), chủ yếu vì số request
retry chứ không phải vì tokenizer chậm.

### Điều kiện kích hoạt

Có CharFilter đứng **trước** `VietnameseTokenizer` và làm đổi độ dài văn bản (`HTMLStripCharFilter` đã gặp thật;
về nguyên tắc cả `PatternReplaceCharFilter`, `MappingCharFilter`). Văn bản thuần thì không bị.

Số liệu đo trên `test_5k.json` (5.000 document), Solr 9.10.1:

| Đo | Kết quả |
|---|---|
| Document lỗi có thẻ HTML | 554/554 (danh sách trong `skipped_docs.log`) |
| Document tốt có thẻ HTML | 0/4.446 |
| 20 doc HTML từng lỗi, có `HTMLStripCharFilter` | 20/20 lỗi (HTTP 500) |
| Cùng 20 doc, đã bỏ thẻ HTML trước khi phân tích | 20/20 thành công (HTTP 200) |
| Cùng 20 doc, giữ nguyên HTML, gỡ `HTMLStripCharFilter` khỏi field type | 20/20 thành công (HTTP 200) |

Mọi document có HTML đều lỗi, không phải lỗi ngẫu nhiên: tỉ lệ lỗi bằng tỉ lệ document có HTML.

### Nguyên nhân

Suy luận từ mã, được các thí nghiệm trên xác nhận gián tiếp (chưa chạy trực tiếp từng dòng):

`incrementToken()` trộn hai hệ toạ độ. Tokenizer đọc văn bản **sau** CharFilter (đã strip, ngắn hơn bản gốc) và tìm
token bằng `indexOf(preprocessedText, form, offset)` trong hệ toạ độ đó. Nhưng bản cũ gán
`offset = correctOffset(location.end)`; `correctOffset` quy về toạ độ **văn bản gốc** (dài hơn), rồi giá trị đó lại làm
điểm bắt đầu tìm ở token kế tiếp. Con trỏ chạy xa dần khỏi vị trí thật cho tới khi một từ không còn tìm thấy thì ném
exception. Không có CharFilter đổi độ dài thì `correctOffset(x) == x` nên lỗi không lộ ra.

### Cách sửa (trong `VietnameseTokenizer.java`)

Chỉ dùng `correctOffset` cho `OffsetAttribute`, giữ con trỏ tìm kiếm ở toạ độ văn bản đã strip:

```java
// Trước
offsetAtt.setOffset(correctOffset(location.start), offset = correctOffset(location.end));

// Sau
offsetAtt.setOffset(correctOffset(location.start), correctOffset(location.end));
offset = location.end;   // con trỏ tìm kiếm: toạ độ văn bản đã qua CharFilter, KHÔNG qua correctOffset
```

`end()` giữ nguyên. Bản đã sửa nằm ở repo `vncore_nlp_research` (đã nâng lên Lucene 9.11.1, bytecode Java 11).
**Bản trong `solr-vn-tokenizer/` của repo này là bản cũ, chưa sửa** (và thư mục này nằm trong `.gitignore`).

### Đã loại trừ

- Lệch chuẩn hoá Unicode NFC/NFD: 0% document lỗi không chuẩn NFC.
- VnCoreNLP dịch chuyển dấu thanh (`òa` -> `oà`): hành vi có thật nhưng `NORMALIZER` chỉ đổi 2 ký tự thành 2 ký tự nên
  không làm lệch vị trí.
- Khoảng trắng và xuống dòng liên tiếp: bản đã bỏ thẻ HTML nhưng giữ nguyên các dòng trống vẫn thành công.
- TokenFilter phía sau tokenizer (`PatternReplaceFilter`, `LengthFilter`, ...): lỗi ném từ tokenizer, trước khi có
  filter nào chạy.

### Trạng thái hiện tại (28/09/2026)

- **Schema đang dùng workaround:** dòng `HTMLStripCharFilterFactory` của `text_cloud_vn` đang bị comment
  (`wordcloud_config_solr/conf/managed-schema.xml`, dòng 177). Insert 5.000 doc vào đủ 5.000, không bỏ qua doc nào.
  Đổi lại thẻ HTML đi vào tokenizer nên còn sót rất ít rác (3 term trong 5.000 doc, ví dụ `hải nguyễn<`,
  `key=đảng cộng sản việt nam`).
- **Jar đã sửa đã build nhưng chưa kiểm chứng end-to-end:** `solr-vn-analyzer-1.0.jar` mới (Lucene 9.11.1) chưa được
  chép vào `wordcloud_config_solr/lib/`, chưa chạy thử trên Solr. Chưa có unit test hồi quy.

### Các bước để bật lại HTMLStrip sau khi sửa tokenizer

1. Chép `vncore_nlp_research/target/solr-vn-analyzer-1.0.jar` đè lên `wordcloud_config_solr/lib/solr-vn-analyzer-1.0.jar`.
   Chỉ jar này thay đổi, các jar còn lại (`VnCoreNLP-1.2.jar`, `commons-io`, `jaxb-*`, `activation`) giữ nguyên.
2. Bỏ comment `HTMLStripCharFilterFactory` ở dòng 177.
3. `./02_schema/apply_schema.sh <tên core>` (xoá và tạo lại core đó, restart container).
4. Phân tích lại các doc HTML từng lỗi qua `/solr/<core>/analysis/field` với `analysis.fieldtype=text_cloud_vn`:
   kỳ vọng HTTP 200 (trước khi sửa: 500).

Hướng khác không cần build lại jar (chưa thử): tách HTML trước khi vào bước phân tích bằng update processor
(`CloneFieldUpdateProcessorFactory` sang field nguồn riêng, rồi `HTMLStripFieldUpdateProcessorFactory` trên field
đó, và `copyField` từ field đó sang `search_text_cloud`).

## Thư mục khác

- `solr-vn-tokenizer/` — source plugin `VietnameseTokenizer` (Maven). Xem `SOLR_9_MIGRATION_GUIDE.md` để build lại jar khi đổi phiên bản VnCoreNLP.
- `VnCoreNLP/` — source + jar của thư viện tách từ tiếng Việt (**GPL-3.0** — cần xác nhận Legal trước khi dùng trong sản phẩm thương mại).
- `lib/` — bản copy thủ công các jar dùng để deploy nhanh (không tự động sync với `solr-vn-tokenizer/target/`).

## Yêu cầu

- Docker và Docker Compose
- Python 3, thư viện: `requests` (`pip install requests`)
- JDK 11+ và Maven — chỉ cần khi build lại `solr-vn-tokenizer` (đổi phiên bản VnCoreNLP, sửa tokenizer)
