#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script to bulk insert data into Solr with progress logging.

Đọc file JSON theo stream bằng `ijson` thay vì json.load() toàn bộ file vào
RAM — file input có thể lớn hơn nhiều lần RAM khả dụng (đã thấy MemoryError
thật khi load file 866MB trên máy chỉ còn ~1.7GB RAM trống). Bộ nhớ dùng chỉ
tỉ lệ với batch_size, không tỉ lệ với kích thước file.

Usage: python bulk_insert.py <file_path> <solr_url> <collection> [batch_size] [expected_total]
"""

import sys
import json
import re
import time
import urllib.request
import urllib.error
import ijson
from datetime import datetime

# Solr báo đúng ID document gây lỗi phân tích trong message lỗi, vd.:
# "Exception writing document id 00015edd-... to the index; possible..."
DOC_ID_ERROR_RE = re.compile(r'[Ee]xception writing document id (\S+) to the index')

# Set UTF-8 encoding for Windows console
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

def format_time(seconds):
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        return f"{int(seconds)//60}m {int(seconds%60)}s"
    else:
        return f"{int(seconds//3600)}h {int((seconds%3600)//60)}m"


def log_progress(processed, expected_total, start_time, skipped_count):
    """
    In 1 dòng LOG THẬT (có xuống dòng), khác với thanh progress \\r trước
    đây — \\r ghi đè tại chỗ nên vô dụng khi redirect ra file (`> log.txt`
    hoặc `| tee log.txt`), không `tail -f` theo dõi được. Gọi 1 lần sau mỗi
    batch, không phải mỗi document, nên không spam log dù chạy hàng giờ.
    """
    elapsed = time.time() - start_time
    speed = processed / elapsed if elapsed > 0 else 0
    ts = datetime.now().strftime("%H:%M:%S")
    if expected_total:
        percent = min(processed / expected_total * 100, 100)
        print(f"[{ts}] {percent:5.1f}% | {processed:,}/{expected_total:,} docs | "
              f"đã chạy: {format_time(elapsed)} | tốc độ: {speed:.0f} docs/s | "
              f"bỏ qua: {skipped_count}", flush=True)
    else:
        print(f"[{ts}] {processed:,} docs | đã chạy: {format_time(elapsed)} | "
              f"tốc độ: {speed:.0f} docs/s | bỏ qua: {skipped_count}", flush=True)


def post_batch(update_url, headers, batch):
    """Gửi 1 batch document lên Solr. Trả về (success, error_message)."""
    batch_json = json.dumps(batch).encode('utf-8')
    try:
        req = urllib.request.Request(update_url, data=batch_json, headers=headers, method='POST')
        with urllib.request.urlopen(req, timeout=300) as response:
            response.read()
        return True, None
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode('utf-8')[:2000]
        except Exception:
            body = ""
        return False, f"HTTP {e.code} {e.reason} — {body}"
    except urllib.error.URLError as e:
        return False, f"Connection error: {e.reason}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"


def insert_with_isolation(update_url, headers, batch, skipped_log):
    """
    Fallback khi cả batch bị Solr từ chối nguyên khối (Solr reject atomic cả
    request JSON update nếu có 1 document lỗi phân tích — vd. bug offset-
    mapping của VietnameseTokenizer với vài từ có dấu đặc biệt), dù phần lớn
    document trong batch hoàn toàn hợp lệ.

    Chia đôi đệ quy (binary split) để cô lập đúng (những) document lỗi:
    thay vì insert từng document một (chậm — mỗi request 1 doc), chỉ tách
    nhỏ dần cho tới khi mỗi nhánh insert được nguyên khối hoặc còn đúng 1
    document (lúc đó mới chắc chắn là chính nó gây lỗi, bỏ qua và log lại —
    khớp BR-34: tách cụm lỗi thì bỏ qua document đó, không chặn cả luồng).

    Trả về số document insert thành công.
    """
    if not batch:
        return 0

    if len(batch) == 1:
        ok, err = post_batch(update_url, headers, batch)
        if ok:
            return 1
        doc_id = batch[0].get('id', '(không có id)')
        skipped_log.append((doc_id, err))
        return 0

    mid = len(batch) // 2
    left, right = batch[:mid], batch[mid:]
    ok_count = 0
    for half in (left, right):
        ok, err = post_batch(update_url, headers, half)
        if ok:
            ok_count += len(half)
        else:
            ok_count += insert_with_isolation(update_url, headers, half, skipped_log)
    return ok_count


def insert_removing_bad_docs(update_url, headers, batch, skipped_log):
    """
    Đường chính khi 1 batch bị Solr từ chối — NHANH HƠN NHIỀU so với chia đôi
    khi mật độ document lỗi cao (đo thực tế ~11%, không phải hiếm): Solr nêu
    thẳng ID document gây lỗi ngay trong message (regex DOC_ID_ERROR_RE).
    Loại đúng ID đó khỏi batch rồi gửi lại — mỗi lần retry vẫn là 1 request
    bulk lớn (không tụt xuống từng document), lặp tới khi batch còn lại
    insert được nguyên khối.

    Với batch 2000 doc có k doc lỗi: cần ~k+1 request. Chia đôi (binary
    split) cần tới ~2×2000 request khi mật độ lỗi cao vì hầu hết mức chia
    trung gian vẫn dính lỗi. Không parse được ID lỗi (lỗi dạng khác, không
    phải lỗi phân tích 1 document) thì rơi về chia đôi làm fallback an toàn.

    Trả về số document insert thành công.
    """
    remaining = list(batch)
    ok_count = 0
    while remaining:
        ok, err = post_batch(update_url, headers, remaining)
        if ok:
            ok_count += len(remaining)
            break

        m = DOC_ID_ERROR_RE.search(err or "")
        bad_id = m.group(1) if m else None
        idx = None
        if bad_id is not None:
            idx = next((i for i, d in enumerate(remaining) if str(d.get('id')) == bad_id), None)

        if idx is None:
            # Không parse được ID, hoặc ID đó không khớp document nào trong
            # batch hiện tại (không nên xảy ra) — fallback an toàn.
            ok_count += insert_with_isolation(update_url, headers, remaining, skipped_log)
            break

        skipped_log.append((bad_id, err))
        remaining.pop(idx)

    return ok_count


def bulk_insert(file_path, solr_url, collection, batch_size=500, expected_total=None):
    start_time = time.time()

    print(f"📖 Streaming data from {file_path}...")
    # Không commit=true trên từng request — mỗi commit ép Solr flush/refresh
    # toàn bộ index, cực chậm khi lặp lại hàng ngàn lần (đặc biệt ở nhánh
    # insert_with_isolation). Chỉ commit đúng 1 lần sau khi insert xong.
    update_url = f"{solr_url}/{collection}/update"
    commit_url = f"{solr_url}/{collection}/update?commit=true"
    headers = {'Content-Type': 'application/json'}

    processed = 0
    success_batches = 0
    failed_batches = 0
    aborted = False
    skipped_docs = []  # [(doc_id, error), ...] — document lỗi phân tích, đã bỏ qua

    batch = []
    try:
        with open(file_path, 'rb') as f:
            # File là 1 JSON array ở top-level — 'item' lấy từng phần tử,
            # không giữ cả mảng trong RAM.
            for doc in ijson.items(f, 'item'):
                batch.append(doc)
                if len(batch) >= batch_size:
                    ok, err = post_batch(update_url, headers, batch)
                    if ok:
                        success_batches += 1
                        processed += len(batch)
                    elif "refused" in err.lower() or "10061" in err:
                        print(f"❌ Lỗi ở batch bắt đầu từ doc thứ {processed}: {err}")
                        print("⛔ Dừng do bị từ chối kết nối (Solr có thể đã down).")
                        failed_batches += 1
                        aborted = True
                    else:
                        # Không phải lỗi kết nối — thường có (những) document
                        # trong batch gây lỗi phân tích. Loại bỏ đúng document
                        # đó rồi gửi lại phần còn lại.
                        print(f"⚠️  Batch bắt đầu từ doc thứ {processed} lỗi, đang loại document lỗi...")
                        ok_count = insert_removing_bad_docs(update_url, headers, batch, skipped_docs)
                        processed += ok_count
                        if ok_count < len(batch):
                            print(f"   Bỏ qua {len(batch) - ok_count} document lỗi trong batch này.")
                        success_batches += 1
                    batch = []
                    log_progress(processed, expected_total, start_time, len(skipped_docs))

                    if aborted:
                        break

            # Batch cuối chưa đủ batch_size
            if not aborted and batch:
                ok, err = post_batch(update_url, headers, batch)
                if ok:
                    success_batches += 1
                    processed += len(batch)
                elif "refused" in err.lower() or "10061" in err:
                    print(f"❌ Lỗi ở batch cuối: {err}")
                    failed_batches += 1
                else:
                    print("⚠️  Batch cuối lỗi, đang loại document lỗi...")
                    ok_count = insert_removing_bad_docs(update_url, headers, batch, skipped_docs)
                    processed += ok_count
                    if ok_count < len(batch):
                        print(f"   Bỏ qua {len(batch) - ok_count} document lỗi trong batch này.")
                    success_batches += 1
                log_progress(processed, expected_total, start_time, len(skipped_docs))
    except FileNotFoundError:
        print(f"❌ Không tìm thấy file: {file_path}")
        sys.exit(1)
    except ijson.JSONError as e:
        print(f"❌ File không phải JSON hợp lệ (hoặc không phải JSON array ở top-level): {e}")
        sys.exit(1)

    if processed > 0:
        print()
        print("💾 Đang commit...")
        ok, err = post_batch(commit_url, headers, [])
        if not ok:
            print(f"⚠️  Commit lỗi: {err} — dữ liệu đã gửi lên nhưng có thể chưa search được ngay")

    print()
    print("-" * 60)
    print(f"✅ Hoàn thành!")
    print(f"   Tổng thời gian: {format_time(time.time() - start_time)}")
    print(f"   Đã xử lý: {processed:,} documents")
    print(f"   Batch thành công: {success_batches}")
    print(f"   Batch lỗi (kết nối): {failed_batches}")
    print(f"   Document bị bỏ qua (lỗi phân tích): {len(skipped_docs)}")

    if skipped_docs:
        skip_log_path = "skipped_docs.log"
        with open(skip_log_path, 'w', encoding='utf-8') as f:
            for doc_id, err in skipped_docs:
                f.write(f"{doc_id}\t{err}\n")
        print(f"   Chi tiết document bị bỏ qua: {skip_log_path}")

    if aborted:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python bulk_insert.py <file_path> <solr_url> <collection> [batch_size] [expected_total]")
        sys.exit(1)

    file_path = sys.argv[1]
    solr_url = sys.argv[2].rstrip('/')
    collection = sys.argv[3]
    batch_size = int(sys.argv[4]) if len(sys.argv) > 4 else 500
    expected_total = int(sys.argv[5]) if len(sys.argv) > 5 else None

    try:
        bulk_insert(file_path, solr_url, collection, batch_size, expected_total)
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user.")
        sys.exit(130)
