#!/bin/bash
# Tiered memory search with synonym expansion
# Usage: bash search.sh "query" [limit] [tier]
# Tiers: core, working, archive, all (default: all)

QUERY="${1}"
LIMIT="${2:-5}"
FILTER_TIER="${3:-all}"
MS_HOST="http://127.0.0.1:7700"
MS_KEY="ms-323a144af37bf9ab26ddc8bc4edd1b3c"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNONYMS_FILE="${SKILL_DIR}/synonyms.json"

if [ -z "$QUERY" ]; then
  echo '{"error":"Usage: search.sh <query> [limit] [tier]"}' >&2
  exit 1
fi

# Expand query with synonyms
expand_query() {
  python3 - "$QUERY" "$SYNONYMS_FILE" << 'PYEOF'
import json, sys

query = sys.argv[1].lower()
synonyms_file = sys.argv[2]

with open(synonyms_file) as f:
    synonyms = json.load(f)

expanded = [query]
for group_name, terms in synonyms.items():
    for term in terms:
        if term.lower() in query:
            # Add other terms from this group
            for t in terms:
                if t.lower() != term.lower():
                    expanded.append(f"{query} {t}")
            break

# Return unique expansions (limit to 5 to avoid query explosion)
seen = set()
result = []
for e in expanded:
    if e not in seen and len(result) < 5:
        seen.add(e)
        result.append(e)

print(" OR ".join(result))
PYEOF
}

EXPANDED=$(expand_query)

# Determine which tiers to search
if [ "$FILTER_TIER" = "all" ]; then
  TIERS="core working archive"
else
  TIERS="$FILTER_TIER"
fi

# Search each tier, collect results
python3 - "$EXPANDED" "$LIMIT" "$TIERS" "$MS_HOST" "$MS_KEY" << 'PYEOF'
import json, subprocess, sys, time

query = sys.argv[1]
limit = int(sys.argv[2])
tiers = sys.argv[3].split()
ms_host = sys.argv[4]
ms_key = sys.argv[5]

all_results = []
seen_ids = set()

for tier in tiers:
    # Search with filter for this tier
    payload = json.dumps({
        "q": query,
        "limit": limit,
        "attributesToRetrieve": ["id", "text", "source", "file", "category", "importance", "date", "tags", "tier"],
        "attributesToHighlight": ["text"],
        "highlightPreTag": "**",
        "highlightPostTag": "**"
    })

    result = subprocess.run([
        "curl", "-s",
        f"{ms_host}/indexes/{tier}/search",
        "-H", f"Authorization: Bearer {ms_key}",
        "-H", "Content-Type: application/json",
        "-d", payload
    ], capture_output=True, text=True)

    try:
        data = json.loads(result.stdout)
        hits = data.get("hits", [])
        for h in hits:
            if h["id"] not in seen_ids:
                seen_ids.add(h["id"])
                h["_tier"] = tier
                all_results.append(h)
    except:
        pass

# Sort by importance (core first), then by MeiliSearch ranking
tier_order = {"core": 0, "working": 1, "archive": 2}
all_results.sort(key=lambda x: (tier_order.get(x.get("_tier", "archive"), 2), -x.get("importance", 0)))

# Output top results
output = {
    "query": query,
    "expanded_query": query,
    "tiers_searched": tiers,
    "total_found": len(all_results),
    "results": all_results[:limit]
}
print(json.dumps(output, indent=2))
PYEOF
