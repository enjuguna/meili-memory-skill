#!/bin/bash
# Index/re-index all Markdown memory files into MeiliSearch
# Usage: bash indexer.sh [--full]

set -e

MS_HOST="http://127.0.0.1:7700"
MS_KEY="ms-323a144af37bf9ab26ddc8bc4edd1b3c"
INDEX="memories"
WORKSPACE="/root/.openclaw/workspace"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Wait for MeiliSearch to be ready
for i in $(seq 1 10); do
  if curl -s "${MS_HOST}/health" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Full reindex: delete and recreate index
if [ "$1" = "--full" ]; then
  echo "Full reindex: deleting index..."
  curl -s -X DELETE "${MS_HOST}/indexes/${INDEX}" \
    -H "Authorization: Bearer ${MS_KEY}" > /dev/null
  sleep 2
fi

# Create index if it doesn't exist
curl -s -X POST "${MS_HOST}/indexes" \
  -H "Authorization: Bearer ${MS_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"uid\":\"${INDEX}\",\"primaryKey\":\"id\"}" > /dev/null 2>&1 || true

sleep 1

# Configure settings
curl -s -X PATCH "${MS_HOST}/indexes/${INDEX}/settings" \
  -H "Authorization: Bearer ${MS_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "searchableAttributes": ["text", "source", "file", "category"],
    "filterableAttributes": ["source", "category", "file", "importance", "date"],
    "rankingRules": ["words", "typo", "proximity", "attribute", "sort", "exactness"],
    "typoTolerance": {
      "enabled": true,
      "minWordSizeForTypos": { "oneTypo": 3, "twoTypos": 6 }
    }
  }' > /dev/null

sleep 1

# Generate documents
python3 - "${WORKSPACE}" << 'PYEOF'
import json, os, glob, sys

workspace = sys.argv[1]
docs = []

# MEMORY.md - chunk by ## sections
with open(f"{workspace}/MEMORY.md", "r") as f:
    content = f.read()

sections = []
current = []
for line in content.split("\n"):
    if line.startswith("## ") and current:
        sections.append("\n".join(current))
        current = [line]
    else:
        current.append(line)
if current:
    sections.append("\n".join(current))

for i, section in enumerate(sections):
    if section.strip():
        docs.append({
            "id": f"memory-md-{i}",
            "text": section.strip(),
            "source": "MEMORY.md",
            "file": "MEMORY.md",
            "category": "long-term-memory",
            "importance": 0.9,
            "date": "2026-06-13"
        })

# Daily notes
daily_dir = f"{workspace}/memory"
if os.path.exists(daily_dir):
    for fname in sorted(glob.glob(f"{daily_dir}/*.md")):
        with open(fname, "r") as f:
            content = f.read()
        chunk_size = 1500
        chunks = [content[i:i+chunk_size] for i in range(0, len(content), chunk_size)]
        for i, chunk in enumerate(chunks):
            if chunk.strip():
                docs.append({
                    "id": f"daily-{os.path.basename(fname)[:-3]}-{i}",
                    "text": chunk.strip(),
                    "source": "daily-note",
                    "file": os.path.basename(fname),
                    "category": "session-note",
                    "importance": 0.5,
                    "date": os.path.basename(fname)[:10]
                })

with open("/tmp/memory-docs.json", "w") as f:
    json.dump(docs, f)

print(f"Generated {len(docs)} documents")
PYEOF

# Push in batches of 20
python3 - << 'PYEOF'
import json, subprocess, time

with open("/tmp/memory-docs.json") as f:
    docs = json.load(f)

ms_host = "http://127.0.0.1:7700"
ms_key = "ms-323a144af37bf9ab26ddc8bc4edd1b3c"
index = "memories"

batch_size = 20
for i in range(0, len(docs), batch_size):
    batch = docs[i:i+batch_size]
    with open("/tmp/batch.json", "w") as f:
        json.dump(batch, f)
    
    subprocess.run([
        "curl", "-s", "-X", "POST",
        f"{ms_host}/indexes/{index}/documents",
        "-H", f"Authorization: Bearer {ms_key}",
        "-H", "Content-Type: application/json",
        "-d", "@/tmp/batch.json"
    ], capture_output=True, text=True)
    time.sleep(0.5)

print(f"Indexed {len(docs)} documents")
PYEOF

# Wait for indexing to complete
sleep 3
STATS=$(curl -s "${MS_HOST}/indexes/${INDEX}/stats" \
  -H "Authorization: Bearer ${MS_KEY}")
DOC_COUNT=$(echo "$STATS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('numberOfDocuments','?'))" 2>/dev/null || echo "?")
echo "Index ready: ${DOC_COUNT} documents"
