import urllib.request
import urllib.parse
import json
import argparse
import sys

def export_data(solr_url, output_file, batch_size=1000):
    select_url = f"{solr_url}/select"
    cursor_mark = "*"
    total_exported = 0
    all_docs = []

    print(f"Exporting data from {solr_url}...")

    while True:
        params = {
            "q": "*:*",
            "sort": "id asc",
            "rows": batch_size,
            "cursorMark": cursor_mark,
            "fl": "*"  # Fetch all stored fields
        }
        
        query_string = urllib.parse.urlencode(params)
        req_url = f"{select_url}?{query_string}"

        try:
            with urllib.request.urlopen(req_url) as response:
                data = json.load(response)

            docs = data.get("response", {}).get("docs", [])
            next_cursor_mark = data.get("nextCursorMark")

            if not docs:
                break

            # Remove _version_ field and append to list
            for doc in docs:
                if "_version_" in doc:
                    del doc["_version_"]
                all_docs.append(doc)

            total_exported += len(docs)
            print(f"Fetched {total_exported} documents...", end='\r')

            if cursor_mark == next_cursor_mark:
                break

            cursor_mark = next_cursor_mark

        except Exception as e:
            print(f"\nError: {e}")
            return False

    print(f"\nTotal documents fetched: {total_exported}")
    
    print(f"Writing to {output_file}...")
    try:
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(all_docs, f, ensure_ascii=False, indent=2)
        print("Export completed successfully.")
        return True
    except Exception as e:
        print(f"Error writing file: {e}")
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export data from Solr to JSON")
    parser.add_argument("--url", default="http://localhost:8985/solr/topic_10236707", help="Solr Core URL")
    parser.add_argument("--output", default="exported_new.json", help="Output JSON file")
    
    args = parser.parse_args()
    
    export_data(args.url, args.output)
