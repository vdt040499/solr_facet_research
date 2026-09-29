#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Lọc field `search_text` của mỗi document, chỉ giữ phần tử số 2 (index 1 —
nội dung văn bản chính của mention), đúng theo BR-27 của FRD 20-F01.

Lý do: `search_text` là mảng nhiều phần tử; phần tử số 1 (index 0) thường
rỗng hoặc là tiêu đề ngắn, phần tử số 3 (index 2) — khi có — là chuỗi JSON
thô kiểu Facebook (`{"ynm_des":"...", "ynm_name":"..."}`), không phải lời
người dùng viết ra. Config copyField hiện tại copy nguyên cả mảng vào
search_text_cloud, làm rác wordcloud với các token "name", "ynm", "{", "}".

Đọc/ghi theo stream (ijson) — không load nguyên file vào RAM, an toàn với
file lớn hơn RAM khả dụng.

Usage: python extract_search_text_content.py <input.json> <output.json> [limit]
"""

import sys
import json
import ijson

if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


def extract(input_file, output_file, limit=None):
    total = 0
    kept_index1 = 0
    empty_or_missing = 0

    with open(input_file, 'rb') as fin, open(output_file, 'w', encoding='utf-8') as fout:
        fout.write('[\n')
        first = True
        for doc in ijson.items(fin, 'item'):
            st = doc.get('search_text')
            if isinstance(st, list) and len(st) > 1 and isinstance(st[1], str) and st[1].strip():
                doc['search_text'] = [st[1]]
                kept_index1 += 1
            else:
                # Không có phần tử số 2 hợp lệ — giữ nguyên document (không
                # có gì để tách cụm ở field này, khớp BR-32: vẫn insert bình
                # thường, không báo lỗi), nhưng xoá search_text_cloud rác
                # nếu search_text vốn có nhiều phần tử.
                if isinstance(st, list):
                    doc['search_text'] = st[:1] if st else []
                empty_or_missing += 1

            if not first:
                fout.write(',\n')
            fout.write(json.dumps(doc, ensure_ascii=False))
            first = False

            total += 1
            if total % 5000 == 0:
                print(f"\r  Đã xử lý {total:,} documents...", end='', flush=True)
            if limit and total >= limit:
                break
        fout.write('\n]\n')

    print()
    print(f"✅ Xong. Tổng: {total:,} | Giữ index[1]: {kept_index1:,} | Không có index[1] hợp lệ: {empty_or_missing:,}")
    print(f"   Output: {output_file}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python extract_search_text_content.py <input.json> <output.json> [limit]")
        sys.exit(1)
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else None
    extract(input_file, output_file, limit)
