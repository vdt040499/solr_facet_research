#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script để export dữ liệu từ Solr collection
- Query 500 records mỗi phút
- Sử dụng cursorMark để pagination hiệu quả
- Lưu state để có thể resume khi dừng giữa chừng
- Tối ưu hiệu năng bằng cách ghi file theo batch
"""

import requests
import time
import json
import os
import sys
from datetime import datetime
from typing import Optional, Dict, Any
from urllib.parse import urlencode

# Cấu hình
SOLR_URL = "http://solrtopic-testing.ynm.local/solr"
COLLECTION_NAME = "topic_10236681"
SOLR_USERNAME = "app"
SOLR_PASSWORD = "iamapp"
ROWS_PER_REQUEST = 500  # Số records mỗi request
WAIT_SECONDS = 10  # Đợi 60 giây (1 phút) giữa các request
OUTPUT_FILE = "exported_data.jsonl"  # JSONL format (một JSON object mỗi dòng)
STATE_FILE = "export_state.json"  # File lưu trạng thái


class SolrExporter:
    def __init__(self, solr_url: str, collection_name: str, username: str, password: str):
        self.solr_url = solr_url.rstrip('/')
        self.collection_name = collection_name
        self.auth = (username, password)
        self.query_url = f"{self.solr_url}/{collection_name}/query"
        
    def get_total_count(self) -> int:
        """Lấy tổng số documents trong collection"""
        params = {
            "q": "*:*",
            "rows": "0",
            "wt": "json"
        }
        try:
            response = requests.get(self.query_url, params=params, auth=self.auth, timeout=30)
            response.raise_for_status()
            data = response.json()
            return data.get('response', {}).get('numFound', 0)
        except Exception as e:
            print(f"❌ Lỗi khi lấy tổng số documents: {e}")
            return 0
    
    def get_cursor_mark(self) -> str:
        """Lấy cursorMark ban đầu từ Solr"""
        params = {
            "q": "*:*",
            "rows": "0",
            "sort": "id asc",  # Cần sort để dùng cursorMark
            "cursorMark": "*",
            "wt": "json"
        }
        try:
            response = requests.get(self.query_url, params=params, auth=self.auth, timeout=30)
            response.raise_for_status()
            data = response.json()
            return data.get('nextCursorMark', '*')
        except Exception as e:
            print(f"❌ Lỗi khi lấy cursorMark: {e}")
            return '*'
    
    def query_with_cursor(self, cursor_mark: str, rows: int = 500) -> Optional[Dict[str, Any]]:
        """Query Solr với cursorMark"""
        params = {
            "q": "*:*",
            "q.op": "OR",
            "rows": str(rows),
            "sort": "id asc",  # Bắt buộc phải có sort để dùng cursorMark
            "cursorMark": cursor_mark,
            "wt": "json",
            "indent": "false"  # Không indent để giảm kích thước response
        }
        
        try:
            response = requests.get(self.query_url, params=params, auth=self.auth, timeout=60)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ Lỗi khi query Solr: {e}")
            if hasattr(e.response, 'text'):
                print(f"   Response: {e.response.text[:500]}")
            return None


class StateManager:
    def __init__(self, state_file: str):
        self.state_file = state_file
    
    def load_state(self) -> Dict[str, Any]:
        """Load state từ file"""
        if os.path.exists(self.state_file):
            try:
                with open(self.state_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"⚠️  Lỗi khi load state: {e}")
        return {
            "cursor_mark": "*",
            "total_exported": 0,
            "last_export_time": None,
            "start_time": None
        }
    
    def save_state(self, cursor_mark: str, total_exported: int, start_time: Optional[str] = None):
        """Lưu state vào file"""
        state = {
            "cursor_mark": cursor_mark,
            "total_exported": total_exported,
            "last_export_time": datetime.now().isoformat(),
            "start_time": start_time or datetime.now().isoformat()
        }
        try:
            with open(self.state_file, 'w', encoding='utf-8') as f:
                json.dump(state, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"⚠️  Lỗi khi lưu state: {e}")


def export_data():
    """Hàm chính để export dữ liệu"""
    # Set UTF-8 encoding cho Windows
    if sys.platform == 'win32':
        import io
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
    
    print("=" * 80)
    print("📦 EXPORT DỮ LIỆU TỪ SOLR")
    print("=" * 80)
    print()
    
    # Khởi tạo exporter và state manager
    exporter = SolrExporter(SOLR_URL, COLLECTION_NAME, SOLR_USERNAME, SOLR_PASSWORD)
    state_manager = StateManager(STATE_FILE)
    
    # Load state
    state = state_manager.load_state()
    cursor_mark = state.get("cursor_mark", "*")
    total_exported = state.get("total_exported", 0)
    start_time_str = state.get("start_time")
    
    if start_time_str:
        start_time = datetime.fromisoformat(start_time_str)
        print(f"🔄 Resume từ state:")
        print(f"   - Cursor mark: {cursor_mark}")
        print(f"   - Đã export: {total_exported:,} records")
        print(f"   - Bắt đầu từ: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    else:
        start_time = datetime.now()
        print(f"🆕 Bắt đầu export mới")
        print(f"   - Thời gian bắt đầu: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    print()
    
    # Lấy tổng số documents
    print("📊 Đang lấy thông tin collection...")
    total_docs = exporter.get_total_count()
    if total_docs == 0:
        print("❌ Không tìm thấy documents trong collection!")
        return
    
    remaining = total_docs - total_exported
    print(f"   ✅ Tổng số documents: {total_docs:,}")
    print(f"   ✅ Đã export: {total_exported:,}")
    print(f"   ✅ Còn lại: {remaining:,}")
    print()
    
    if remaining == 0:
        print("✅ Đã export hết dữ liệu!")
        return
    
    # Mở file để ghi (append mode)
    file_mode = 'a' if os.path.exists(OUTPUT_FILE) else 'w'
    print(f"📝 Ghi vào file: {OUTPUT_FILE} (mode: {file_mode})")
    print()
    
    # Lấy cursorMark ban đầu nếu chưa có
    if cursor_mark == "*":
        print("🔍 Đang lấy cursorMark ban đầu...")
        cursor_mark = exporter.get_cursor_mark()
        print(f"   ✅ Cursor mark: {cursor_mark}")
        print()
    
    request_count = 0
    last_save_time = time.time()
    query_start_time = time.time()
    
    # Tính toán ước tính ban đầu
    estimated_requests = (remaining + ROWS_PER_REQUEST - 1) // ROWS_PER_REQUEST
    
    def format_time(seconds):
        """Format thời gian thành dạng dễ đọc"""
        if seconds < 60:
            return f"{int(seconds)}s"
        elif seconds < 3600:
            return f"{int(seconds//60)}m {int(seconds%60)}s"
        else:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            return f"{hours}h {minutes}m"
    
    def get_file_size(filepath):
        """Lấy kích thước file"""
        if os.path.exists(filepath):
            size = os.path.getsize(filepath)
            if size < 1024:
                return f"{size} B"
            elif size < 1024 * 1024:
                return f"{size/1024:.1f} KB"
            elif size < 1024 * 1024 * 1024:
                return f"{size/(1024*1024):.1f} MB"
            else:
                return f"{size/(1024*1024*1024):.2f} GB"
        return "0 B"
    
    def print_progress_bar(current, total, width=50):
        """In progress bar"""
        if total == 0:
            return
        percent = current / total
        filled = int(width * percent)
        bar = '█' * filled + '░' * (width - filled)
        return f"[{bar}] {percent*100:.1f}%"
    
    print("=" * 80)
    print("🚀 BẮT ĐẦU EXPORT")
    print("=" * 80)
    print(f"📊 Tổng số records cần export: {remaining:,}")
    print(f"📦 Số records mỗi request: {ROWS_PER_REQUEST}")
    print(f"⏱️  Thời gian đợi giữa các request: {WAIT_SECONDS}s")
    print(f"📁 File output: {os.path.abspath(OUTPUT_FILE)}")
    print(f"💾 File state: {os.path.abspath(STATE_FILE)}")
    print(f"📈 Ước tính số requests: ~{estimated_requests}")
    print("=" * 80)
    print()
    
    try:
        with open(OUTPUT_FILE, file_mode, encoding='utf-8') as f:
            while True:
                request_count += 1
                query_start = time.time()
                
                # Hiển thị thông tin request
                print("─" * 80)
                print(f"📡 REQUEST #{request_count} | {datetime.now().strftime('%H:%M:%S')}")
                print("─" * 80)
                
                # Query Solr
                print("   🔍 Đang query Solr...", end=' ', flush=True)
                data = exporter.query_with_cursor(cursor_mark, ROWS_PER_REQUEST)
                query_time = time.time() - query_start
                
                if not data:
                    print("❌")
                    print("   ⚠️  Không nhận được dữ liệu, đợi 10 giây rồi thử lại...")
                    time.sleep(10)
                    continue
                
                print(f"✅ ({query_time:.2f}s)")
                
                # Lấy documents từ response
                docs = data.get('response', {}).get('docs', [])
                next_cursor_mark = data.get('nextCursorMark')
                
                if not docs:
                    print("   ✅ Không còn documents nào!")
                    break
                
                # Ghi documents vào file (JSONL format)
                write_start = time.time()
                batch_count = 0
                for doc in docs:
                    json_line = json.dumps(doc, ensure_ascii=False)
                    f.write(json_line + '\n')
                    batch_count += 1
                f.flush()  # Đảm bảo ghi vào disk ngay
                write_time = time.time() - write_start
                
                total_exported += batch_count
                remaining = total_docs - total_exported
                
                # Tính toán thống kê
                elapsed_time = (datetime.now() - start_time).total_seconds()
                if total_exported > 0 and elapsed_time > 0:
                    avg_speed = total_exported / elapsed_time * 60  # records/phút
                else:
                    avg_speed = 0
                
                if remaining > 0 and avg_speed > 0:
                    # Ước tính: số requests còn lại * thời gian đợi + thời gian query/ghi
                    remaining_requests = (remaining + ROWS_PER_REQUEST - 1) // ROWS_PER_REQUEST
                    estimated_remaining_time = remaining_requests * WAIT_SECONDS + (remaining / avg_speed * 60)
                else:
                    estimated_remaining_time = 0
                
                # Hiển thị thông tin chi tiết
                print()
                print("   📥 DỮ LIỆU NHẬN ĐƯỢC:")
                print(f"      • Records trong batch này: {batch_count:,}")
                print(f"      • Thời gian query: {query_time:.2f}s")
                print(f"      • Thời gian ghi file: {write_time:.2f}s")
                print()
                
                print("   📊 TIẾN ĐỘ TỔNG THỂ:")
                progress_bar = print_progress_bar(total_exported, total_docs)
                print(f"      {progress_bar}")
                print(f"      • Đã export: {total_exported:,} / {total_docs:,} records")
                print(f"      • Còn lại: {remaining:,} records")
                print(f"      • Hoàn thành: {total_exported*100/total_docs:.2f}%")
                print()
                
                print("   ⏱️  THỜI GIAN:")
                print(f"      • Đã chạy: {format_time(elapsed_time)}")
                if estimated_remaining_time > 0:
                    print(f"      • Ước tính còn lại: ~{format_time(estimated_remaining_time)}")
                print()
                
                print("   📈 TỐC ĐỘ:")
                print(f"      • Tốc độ trung bình: {avg_speed:.1f} records/phút")
                print(f"      • Requests đã thực hiện: {request_count}")
                if remaining > 0:
                    remaining_requests = (remaining + ROWS_PER_REQUEST - 1) // ROWS_PER_REQUEST
                    print(f"      • Requests còn lại: ~{remaining_requests}")
                print()
                
                print("   💾 FILE:")
                file_size = get_file_size(OUTPUT_FILE)
                print(f"      • Kích thước file: {file_size}")
                print(f"      • Đường dẫn: {os.path.abspath(OUTPUT_FILE)}")
                print()
                
                # Kiểm tra xem đã hết chưa
                if cursor_mark == next_cursor_mark:
                    print("   ✅ Đã đến cuối dữ liệu!")
                    break
                
                cursor_mark = next_cursor_mark
                
                # Lưu state mỗi request
                state_manager.save_state(cursor_mark, total_exported, start_time.isoformat())
                print("   💾 Đã lưu state")
                
                # Đợi trước request tiếp theo
                if remaining > 0:
                    print()
                    print(f"   ⏳ Đợi {WAIT_SECONDS} giây trước request tiếp theo...")
                    print()
                    # Hiển thị countdown
                    for i in range(WAIT_SECONDS, 0, -1):
                        print(f"\r   ⏳ Còn {i} giây...", end='', flush=True)
                        time.sleep(1)
                    print("\r   " + " " * 30 + "\r", end='')  # Xóa dòng countdown
                else:
                    break
        
        # Lưu state cuối cùng
        state_manager.save_state(cursor_mark, total_exported, start_time.isoformat())
        
        elapsed = datetime.now() - start_time
        elapsed_seconds = elapsed.total_seconds()
        avg_speed = total_exported / elapsed_seconds * 60 if elapsed_seconds > 0 else 0
        
        print()
        print("=" * 80)
        print("✅ HOÀN THÀNH EXPORT")
        print("=" * 80)
        print()
        print("📊 THỐNG KÊ:")
        print(f"   • Tổng số records đã export: {total_exported:,}")
        print(f"   • Tổng số requests: {request_count}")
        print(f"   • Thời gian tổng cộng: {format_time(elapsed_seconds)}")
        print(f"   • Tốc độ trung bình: {avg_speed:.1f} records/phút")
        print()
        print("📁 FILES:")
        print(f"   • File output: {os.path.abspath(OUTPUT_FILE)}")
        print(f"   • Kích thước: {get_file_size(OUTPUT_FILE)}")
        print(f"   • File state: {os.path.abspath(STATE_FILE)}")
        print()
        print("=" * 80)
        print()
        
    except KeyboardInterrupt:
        print()
        print()
        print("=" * 80)
        print("⚠️  ĐÃ DỪNG BỞI NGƯỜI DÙNG (Ctrl+C)")
        print("=" * 80)
        elapsed = datetime.now() - start_time
        elapsed_seconds = elapsed.total_seconds()
        state_manager.save_state(cursor_mark, total_exported, start_time.isoformat())
        print()
        print("📊 TIẾN ĐỘ HIỆN TẠI:")
        print(f"   • Đã export: {total_exported:,} / {total_docs:,} records")
        print(f"   • Hoàn thành: {total_exported*100/total_docs:.2f}%")
        print(f"   • Requests đã thực hiện: {request_count}")
        print(f"   • Thời gian đã chạy: {format_time(elapsed_seconds)}")
        print()
        print("💾 STATE ĐÃ ĐƯỢC LƯU:")
        print(f"   • File state: {os.path.abspath(STATE_FILE)}")
        print(f"   • Cursor mark: {cursor_mark}")
        print()
        print("🔄 ĐỂ TIẾP TỤC:")
        print(f"   Chạy lại script: python export_solr_data.py")
        print()
        print("=" * 80)
    except Exception as e:
        print()
        print()
        print("=" * 80)
        print("❌ LỖI XẢY RA")
        print("=" * 80)
        print(f"Lỗi: {e}")
        print()
        import traceback
        print("Chi tiết lỗi:")
        traceback.print_exc()
        print()
        elapsed = datetime.now() - start_time
        elapsed_seconds = elapsed.total_seconds()
        state_manager.save_state(cursor_mark, total_exported, start_time.isoformat())
        print("💾 STATE ĐÃ ĐƯỢC LƯU:")
        print(f"   • File state: {os.path.abspath(STATE_FILE)}")
        print(f"   • Đã export: {total_exported:,} records")
        print(f"   • Cursor mark: {cursor_mark}")
        print()
        print("🔄 ĐỂ TIẾP TỤC:")
        print(f"   Chạy lại script: python export_solr_data.py")
        print()
        print("=" * 80)


if __name__ == "__main__":
    export_data()

