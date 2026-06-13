---
name: meili-memory
description: Local full-text search for OpenClaw memory recall using MeiliSearch. No API keys, no cloud services — runs entirely on your server.
---

# MeiliSearch Memory

Local full-text search for memory recall. No API keys, no cloud services — runs entirely on your server.

## Architecture

Three-tier indexing system that mimics human memory:

- **Core** — MEMORY.md sections (highest importance, always current)
- **Working** — Daily notes from the last 7 days (recent context)
- **Archive** — Older daily notes (lower priority)

Search queries hit all tiers in order: core → working → archive. Results are ranked by tier priority and importance score.

## Features

- **Synonym expansion** — "debts" also matches "liabilities", "rent", "KES", etc.
- **Relationship tags** — Each chunk is auto-tagged (#finance/debts, #project/molthub, #identity, etc.)
- **Tiered search** — Query core only for fast answers, or all tiers for deep recall
- **Auto-distillation** — Weekly cron extracts key facts from daily notes into MEMORY.md
- **Typo tolerance** — Built-in fuzzy matching via MeiliSearch

## Search

```bash
bash scripts/search.sh "your query" [limit] [tier]
```

Examples:
```bash
bash scripts/search.sh "debts"           # Search all tiers, top 5
bash scripts/search.sh "projects" 3      # Top 3 from all tiers
bash scripts/search.sh "Eric" 5 core     # Core only (fast)
```

## Indexing

```bash
bash scripts/indexer.sh          # Incremental update
bash scripts/indexer.sh --full   # Full reindex (wipes and rebuilds)
```

## Distillation

```bash
bash scripts/distill.sh          # Extract facts → MEMORY.md
bash scripts/distill.sh --dry-run # Preview what would be added
```

## Cron Jobs

- **Hourly** — Re-index new daily notes
- **Weekly (Sunday 2 AM)** — Distill facts into MEMORY.md

## Service

```bash
systemctl status meilisearch
journalctl -u meilisearch -f
```
