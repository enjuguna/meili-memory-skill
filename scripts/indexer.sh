#!/bin/bash
# Tiered memory indexer for MeiliSearch
# Creates three indexes: core, working, archive
# Usage: bash indexer.sh [--full]

set -e

MS_HOST="http://127.0.0.1:7700"
MS_KEY="ms-323a144af37bf9ab26ddc8bc4edd1b3c"
WORKSPACE="/root/.openclaw/workspace"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNONYMS_FILE="${SKILL_DIR}/synonyms.json"

# Wait for MeiliSearch
for i in $(seq 1 10); do
  if curl -s "${MS_HOST}/health" > /dev/null 2>&1; then break; fi
  sleep 1
done

echo "=== MeiliSearch Tiered Memory Indexer ==="

# --- Create/recreate indexes ---
for TIER in core working archive; do
  if [ "$1" = "--full" ]; then
    curl -s -X DELETE "${MS_HOST}/indexes/${TIER}" -H "Authorization: Bearer ${MS_KEY}" > /dev/null 2>&1 || true
  fi

  # Create index if not exists
  curl -s -X POST "${MS_HOST}/indexes" \
    -H "Authorization: Bearer ${MS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"uid\":\"${TIER}\",\"primaryKey\":\"id\"}" > /dev/null 2>&1 || true

  sleep 1

  # Configure settings per tier
  case $TIER in
    core)
      # MEMORY.md — highest importance, no recency bias (it's always current)
      RANKING='["words","typo","proximity","attribute","sort","exactness"]'
      ;;
    working)
      # Recent daily notes — boost recent documents
      RANKING='["words","typo","proximity","sort","attribute","exactness"]'
      ;;
    archive)
      # Older notes — standard ranking
      RANKING='["words","typo","proximity","attribute","sort","exactness"]'
      ;;
  esac

  curl -s -X PATCH "${MS_HOST}/indexes/${TIER}/settings" \
    -H "Authorization: Bearer ${MS_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"searchableAttributes\": [\"text\", \"source\", \"file\", \"category\", \"tags\"],
      \"filterableAttributes\": [\"source\", \"category\", \"file\", \"importance\", \"date\", \"tags\", \"tier\"],
      \"rankingRules\": ${RANKING},
      \"typoTolerance\": {
        \"enabled\": true,
        \"minWordSizeForTypos\": { \"oneTypo\": 3, \"twoTypos\": 6 }
      }
    }" > /dev/null

  sleep 0.5
done

echo "Indexes configured: core, working, archive"

# --- Generate and push documents ---
python3 - "${WORKSPACE}" "${SYNONYMS_FILE}" << 'PYEOF'
import json, os, glob, sys, time
from datetime import datetime, timedelta

workspace = sys.argv[1]
synonyms_file = sys.argv[2]

# Load synonyms
with open(synonyms_file) as f:
    synonyms = json.load(f)

def expand_query_terms(text):
    """Find which synonym groups this text belongs to"""
    text_lower = text.lower()
    matched_groups = []
    for group_name, terms in synonyms.items():
        for term in terms:
            if term.lower() in text_lower:
                matched_groups.append(group_name)
                break
    return matched_groups

def auto_tag(text, source, file):
    """Generate relationship tags based on content"""
    tags = []
    text_lower = text.lower()

    # Content-based tags
    if "debt" in text_lower or "rent" in text_lower or "kes" in text_lower:
        tags.append("finance/debts")
    if "molthub" in text_lower or "daily-devotion" in text_lower:
        tags.append("project/molthub")
    if "budget" in text_lower or "budget_bot" in text_lower or "agent-money" in text_lower:
        tags.append("project/budget-tracker")
    if "bursary" in text_lower:
        tags.append("project/bursary")
    if "membership" in text_lower:
        tags.append("project/membership")
    if "github" in text_lower or "gh " in text_lower or "ghp_" in text_lower:
        tags.append("auth/github")
    if "google" in text_lower or "gog" in text_lower or "gmail" in text_lower:
        tags.append("auth/google")
    if "cron" in text_lower or "schedule" in text_lower or "daily" in text_lower:
        tags.append("schedule")
    if "eric" in text_lower and "njuguna" in text_lower:
        tags.append("identity")
    if "typescript" in text_lower or "npm" in text_lower or "node" in text_lower:
        tags.append("work/development")
    if "meilisearch" in text_lower or "meili" in text_lower:
        tags.append("infrastructure/meilisearch")
    if "openclaw" in text_lower or "gateway" in text_lower:
        tags.append("infrastructure/openclaw")
    if "skill" in text_lower and ("install" in text_lower or "publish" in text_lower):
        tags.append("skills")

    # Source-based tags
    if source == "MEMORY.md":
        tags.append("tier/core")
    else:
        tags.append("tier/daily")

    return list(set(tags))

