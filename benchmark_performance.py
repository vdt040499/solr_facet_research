#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
import time
import json
import statistics
from urllib.parse import quote

SOLR_URL = "http://localhost:8983/solr"
COLLECTION_NAME = "topic_tanvd"
FIELD_TYPE = "text_cloud"

# Các text mẫu để test tokenization
TEST_TEXTS = [
    "Sản phẩm này có chất lượng tốt, hiệu năng mạnh mẽ, thiết kế đẹp và hiện đại",
    "Chất lượng hình ảnh sắc nét, tốc độ xử lý nhanh, pin trâu chụp được nhiều ảnh",
    "Đồ ăn tươi ngon và đa dạng, nguyên liệu chất lượng, cách chế biến công phu, hương vị đậm đà",
    "Giao hàng nhanh chóng, đóng gói cẩn thận, sản phẩm đúng như mô tả, chất lượng tốt",
    "Thiết kế thời trang và hiện đại, chất liệu cao cấp, may vá tinh tế, form dáng đẹp",
    "Sản phẩm chất lượng cao, thành phần an toàn, hiệu quả tốt, mùi hương dễ chịu",
    "Chất lượng tốt, bền bỉ, thiết kế thể thao, màu sắc đẹp, kích thước chuẩn",
    "Nội dung hay và ý nghĩa, văn phong dễ hiểu, bố cục rõ ràng, hình ảnh minh họa đẹp",
    "Chất lượng tốt, thiết kế đẹp, màu sắc trang nhã, kích thước phù hợp, giá cả hợp lý",
    "Dịch vụ tốt, nhân viên nhiệt tình, không gian đẹp, vị trí thuận tiện, giá cả hợp lý"
]

