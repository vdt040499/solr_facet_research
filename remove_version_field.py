#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script để xóa field _version_ khỏi file JSON trước khi insert vào Solr
Để tránh version conflict errors
"""

import json
import sys
import os

# Set UTF-8 encoding cho Windows
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

def remove_version_field(input_file: str, output_file: str = None):
    """
    Xóa field _version_ khỏi file JSON
    
    Args:
        input_file: File JSON input
        output_file: File JSON output (nếu None thì ghi đè file input)
    """
    if not os.path.exists(input_file):
        print(f"❌ File không tồn tại: {input_file}")
        return False
    
    if output_file is None:
        output_file = input_file.replace('.json', '_no_version.json')
        print(f"⚠️  Không chỉ định output file, sẽ tạo: {output_file}")
    
    print(f"📖 Đang đọc file: {input_file}")
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        if not isinstance(data, list):
            print("❌ File JSON phải là một array")
            return False
        
        print(f"   ✅ Tổng số records: {len(data):,}")
        print(f"🔧 Đang xóa field _version_...")
        
        removed_count = 0
        for doc in data:
            if '_version_' in doc:
                del doc['_version_']
                removed_count += 1
        
        print(f"   ✅ Đã xóa _version_ từ {removed_count:,} records")
        
        print(f"📝 Đang ghi vào file: {output_file}")
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        
        # So sánh kích thước file
        input_size = os.path.getsize(input_file)
        output_size = os.path.getsize(output_file)
        print(f"   ✅ Kích thước file:")
        print(f"      Input: {input_size / (1024*1024):.2f} MB")
        print(f"      Output: {output_size / (1024*1024):.2f} MB")
        
        print(f"✅ Hoàn thành!")
        print(f"   Input: {input_file}")
        print(f"   Output: {output_file}")
        return True
        
    except json.JSONDecodeError as e:
        print(f"❌ Lỗi khi parse JSON: {e}")
        return False
    except Exception as e:
        print(f"❌ Lỗi: {e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python remove_version_field.py <input_file> [output_file]")
        print()
        print("Ví dụ:")
        print("  python remove_version_field.py exported_data.json")
        print("  python remove_version_field.py exported_data.json exported_data_no_version.json")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    success = remove_version_field(input_file, output_file)
    sys.exit(0 if success else 1)

