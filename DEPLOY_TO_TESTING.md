# Deploy wordcloud tokenizer plugin lên Solr testing

> Khảo sát cluster ngày 24/09/2026, chỉ gọi API đọc, chưa đổi gì trên cluster.

## Mục tiêu


|         |                                                                                                      |
| ------- | ---------------------------------------------------------------------------------------------------- |
| Việc    | Deploy field type `text_cloud_vn` (`VietnameseTokenizer`) lên `solrtopic-testing.ynm.local`          |
| Phạm vi | 1 topic cụ thể, không đụng 81 topic khác                                                             |
| Nguồn   | Repo `solr_search_text_facet` — đã verify trên 167.408 document thật (29/09/2026), 0 lỗi, facet sạch |


## Khảo sát cluster (24/09/2026)


| Mục                                  | Kết quả                                                      |
| ------------------------------------ | ------------------------------------------------------------ |
| Mode                                 | SolrCloud — zkHost `zk01/02/03.ynm.local:2181/solrtopic`     |
| Node                                 | 3 node: `solrtopic01/02/03.ynm.local:8985`                   |
| Solr version                         | 9.10.1                                                       |
| Tổng collection                      | 82                                                           |
| Collection dùng configset `topic_v3` | 81/82                                                        |
| Collection dùng configset riêng      | 1 (`_designer_hung_sample`)                                  |
| Mô hình topic                        | 1 topic = 1 collection = 1 shard = 1 replica, không failover |
| Package Manager                      | Đã bật (`-Denable.packages=true`)                            |




## Điểm chặn kỹ thuật


| #   | Vấn đề                                  | Chi tiết                                                                                                                                                                                                              |
| --- | --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Jar không đưa vào ZooKeeper được        | ZK giới hạn ~1MB/znode, `VnCoreNLP-1.2.jar` = 27MB. Phải deploy jar qua filesystem 3 node (`sharedLib` trong `solr.xml`) hoặc Package Manager — **cần infra chọn cách**                                               |
| 2   | Bug classloader lúc tạo/reload core     | Tạo core dùng jar ngoài trong lúc JVM đang chạy → lỗi load class. Chỉ hết khi JVM khởi động lại. Với replica duy nhất/node, restart node = gián đoạn các topic khác trên node đó — **cần infra coordinate thời điểm** |
| 3   | 81/82 collection dùng chung 1 configset | Không sửa trực tiếp `topic_v3` — phải clone configset riêng để test                                                                                                                                                   |




## Việc cần làm trước khi deploy


| #   | Việc                                                                                                                                                                                                   |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Xác nhận VPN/kết nối tới `solrtopic-testing.ynm.local`                                                                                                                                                 |
| 2   | Kiểm tra `topic_v3` đã có `search_text_cloud`/`text_cloud_vn` chưa                                                                                                                                     |
| 3   | Kiểm tra `solrconfig.xml` của `topic_v3` có `<lib>` sẵn chưa, `solr.allowPaths` có chặn lib path tuỳ chọn không                                                                                        |
| 4   | Kiểm tra `solr.xml` trong ZK có `sharedLib` đang dùng chưa                                                                                                                                             |
| 5   | Kiểm tra Package Manager có package nào sẵn chưa                                                                                                                                                       |
| 6   | Xác nhận số replica/node (giả định 1, cần xác nhận thật)                                                                                                                                               |
| 7   | Đo latency index có/không `search_text_cloud` trên hạ tầng thật, đối chiếu NFR-05 (≤ 20%) — local đo chậm hơn 5-8 lần                                                                                  |
| 8   | Xin Legal xác nhận license GPL-3.0 của VnCoreNLP                                                                                                                                                       |
| 9   | Xác nhận field `search_text` trong schema `topic_v3` có `stored="true"` không — điều kiện bắt buộc để `REINDEXCOLLECTION` đọc lại được nội dung, field không stored sẽ mất vĩnh viễn ở collection đích |
| 10  | Chọn 1 topic thật **ít traffic ghi** để làm nguồn test — nguồn bị chuyển read-only trong suốt lúc reindex                                                                                              |




## File cần mang theo


| File                                      | Nguồn                                                                                                                            |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `solr-vn-analyzer-1.0.jar`                 | Build từ `vncore_nlp_research/` (`mvn clean package -Dmaven.test.skip=true`) — không dùng `solr-vn-tokenizer/` (còn bug offset)  |
| `VnCoreNLP-1.2.jar`                        | `VnCoreNLP/VnCoreNLP-1.2.jar`                                                                                                    |
| `models/wordsegmenter/vi-vocab`            | `wordcloud_config_solr/lib/models/wordsegmenter/` — đặt cùng thư mục với `VnCoreNLP-1.2.jar` trên mỗi node                       |
| `models/wordsegmenter/wordsegmenter.rdr`   | `wordcloud_config_solr/lib/models/wordsegmenter/`                                                                                |

`commons-io`, `jaxb-api/core/impl`, `activation` **không cần mang theo** — đã test trên 1 container Solr 9.10.1
riêng biệt (không đụng data thật), chỉ dùng 2 jar + `models/` ở trên: core load được, phân tích + insert 50
document thật cho kết quả đúng, không lỗi (30/09/2026).

