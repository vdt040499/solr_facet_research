# Solr Search Text Facet Comparison

Script để so sánh kết quả facet giữa 3 Solr containers với các cấu hình khác nhau.

## Cấu hình

- **Solr 8.5.2 (VnCoreNLP 1.1.1)**: Port 8983
- **Solr 8.5.2 (VnCoreNLP 1.2)**: Port 8984
- **Solr 9.11**: Port 8985

## Cách sử dụng

### Bước 1: Khởi động Solr containers

```bash
docker-compose up -d
```

### Bước 2: Insert data vào Solr

```bash
./insert_data.sh
```

Hoặc chỉ định file data cụ thể:

```bash
./insert_data.sh all exported_data.json
```

### Bước 3: Chạy query trên tất cả containers

**Query một ID cụ thể:**

```bash
# Sử dụng ID mặc định
python run_query_all_containers.py

# Hoặc chỉ định ID
python run_query_all_containers.py YOUR_ID_HERE
```

**So sánh kết quả facet cho nhiều documents:**

Script sẽ tạo các file:
- `facet_comparison_log_*.txt` - Log file chi tiết
- `facet_comparison_results_*.json` - Kết quả dạng JSON
- `facet_comparison_results_*.xlsx` - Kết quả dạng Excel

## Scripts

- `docker-compose.yml` - Cấu hình 3 Solr containers
- `insert_data.sh` - Script insert data vào Solr
- `run_query_all_containers.py` - Query một ID trên cả 3 containers

## Yêu cầu

- Docker và Docker Compose
- Python 3
- Thư viện Python: `requests`, `openpyxl`

Cài đặt thư viện Python:

```bash
pip install requests openpyxl
```
