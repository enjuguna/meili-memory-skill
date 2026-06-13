---
name: meili-memory
description: Local full-text search for OpenClaw memory recall using MeiliSearch. No API keys, no cloud services — runs entirely on your server.
---

# MeiliSearch Memory

Local full-text search for memory recall. No API keys, no cloud services — runs entirely on your server.

## How it works

- **MeiliSearch** runs as a systemd service on `127.0.0.1:7700`
- Memory documents are stored in the `memories` index
- Documents are chunked from `MEMORY.md` (by section) and daily notes (by 1500 chars)
- The indexer runs automatically via cron and on-demand

## Searching memory

Use the `scripts/search.sh` script to query the index:

```bash
bash scripts/search.sh "your query here" [limit]
```

Returns JSON with matching documents ranked by relevance.

## Indexing / re-indexing

Run the indexer to sync all Markdown files to MeiliSearch:

```bash
bash scripts/indexer.sh
```

This:
1. Reads `MEMORY.md` and splits by `##` sections
2. Reads all `memory/*.md` daily notes and chunks them
3. Pushes to MeiliSearch in batches

## crontab

The indexer runs every hour via cron to pick up new daily notes:

```
0 * * * * cd /root/.openclaw/workspace/skills/meili-memory && bash scripts/indexer.sh >> /tmp/meili-indexer.log 2>&1
```

## Service management

```bash
systemctl status meilisearch    # Check status
systemctl restart meilisearch   # Restart
journalctl -u meilisearch -f   # View logs
```
