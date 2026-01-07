#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script để chuyển đổi file JSONL (một JSON object mỗi dòng) 
sang file JSON array format
"""

import json
import sys
import os
from typing import Iterator

# Set UTF-8 encoding cho Windows
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

def convert_jsonl_to_json(jsonl_file: str, json_file: str, batch_size: int = 1000):
    """
    Chuyển đổi JSONL sang JSON array
    
    Args:
        jsonl_file: File JSONL input
        json_file: File JSON output
        batch_size: Số records xử lý mỗi lần để tránh memory issues
    """
    if not os.path.exists(jsonl_file):
        print(f"❌ File không tồn tại: {jsonl_file}")
        return False
    
    print(f"📖 Đang đọc file: {jsonl_file}")
    
    total_records = 0
    
    # Đếm tổng số dòng trước - thử nhiều encoding
    encodings_to_try = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252', 'iso-8859-1']
    file_encoding = None
    
    for enc in encodings_to_try:
        try:
            with open(jsonl_file, 'r', encoding=enc, errors='replace') as f:
                for _ in f:
                    total_records += 1
            file_encoding = enc
            print(f"   ✅ Phát hiện encoding: {enc}")
            break
        except UnicodeDecodeError:
            continue
    
    if file_encoding is None:
        print(f"   ⚠️  Không thể xác định encoding, sử dụng utf-8 với errors='replace'")
        file_encoding = 'utf-8'
        # Đếm lại với errors='replace'
        with open(jsonl_file, 'r', encoding=file_encoding, errors='replace') as f:
            for _ in f:
                total_records += 1
    
    print(f"   ✅ Tổng số records: {total_records:,}")
    print(f"📝 Đang ghi vào file: {json_file}")
    
    # Đọc và ghi theo batch
    with open(jsonl_file, 'r', encoding=file_encoding, errors='replace') as infile, \
         open(json_file, 'w', encoding='utf-8') as outfile:
        
        outfile.write('[\n')
        
        first = True
        count = 0
        
        for line in infile:
            line = line.strip()
            if not line:
                continue
            
            try:
                doc = json.loads(line)
                
                if not first:
                    outfile.write(',\n')
                else:
                    first = False
                
                json.dump(doc, outfile, ensure_ascii=False, indent=2)
                count += 1
                
                if count % batch_size == 0:
                    print(f"   Đã xử lý: {count:,} / {total_records:,} ({count*100/total_records:.1f}%)")
                    outfile.flush()
                    
            except json.JSONDecodeError as e:
                print(f"⚠️  Lỗi khi parse dòng {count + 1}: {e}")
                continue
        
        outfile.write('\n]')
    
    print(f"✅ Hoàn thành! Đã chuyển đổi {count:,} records")
    print(f"   Input: {jsonl_file}")
    print(f"   Output: {json_file}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python convert_jsonl_to_json.py <jsonl_file> [json_file]")
        print()
        print("Ví dụ:")
        print("  python convert_jsonl_to_json.py exported_data.jsonl")
        print("  python convert_jsonl_to_json.py exported_data.jsonl output.json")
        sys.exit(1)
    
    jsonl_file = sys.argv[1]
    json_file = sys.argv[2] if len(sys.argv) > 2 else jsonl_file.replace('.jsonl', '.json')
    
    convert_jsonl_to_json(jsonl_file, json_file)