def get_tier(date_str):
    """Determine tier based on document date"""
    try:
        doc_date = datetime.strptime(date_str[:10], "%Y-%m-%d")
        days_old = (datetime.now() - doc_date).days
        if days_old <= 7:
            return "working"
        else:
            return "archive"
    except:
        return "archive"

# --- Build documents ---
core_docs = []
working_docs = []
archive_docs = []

# MEMORY.md → always core
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
    if not section.strip():
        continue
    tags = auto_tag(section, "MEMORY.md", "MEMORY.md")
    tags.append(f"section/{i}")
    # Add synonym group tags
    for group in expand_query_terms(section):
        tags.append(f"topic/{group}")

    core_docs.append({
        "id": f"core-mem-{i}",
        "text": section.strip(),
        "source": "MEMORY.md",
        "file": "MEMORY.md",
        "category": "long-term-memory",
        "importance": 0.95,
        "date": datetime.now().strftime("%Y-%m-%d"),
        "tags": list(set(tags)),
        "tier": "core"
    })

# Daily notes → working or archive based on age
daily_dir = f"{workspace}/memory"
if os.path.exists(daily_dir):
    for fname in sorted(glob.glob(f"{daily_dir}/*.md")):
        with open(fname, "r") as f:
            content = f.read()

        date_str = fname.split("/")[-1][:10]
        tier = get_tier(date_str)

        # Chunk large files
        chunk_size = 1500
        chunks = [content[i:i+chunk_size] for i in range(0, len(content), chunk_size)]

        for i, chunk in enumerate(chunks):
            if not chunk.strip():
                continue
            tags = auto_tag(chunk, "daily-note", fname)
            tags.append(f"date/{date_str}")
            for group in expand_query_terms(chunk):
                tags.append(f"topic/{group}")

            doc = {
                "id": f"{tier}-{date_str.replace('-','')}-{i}",
                "text": chunk.strip(),
                "source": "daily-note",
                "file": os.path.basename(fname),
                "category": "session-note",
                "importance": 0.6 if tier == "working" else 0.3,
                "date": date_str,
                "tags": list(set(tags)),
                "tier": tier
            }

            if tier == "working":
                working_docs.append(doc)
            else:
                archive_docs.append(doc)

# Write batches
with open("/tmp/core-docs.json", "w") as f:
    json.dump(core_docs, f)
with open("/tmp/working-docs.json", "w") as f:
    json.dump(working_docs, f)
with open("/tmp/archive-docs.json", "w") as f:
    json.dump(archive_docs, f)

print(f"Core: {len(core_docs)} | Working: {len(working_docs)} | Archive: {len(archive_docs)}")
PYEOF

# --- Push to MeiliSearch ---
for TIER in core working archive; do
  DOC_FILE="/tmp/${TIER}-docs.json"
  if [ ! -f "$DOC_FILE" ]; then continue; fi

  DOC_COUNT=$(python3 -c "import json; print(len(json.load(open('${DOC_FILE}'))))" 2>/dev/null || echo 0)
  if [ "$DOC_COUNT" = "0" ]; then continue; fi

  # Push in batches of 20
  python3 - << PYEOF
import json, subprocess, time

with open("${DOC_FILE}") as f:
    docs = json.load(f)

ms_host = "${MS_HOST}"
ms_key = "${MS_KEY}"
tier = "${TIER}"

for i in range(0, len(docs), 20):
    batch = docs[i:i+20]
    with open("/tmp/batch.json", "w") as f:
        json.dump(batch, f)
    subprocess.run([
        "curl", "-s", "-X", "POST",
        f"{ms_host}/indexes/{tier}/documents",
        "-H", f"Authorization: Bearer {ms_key}",
        "-H", "Content-Type: application/json",
        "-d", "@/tmp/batch.json"
    ], capture_output=True, text=True)
    time.sleep(0.3)

print(f"  {tier}: {len(docs)} documents indexed")
PYEOF
done

# --- Print stats ---
echo ""
echo "=== Index Stats ==="
for TIER in core working archive; do
  STATS=$(curl -s "${MS_HOST}/indexes/${TIER}/stats" -H "Authorization: Bearer ${MS_KEY}" 2>/dev/null)
  COUNT=$(echo "$STATS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('numberOfDocuments','?'))" 2>/dev/null || echo "?")
  echo "  ${TIER}: ${COUNT} documents"
done
echo ""
echo "Done. Use search.sh to query: bash ../search.sh 'your query'"
