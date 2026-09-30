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


| File                                                               | Nguồn                                                                                                                           |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `solr-vn-analyzer-1.0.jar`                                         | Build từ `vncore_nlp_research/` (`mvn clean package -Dmaven.test.skip=true`) — không dùng `solr-vn-tokenizer/` (còn bug offset) |
| `VnCoreNLP-1.2.jar`                                                | `VnCoreNLP/VnCoreNLP-1.2.jar`                                                                                                   |
| `commons-io-2.7.jar`                                               | `wordcloud_config_solr/lib/`                                                                                                    |
| `jaxb-api-2.3.0.jar`, `jaxb-core-2.3.0.jar`, `jaxb-impl-2.3.0.jar` | `wordcloud_config_solr/lib/`                                                                                                    |
| `activation-1.1.1.jar`                                             | `wordcloud_config_solr/lib/`                                                                                                    |
| `models/wordsegmenter/vi-vocab`                                    | `wordcloud_config_solr/lib/models/wordsegmenter/` — đặt cùng thư mục với `VnCoreNLP-1.2.jar` trên mỗi node                      |
| `models/wordsegmenter/wordsegmenter.rdr`                           | `wordcloud_config_solr/lib/models/wordsegmenter/`                                                                               |




## Schema — merge vào `managed-schema.xml` của configset clone

```xml
<fieldType name="text_cloud_vn" class="solr.TextField" positionIncrementGap="100">
  <analyzer type="index">
    <charFilter class="solr.HTMLStripCharFilterFactory"/>
    <tokenizer class="org.apache.lucene.analysis.vi.VietnameseTokenizerFactory"/>
    <filter class="solr.LowerCaseFilterFactory"/>
    <filter class="org.apache.lucene.analysis.vi.VietnameseStopFilterFactory"/>
    <filter class="solr.PatternReplaceFilterFactory" pattern="^[\p{P}\p{S}]+$" replacement=""/>
    <filter class="solr.PatternReplaceFilterFactory" pattern="^\S+$" replacement=""/>
    <filter class="solr.LengthFilterFactory" min="1" max="200"/>
  </analyzer>
  <analyzer type="query">
    <tokenizer class="org.apache.lucene.analysis.vi.VietnameseTokenizerFactory"/>
    <filter class="solr.LowerCaseFilterFactory"/>
  </analyzer>
</fieldType>

<field name="search_text_cloud" type="text_cloud_vn" indexed="true" stored="false" multiValued="true"/>
<copyField source="search_text" dest="search_text_cloud"/>
```

Bản đầy đủ: `[wordcloud_config_solr/conf/managed-schema.xml](wordcloud_config_solr/conf/managed-schema.xml)`.

## Trình tự triển khai

Dùng `REINDEXCOLLECTION` để lấy data thật từ 1 topic có sẵn, không tự export/insert từ máy local.
Nguồn bị chuyển **read-only** trong suốt lúc reindex (mục 9-10 ở trên).


| #   | Bước                                                            | Lệnh                                                                                                                                                                                 |
| --- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Clone configset                                                 | `bin/solr zk cp -r zk:/configs/topic_v3 zk:/configs/topic_v3_wordcloud_test -z <zkHost>` hoặc `CONFIGSETS?action=CREATE&name=topic_v3_wordcloud_test&baseConfigSet=topic_v3`         |
| 2   | Merge fieldType vào configset clone                             | Sửa `managed-schema.xml` của `topic_v3_wordcloud_test`, không đụng `topic_v3` gốc                                                                                                    |
| 3   | Deploy jar + `models/` lên cả 3 node, rolling-restart 1 lần     | Theo cách A/B đã chọn ở mục "Điểm chặn kỹ thuật" #1                                                                                                                                  |
| 4   | Reindex topic nguồn (đã chọn ở mục 10) sang collection test mới | `admin/collections?action=REINDEXCOLLECTION&name=<topic_id>&target=wordcloud_test_1&configName=topic_v3_wordcloud_test&async=reindex1`                                               |
| 5   | Theo dõi tới khi xong                                           | `action=REQUESTSTATUS&requestid=reindex1`                                                                                                                                            |
| 6   | Kiểm tra facet + latency trên `wordcloud_test_1`                | Đối chiếu NFR-05. Topic nguồn tự hết read-only khi bước 4 xong                                                                                                                       |
| 7a  | Nếu ổn — xoá `wordcloud_test_1` + configset test                | Không đụng gì tới topic nguồn                                                                                                                                                        |
| 7b  | Áp lên chính topic đó                                           | `REINDEXCOLLECTION&name=<topic_id>&target=<topic_id>&configName=topic_v3_wordcloud_test&async=reindex2` — Solr tự tạo bản mới + alias trỏ ngược tên cũ, phía client không cần đổi gì |




## Việc còn treo


| Việc                          | Trạng thái                                                                                                               |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| License GPL-3.0 của VnCoreNLP | Chưa có xác nhận Legal. 3 hướng: (1) tách tokenizer khỏi process Solr, (2) mua license thương mại, (3) đổi thư viện khác |


