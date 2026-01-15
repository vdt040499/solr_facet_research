#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script để chạy query Solr trên cả 3 containers
Query: facet search với id filter

Cách sử dụng:
    python run_query_all_containers.py [id]

Tham số:
    id: ID để filter (mặc định: 0034f7e7-7c85-5ae4-8c30-145cb0aecfae)

Ví dụ:
    python run_query_all_containers.py
    python run_query_all_containers.py 0034f7e7-7c85-5ae4-8c30-145cb0aecfae
"""

import requests
import json
import sys
from urllib.parse import urlencode

# ID để filter (có thể override từ command line)
ID = sys.argv[1] if len(sys.argv) > 1 else "0034f7e7-7c85-5ae4-8c30-145cb0aecfae"

# Base query parameters
QUERY_PARAMS = {
    "q": "*:*",
    "fq": f"id:{ID}",
    "facet": "true",
    "facet.field": "search_text_cloud",
    "facet.sort": "count",
    "rows": "0",
    "wt": "json",
    "indent": "true",
    "facet.limit": "1000",
    "facet.mincount": "1"
}

# Container configurations
CONTAINERS = [
    {
        "name": "solr_8_5_2_1_1",
        "port": 8983,
        "core": "topic_tanvd",
        "version": "Solr 8.5.2 (VnCoreNLP 1.1.1)"
    },
    {
        "name": "solr_8_5_2_1_2",
        "port": 8984,
        "core": "topic_tanvd",
        "version": "Solr 8.5.2 (VnCoreNLP 1.2)"
    },
    {
        "name": "solr_9_11",
        "port": 8985,
        "core": "topic_tanvd_9",
        "version": "Solr 9.11"
    }
]


def run_query(container_name, port, core, solr_version):
    """Chạy query trên một container"""
    url = f"http://localhost:{port}/solr/{core}/select"
    
    print("━" * 50)
    print(f"📦 Container: {solr_version}")
    print("━" * 50)
    print(f"\nURL: {url}?{urlencode(QUERY_PARAMS)}")
    print()
    
    # Thử query trực tiếp (không cần ping trước)
    try:
        response = requests.get(url, params=QUERY_PARAMS, timeout=30)
        response.raise_for_status()
        
        # Format JSON output
        data = response.json()
        print(json.dumps(data, indent=2, ensure_ascii=False))
        print()
        print("✅ Query thành công")
        
        return True, data
        
    except requests.exceptions.ConnectionError:
        print(f"❌ Không thể kết nối đến Solr {solr_version} trên port {port}")
        print(f"   Hãy kiểm tra container có đang chạy không:")
        print(f"   docker ps | grep {container_name}")
        print(f"   Hoặc khởi động containers: docker-compose up -d")
        return False, None
    except requests.exceptions.Timeout:
        print(f"❌ ERROR: Timeout khi kết nối đến container {container_name}")
        return False, None
    except requests.exceptions.HTTPError as e:
        print(f"❌ ERROR: HTTP {e.response.status_code} - {e.response.reason}")
        try:
            error_data = e.response.json()
            print(json.dumps(error_data, indent=2, ensure_ascii=False))
        except:
            print(e.response.text)
        return False, None
    except json.JSONDecodeError:
        print(f"❌ ERROR: Không thể parse JSON response")
        print(f"Response: {response.text[:500]}")
        return False, None
    except Exception as e:
        print(f"❌ ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return False, None


def main():
    print("━" * 50)
    print("🔍 Running Solr Query on All Containers")
    print("━" * 50)
    print(f"\nID Filter: {ID}")
    print(f"\nQuery Parameters:")
    for key, value in QUERY_PARAMS.items():
        print(f"  {key}: {value}")
    print()
    
    results = []
    
    # Chạy query trên từng container
    for container in CONTAINERS:
        success, data = run_query(
            container["name"],
            container["port"],
            container["core"],
            container["version"]
        )
        results.append({
            "container": container["name"],
            "version": container["version"],
            "success": success,
            "data": data
        })
        print()
        print()
    
    # Tóm tắt kết quả
    print("━" * 50)
    print("📊 Summary")
    print("━" * 50)
    print()
    for result in results:
        status = "✅ SUCCESS" if result["success"] else "❌ FAILED"
        print(f"{result['version']}: {status}")
    
    # Trả về exit code
    if all(r["success"] for r in results):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