def check_solr_connection():
    """Kiểm tra kết nối đến Solr"""
    print("   Dang kiem tra ket noi...")
    # Thử ping ở collection level
    try:
        print(f"   Thu ping collection: {SOLR_URL}/{COLLECTION_NAME}/admin/ping")
        response = requests.get(f"{SOLR_URL}/{COLLECTION_NAME}/admin/ping", timeout=5)
        print(f"   Status code: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            if 'status' in data.get('responseHeader', {}) and data['responseHeader']['status'] == 0:
                print("   OK: Collection ping thanh cong")
                return True
    except Exception as e:
        print(f"   Loi khi ping collection: {e}")
    # Thử ping ở root level
    try:
        print(f"   Thu ping root: {SOLR_URL}/admin/cores?action=STATUS")
        response = requests.get(f"{SOLR_URL}/admin/cores?action=STATUS", timeout=5)
        print(f"   Status code: {response.status_code}")
        if response.status_code == 200:
            print("   OK: Root ping thanh cong")
            return True
    except Exception as e:
        print(f"   Loi khi ping root: {e}")
    return False

def test_tokenization(text, num_runs=10):
    """Test tokenization và đo thời gian"""
    url = f"{SOLR_URL}/{COLLECTION_NAME}/analysis/field"
    params = {
        "analysis.fieldvalue": text,
        "analysis.fieldtype": FIELD_TYPE,
        "wt": "json"
    }
    
    times = []
    tokens_count = 0
    
    for run_num in range(num_runs):
        start_time = time.time()
        try:
            response = requests.get(url, params=params, timeout=10)
            elapsed = (time.time() - start_time) * 1000  # Convert to milliseconds
            
            if response.status_code == 200:
                data = response.json()
                # Đếm số tokens từ response
                if 'analysis' in data and 'field_types' in data['analysis']:
                    field_analysis = data['analysis']['field_types'].get(FIELD_TYPE, {})
                    if 'index' in field_analysis:
                        index_analysis = field_analysis['index']
                        if len(index_analysis) > 0 and 'tokenStream' in index_analysis[0]:
                            tokens = index_analysis[0]['tokenStream']
                            tokens_count = len([t for t in tokens if 'string' in t])
                times.append(elapsed)
                print(f"      Run {run_num + 1}/{num_runs}: {elapsed:.2f}ms", end='\r')
            else:
                print(f"      Run {run_num + 1}: HTTP {response.status_code}")
        except Exception as e:
            print(f"      Error run {run_num + 1}: {e}")
    
    print()  # New line after progress
    
    if times:
        return {
            "text": text[:50] + "..." if len(text) > 50 else text,
            "avg_time_ms": statistics.mean(times),
            "min_time_ms": min(times),
            "max_time_ms": max(times),
            "median_time_ms": statistics.median(times),
            "tokens_count": tokens_count,
            "num_runs": len(times)
        }
    return None

def get_collection_info():
    """Lấy thông tin về collection"""
    url = f"{SOLR_URL}/{COLLECTION_NAME}/select"
    params = {
        "q": "*:*",
        "rows": "0",
        "wt": "json"
    }
    
    try:
        response = requests.get(url, params=params, timeout=10)
        if response.status_code == 200:
            data = response.json()
            if 'response' in data:
                return data['response'].get('numFound', 0)
    except:
        pass
    return 0

def test_facet_query(num_runs=10, facet_limit=100):
    """Test facet query và đo thời gian"""
    url = f"{SOLR_URL}/{COLLECTION_NAME}/select"
    params = {
        "q": "*:*",
        "facet": "true",
        "facet.field": "search_text_cloud",
        "facet.limit": str(facet_limit),
        "rows": "0",
        "wt": "json"
    }
    
    times = []
    facet_counts = []
    
    for run_num in range(num_runs):
        start_time = time.time()
        try:
            response = requests.get(url, params=params, timeout=30)
            elapsed = (time.time() - start_time) * 1000  # Convert to milliseconds
            
            if response.status_code == 200:
                data = response.json()
                # Đếm số facet values
                facet_count = 0
                if 'facet_counts' in data and 'facet_fields' in data['facet_counts']:
                    facet_fields = data['facet_counts']['facet_fields']
                    if 'search_text_cloud' in facet_fields:
                        facet_values = facet_fields['search_text_cloud']
                        # facet_values là list [term1, count1, term2, count2, ...]
                        facet_count = len(facet_values) // 2
                
                times.append(elapsed)
                facet_counts.append(facet_count)
                print(f"      Run {run_num + 1}/{num_runs}: {elapsed:.2f}ms", end='\r')
            else:
                print(f"      Run {run_num + 1}: HTTP {response.status_code}")
        except Exception as e:
            print(f"      Error run {run_num + 1}: {e}")
    
    print()  # New line after progress
    
    if times:
        return {
            "facet_limit": facet_limit,
            "avg_time_ms": statistics.mean(times),
            "min_time_ms": min(times),
            "max_time_ms": max(times),
            "median_time_ms": statistics.median(times),
            "avg_facet_count": statistics.mean(facet_counts) if facet_counts else 0,
            "num_runs": len(times)
        }
    return None

def test_facet_with_query(query, num_runs=10, facet_limit=100):
    """Test facet với query cụ thể"""
    url = f"{SOLR_URL}/{COLLECTION_NAME}/select"
    params = {
        "q": query,
        "facet": "true",
        "facet.field": "search_text_cloud",
        "facet.limit": str(facet_limit),
        "rows": "0",
        "wt": "json"
    }
    
    times = []
    
    for _ in range(num_runs):
        start_time = time.time()
        try:
            response = requests.get(url, params=params, timeout=30)
            elapsed = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                times.append(elapsed)
        except Exception as e:
            print(f"Error during facet test with query: {e}")
    
    if times:
        return {
            "query": query,
            "avg_time_ms": statistics.mean(times),
            "min_time_ms": min(times),
            "max_time_ms": max(times),
            "median_time_ms": statistics.median(times),
            "num_runs": len(times)
        }
    return None

def main():
    import sys
    import io
    # Set UTF-8 encoding for stdout on Windows
    if sys.platform == 'win32':
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    
    print("=" * 80)
    print("BENCHMARK PERFORMANCE: Tokenization & Faceting")
    print("=" * 80)
    print()
    
    # Kiểm tra kết nối Solr
    print("1. Kiem tra ket noi Solr...")
    print(f"   URL: {SOLR_URL}")
    print(f"   Collection: {COLLECTION_NAME}")
    if not check_solr_connection():
        print("ERROR: Khong the ket noi den Solr!")
        print(f"   Vui long kiem tra Solr dang chay tai: {SOLR_URL}")
        return
    print(f"   OK: Ket noi thanh cong den {SOLR_URL}")
    
    # Lấy thông tin collection
    print("   Dang lay thong tin collection...")
    doc_count = get_collection_info()
    print(f"   So documents trong collection: {doc_count:,}")
    if doc_count == 0:
        print("   CANH BAO: Collection trong, co the ket qua benchmark khong chinh xac!")
    print()
    
    # Test tokenization
    print("2. Test TOKENIZATION (text_cloud field type)")
    print("-" * 80)
    tokenization_results = []
    
    for i, text in enumerate(TEST_TEXTS, 1):
        print(f"   Test {i}/{len(TEST_TEXTS)}: {text[:50]}...")
        sys.stdout.flush()  # Force output
        result = test_tokenization(text, num_runs=5)
        if result:
            tokenization_results.append(result)
            print(f"      Avg: {result['avg_time_ms']:.2f}ms | "
                  f"Min: {result['min_time_ms']:.2f}ms | "
                  f"Max: {result['max_time_ms']:.2f}ms | "
                  f"Tokens: {result['tokens_count']}")
        else:
            print(f"      ERROR: Khong the test tokenization cho text nay")
        sys.stdout.flush()
    
    print()
    if tokenization_results:
        avg_all = statistics.mean([r['avg_time_ms'] for r in tokenization_results])
        print(f"   TONG KET TOKENIZATION:")
        print(f"   - Trung binh: {avg_all:.2f}ms")
        print(f"   - Nhanh nhat: {min([r['min_time_ms'] for r in tokenization_results]):.2f}ms")
        print(f"   - Cham nhat: {max([r['max_time_ms'] for r in tokenization_results]):.2f}ms")
    print()
    
    # Test facet query
    print("3. Test FACET QUERY (search_text_cloud field)")
    print("-" * 80)
    
    # Test với nhiều facet_limit khác nhau
    facet_limits = [50, 100, 200, 500]
    facet_results = []
    
    for limit in facet_limits:
        print(f"   Test facet voi query: *:* (facet.limit={limit})")
        sys.stdout.flush()
        facet_result = test_facet_query(num_runs=10, facet_limit=limit)
        if facet_result:
            facet_results.append(facet_result)
            print(f"      - Trung binh: {facet_result['avg_time_ms']:.2f}ms")
            print(f"      - Min: {facet_result['min_time_ms']:.2f}ms")
            print(f"      - Max: {facet_result['max_time_ms']:.2f}ms")
            print(f"      - Median: {facet_result['median_time_ms']:.2f}ms")
            print(f"      - So facet values: {facet_result['avg_facet_count']:.0f}")
        else:
            print(f"      ERROR: Khong the test facet voi limit={limit}")
        print()
        sys.stdout.flush()
    
    # Test facet với các queries khác nhau
    test_queries = [
        "*:*",
        "domain:electronics",
        "domain:food",
        "sentiment:1"
    ]
    
    print("   Test facet voi cac queries khac nhau:")
    for query in test_queries:
        result = test_facet_with_query(query, num_runs=5, facet_limit=100)
        if result:
            print(f"   - Query: {query}")
            print(f"     Trung binh: {result['avg_time_ms']:.2f}ms | "
                  f"Min: {result['min_time_ms']:.2f}ms | "
                  f"Max: {result['max_time_ms']:.2f}ms")
    print()
    
    # Tổng kết
    print("=" * 80)
    print("TONG KET")
    print("=" * 80)
    
    if tokenization_results:
        print(f"Tokenization:")
        print(f"  - Trung binh: {statistics.mean([r['avg_time_ms'] for r in tokenization_results]):.2f}ms")
        print(f"  - Nhanh nhat: {min([r['min_time_ms'] for r in tokenization_results]):.2f}ms")
        print(f"  - Cham nhat: {max([r['max_time_ms'] for r in tokenization_results]):.2f}ms")
        print()
    
    if facet_results:
        print(f"Faceting (facet.limit=100):")
        result_100 = next((r for r in facet_results if r['facet_limit'] == 100), None)
        if result_100:
            print(f"  - Trung binh: {result_100['avg_time_ms']:.2f}ms")
            print(f"  - Min: {result_100['min_time_ms']:.2f}ms")
            print(f"  - Max: {result_100['max_time_ms']:.2f}ms")
            print(f"  - Median: {result_100['median_time_ms']:.2f}ms")
    
    print()
    print("=" * 80)
    print("HOAN TAT BENCHMARK")
    print("=" * 80)

if __name__ == "__main__":
    main()