**Chỉ thêm file mới, không xoá gì trên node testing.** Đặt 2 jar + `models/` vào 1 thư mục riêng
(`sharedLib` mới hoặc thư mục Package Manager cấp), không động vào bất kỳ jar/thư viện nào Solr đang có sẵn.




## Schema — thêm bằng Schema API, không sửa file XML tay

**Không tải/chèn/đẩy lại `managed-schema.xml`.** Dùng Schema API để Solr tự thêm đúng 3 phần dưới đây vào
bản đang có — không có rủi ro ghi đè mất field/fieldType khác của `topic_v3` (`search_text`, `mention_tags`,
`categories`...).

Schema API hoạt động ở cấp **collection** đang chạy, không gọi thẳng vào configset — cần 1 collection tạm
dùng configset clone để gọi API lên (xem bước 2-4 ở "Trình tự triển khai").

```json
{
  "add-field-type": {
    "name": "text_cloud_vn",
    "class": "solr.TextField",
    "positionIncrementGap": "100",
    "indexAnalyzer": {
      "charFilters": [
        { "class": "solr.HTMLStripCharFilterFactory" }
      ],
      "tokenizer": { "class": "org.apache.lucene.analysis.vi.VietnameseTokenizerFactory" },
      "filters": [
        { "class": "solr.LowerCaseFilterFactory" },
        { "class": "org.apache.lucene.analysis.vi.VietnameseStopFilterFactory" },
        { "class": "solr.PatternReplaceFilterFactory", "pattern": "^[\\p{P}\\p{S}]+$", "replacement": "" },
        { "class": "solr.PatternReplaceFilterFactory", "pattern": "^\\S+$", "replacement": "" },
        { "class": "solr.LengthFilterFactory", "min": 1, "max": 200 }
      ]
    },
    "queryAnalyzer": {
      "tokenizer": { "class": "org.apache.lucene.analysis.vi.VietnameseTokenizerFactory" },
      "filters": [
        { "class": "solr.LowerCaseFilterFactory" }
      ]
    }
  },
  "add-field": {
    "name": "search_text_cloud",
    "type": "text_cloud_vn",
    "indexed": true,
    "stored": false,
    "multiValued": true
  },
  "add-copy-field": {
    "source": "search_text",
    "dest": "search_text_cloud"
  }
}
```

```bash
curl -X POST -H 'Content-Type: application/json' --data-binary @schema-add.json \
  "http://solrtopic01.ynm.local:8985/solr/<collection_tạm>/schema"
```

Đối chiếu (không copy) với bản XML tương đương đang chạy ở local:
[wordcloud_config_solr/conf/managed-schema.xml](wordcloud_config_solr/conf/managed-schema.xml).

## Trình tự triển khai

Dùng `REINDEXCOLLECTION` để lấy data thật từ 1 topic có sẵn, không tự export/insert từ máy local.
Nguồn bị chuyển **read-only** trong suốt lúc reindex (mục 9-10 ở trên).


| #   | Bước                                                            | Lệnh                                                                                                                                                                                 |
| --- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Clone configset                                                 | `bin/solr zk cp -r zk:/configs/topic_v3 zk:/configs/topic_v3_wordcloud_test -z <zkHost>` hoặc `CONFIGSETS?action=CREATE&name=topic_v3_wordcloud_test&baseConfigSet=topic_v3`         |
| 2   | Tạo collection tạm dùng configset clone — chỉ để gọi Schema API | `CREATE?name=wordcloud_schema_setup&numShards=1&replicationFactor=1&collection.configName=topic_v3_wordcloud_test`                                                                  |
| 3   | Gọi Schema API — thêm fieldType/field/copyField                | POST JSON ở mục "Schema" lên `/solr/wordcloud_schema_setup/schema`                                                                                                                    |
| 4   | Xoá collection tạm — configset đã lưu thay đổi trong ZK         | `action=DELETE&name=wordcloud_schema_setup`                                                                                                                                          |
| 5   | Deploy jar + `models/` lên cả 3 node, rolling-restart 1 lần     | Theo cách A/B đã chọn ở mục "Điểm chặn kỹ thuật" #1                                                                                                                                  |
| 6   | Reindex topic nguồn (đã chọn ở mục 10) sang collection test mới | `admin/collections?action=REINDEXCOLLECTION&name=<topic_id>&target=wordcloud_test_1&configName=topic_v3_wordcloud_test&async=reindex1`                                               |
| 7   | Theo dõi tới khi xong                                           | `action=REQUESTSTATUS&requestid=reindex1`                                                                                                                                            |
| 8   | Kiểm tra facet + latency trên `wordcloud_test_1`                | Đối chiếu NFR-05. Topic nguồn tự hết read-only khi bước 6 xong                                                                                                                       |
| 9a  | Nếu ổn — xoá `wordcloud_test_1` + configset test                | Không đụng gì tới topic nguồn                                                                                                                                                        |
| 9b  | Áp lên chính topic đó                                           | `REINDEXCOLLECTION&name=<topic_id>&target=<topic_id>&configName=topic_v3_wordcloud_test&async=reindex2` — Solr tự tạo bản mới + alias trỏ ngược tên cũ, phía client không cần đổi gì |




## Việc còn treo


| Việc                          | Trạng thái                                                                                                               |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| License GPL-3.0 của VnCoreNLP | Chưa có xác nhận Legal. 3 hướng: (1) tách tokenizer khỏi process Solr, (2) mua license thương mại, (3) đổi thư viện khác |


