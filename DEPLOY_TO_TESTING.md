# Deploy wordcloud tokenizer plugin lên Solr testing

> Note kèm ticket cho team infra. Khảo sát cluster thực hiện ngày 24/09/2026,
> chỉ gọi API đọc (Admin API `STATUS`/`CLUSTERSTATUS`/`info/system`), chưa
> đổi gì trên cluster.

## Mục tiêu

Áp dụng field type `text_cloud_vn` (plugin `VietnameseTokenizer` tách từ
tiếng Việt cho wordcloud) lên **1 topic cụ thể** trên Solr testing
(`solrtopic-testing.ynm.local`), không ảnh hưởng các topic khác.

Nguồn: repo `solr_search_text_facet` — đã build và verify chạy đúng trên
Solr 9.10.1 local (cùng version với cluster testing), **kể cả trên toàn bộ
167.408 document thật** (29/09/2026), không còn lỗi, facet sạch. Chi tiết
lỗi đã sửa và số liệu verify ở mục "Lỗi đã biết" trong
[README.md](README.md#lỗi-đã-biết-token--should-appear-in-the-text-khi-bật-htmlstripcharfilter-cho-text_cloud_vn).

## Việc cần làm trước khi deploy lên testing

- [ ] Xác nhận VPN/kết nối mạng tới `solrtopic-testing.ynm.local` (lần thử gần nhất bị timeout)
- [ ] Kiểm tra `topic_v3` đã có `search_text_cloud` / `text_cloud_vn` chưa
- [ ] Kiểm tra `solrconfig.xml` của `topic_v3` có `<lib>` nào sẵn chưa, và
      `solr.allowPaths` có chặn thư mục lib tuỳ chọn không
- [ ] Kiểm tra `solr.xml` trong ZooKeeper có `sharedLib` nào đang dùng chưa
- [ ] Kiểm tra Package Manager có package nào sẵn chưa (khả năng cao không dùng được — xem mục 1 bên dưới)
- [ ] Xác nhận số replica mỗi node (giả định 1, không failover — cần xác nhận, không suy đoán)
- [ ] Đo latency index với `search_text_cloud` trên hạ tầng thật, đối chiếu NFR-05 (≤ 20%) — local đo được chậm hơn ~5-8 lần (2.000 doc: ~12,7s có field vs ~1,5-2,7s không có)
- [ ] Xin Legal xác nhận license GPL-3.0 của VnCoreNLP trước khi deploy diện rộng hơn

## Khảo sát cluster (24/09/2026)

| Mục | Kết quả |
|---|---|
| Mode | **SolrCloud** — zkHost `zk01/02/03.ynm.local:2181/solrtopic` |
| Node | 3 node: `solrtopic01/02/03.ynm.local:8985` |
| Solr version | 9.10.1 (khớp bản đang test local) |
| Tổng số collection | 82 |
| Collection dùng configset `topic_v3` | **81/82** |
| Collection dùng configset riêng | 1 (`_designer_hung_sample`) |
| Mô hình topic | Mỗi topic = 1 collection riêng, 1 shard, 1 replica (`replicationFactor: 1`, không có replica dự phòng) |
| Package Manager | Đã bật (`-Denable.packages=true` trong JVM args) |

**Điểm quan trọng nhất: 81 collection đang dùng chung đúng 1 configset
`topic_v3`.** Sửa trực tiếp `topic_v3` trong ZooKeeper rồi reload sẽ ảnh
hưởng cả 81 topic, không riêng topic cần test.

## 2 điểm chặn kỹ thuật

### 1. Jar không đưa thẳng vào ZooKeeper được

ZK giới hạn kích thước dữ liệu mỗi znode (mặc định ~1MB). `VnCoreNLP-1.2.jar`
một mình đã 27MB. Configset lưu trong ZK chỉ chứa được file text
(`managed-schema.xml`, `solrconfig.xml`, `.txt`) — jar phải deploy qua
đường khác:

- **(A) Filesystem trên cả 3 node** — copy jar vào một `sharedLib` path khai
  trong `solr.xml` của từng node, hoặc
- **(B) Solr Package Manager** — cluster đã bật sẵn, có thể là cách chuẩn
  của team (phân phối jar qua blob store `.system` collection, tự sync tới
  mọi node, không cần SSH từng máy).

**Cần infra xác nhận: cách A hay B là quy ước hiện có của team?**

### 2. Bug classloader — cách né ở local không an toàn ở đây

Đã gặp thật trên Solr 9.10.1 (local test): tạo/reload core dùng field type
nạp từ jar ngoài **trong lúc JVM đang chạy** báo lỗi
`Error loading class ...VietnameseAnalyzer`, dù jar đã mount đúng chỗ. Cùng
jar đó load được bình thường nếu core được JVM phát hiện **lúc khởi động**
(JVM mới).

Ở Docker local, cách né là restart container. Ở cluster 3 node này, mỗi
node đang giữ **replica duy nhất** (không failover) của hàng chục topic
khác. Restart JVM một node để né bug sẽ làm gián đoạn mọi topic có replica
trên đúng node đó — **không phải việc tự làm một mình, cần infra
coordinate thời điểm** (rolling restart, hoặc xác nhận reload không dính
bug này trên cluster thật trước).

## File cần mang theo

Từ repo `solr_search_text_facet`:

| File | Nguồn |
|---|---|
| `solr-vn-analyzer-1.0.jar` | Build từ **`vncore_nlp_research/`** (`mvn clean package -Dmaven.test.skip=true`) — **không** build từ `solr-vn-tokenizer/`, repo đó vẫn còn lỗi offset đã ghi ở [README.md](README.md), giữ chưa sửa để tiện so sánh trước/sau |
| `VnCoreNLP-1.2.jar` | `VnCoreNLP/VnCoreNLP-1.2.jar` |
| `commons-io-2.7.jar` | `wordcloud_config_solr/lib/` |
| `jaxb-api-2.3.0.jar`, `jaxb-core-2.3.0.jar`, `jaxb-impl-2.3.0.jar` | `wordcloud_config_solr/lib/` |
| `activation-1.1.1.jar` | `wordcloud_config_solr/lib/` |
| `models/wordsegmenter/vi-vocab` | `wordcloud_config_solr/lib/models/wordsegmenter/` |
| `models/wordsegmenter/wordsegmenter.rdr` | `wordcloud_config_solr/lib/models/wordsegmenter/` |

**Lưu ý:** thư mục `models/wordsegmenter/` phải nằm **cùng thư mục** với
`VnCoreNLP-1.2.jar` (tokenizer tự tìm model theo đường dẫn tương đối tới
chính jar, không phải theo working directory hay theo `conf/`).

Đoạn `fieldType` cần merge vào `managed-schema.xml` — **giữ nguyên `HTMLStripCharFilterFactory`**, đã
verify chạy đúng trên 167.408 document thật (29/09/2026) sau khi sửa lỗi offset trong tokenizer:

```xml
<fieldType name="text_cloud_vn" class="solr.TextField" positionIncrementGap="100">
  <analyzer type="index">
    <charFilter class="solr.HTMLStripCharFilterFactory"/>
    <tokenizer class="org.apache.lucene.analysis.vi.VietnameseTokenizerFactory"/>
    <filter class="solr.LowerCaseFilterFactory"/>
    <filter class="org.apache.lucene.analysis.vi.VietnameseStopFilterFactory"/>
    <!-- Loại token chỉ gồm dấu câu / ký hiệu -->
    <filter class="solr.PatternReplaceFilterFactory"
            pattern="^[\p{P}\p{S}]+$"
            replacement=""/>
    <!-- Loại từ đơn 1 âm tiết — KHÔNG ghép cụm (ShingleFilter tạo cụm vô
         nghĩa). Tokenizer (VnCoreNLP) đã tự ghép sẵn từ nhiều âm tiết có
         nghĩa thành 1 token chứa khoảng trắng (vd. "đại hội", "toàn
         quốc"); token không chứa khoảng trắng là từ đơn 1 âm tiết. -->
    <filter class="solr.PatternReplaceFilterFactory"
            pattern="^\S+$"
            replacement=""/>
    <filter class="solr.LengthFilterFactory" min="1" max="200"/>
  </analyzer>
  <analyzer type="query">
    <tokenizer class="org.apache.lucene.analysis.vi.VietnameseTokenizerFactory"/>
    <filter class="solr.LowerCaseFilterFactory"/>
  </analyzer>
</fieldType>
```

Bản đầy đủ đang chạy tham khảo tại
[`wordcloud_config_solr/conf/managed-schema.xml`](wordcloud_config_solr/conf/managed-schema.xml).

## Trình tự đề xuất — không đụng 81 topic còn lại

**Test trước trên 1 collection mới, rỗng — chưa áp thẳng lên topic thật.**
Chỉ chuyển sang topic thật (bước 6b) sau khi bước 5 cho kết quả ổn.

1. Clone configset: `topic_v3` → `topic_v3_wordcloud_test`
   ```
   bin/solr zk cp -r zk:/configs/topic_v3 zk:/configs/topic_v3_wordcloud_test -z <zkHost>
   ```
   hoặc qua Admin API: `CONFIGSETS?action=CREATE&name=topic_v3_wordcloud_test&baseConfigSet=topic_v3`
2. Merge fieldType `text_cloud_vn` ở trên vào `managed-schema.xml` của
   configset **clone** — không đụng `topic_v3` gốc.
3. Deploy jar + `models/` lên cluster (cách A hoặc B ở trên, tuỳ infra xác nhận).
   Rolling-restart 3 node để nạp jar — **cần infra coordinate thời điểm**,
   làm 1 lần duy nhất cho cả bước này, không lặp lại ở bước 6b.
4. Tạo collection mới, rỗng, dùng `collection.configName=topic_v3_wordcloud_test`
   (không phải topic đang có data).
5. Nạp thử ít document, kiểm tra facet + đo latency index (đối chiếu NFR-05).
   Xử lý phần restart JVM nếu vẫn dính bug classloader ở mục 2, dù jar đã
   sửa xong nên khả năng thấp hơn.
6. Chỉ khi bước 5 ổn:
   - **6a.** Xoá collection test + configset clone dùng để thử.
   - **6b.** Trỏ 1 topic thật sang configset mới:
     ```
     admin/collections?action=MODIFYCOLLECTION&collection=<topic_id>&collection.configName=topic_v3_wordcloud_test
     ```
     rồi reindex lại data cho topic đó — core mất index khi đổi field type,
     không tự động migrate dữ liệu cũ sang cách tách từ mới.

## Việc còn treo

**License GPL-3.0 của VnCoreNLP chưa có xác nhận Legal.** Đưa vào hạ tầng
company dù chỉ testing cũng nên chốt hướng trước khi deploy diện rộng hơn
— 3 hướng đã note trong review trước: (1) tách tokenizer ra khỏi process
Solr (ranh giới process, cần Legal xác nhận có đủ để không lan copyleft),
(2) xin license thương mại từ tác giả VnCoreNLP, (3) đổi thư viện tách từ
khác có license permissive hơn.
