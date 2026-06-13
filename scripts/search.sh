#!/bin/bash
# Search MeiliSearch memories index
# Usage: bash search.sh "query" [limit]
# Returns JSON results

QUERY="${1}"
LIMIT="${2:-5}"
MS_HOST="http://127.0.0.1:7700"
MS_KEY="ms-323a144af37bf9ab26ddc8bc4edd1b3c"
INDEX="memories"

if [ -z "$QUERY" ]; then
  echo '{"error":"Usage: search.sh <query> [limit]"}' >&2
  exit 1
fi

curl -s "${MS_HOST}/indexes/${INDEX}/search" \
  -H "Authorization: Bearer ${MS_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"q\":\"${QUERY}\",\"limit\":${LIMIT},\"attributesToRetrieve\":[\"id\",\"text\",\"source\",\"file\",\"category\",\"importance\",\"date\"],\"attributesToHighlight\":[\"text\"],\"highlightPreTag\":\"\",\"highlightPostTag\":\"\"}"
