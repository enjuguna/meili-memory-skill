# MeiliSearch Memory Skill

Local full-text search for OpenClaw memory recall. No API keys, no cloud services, no GPU needed — runs entirely on your server.

## Why?

OpenClaw's built-in vector search requires embedding APIs (Jina, OpenAI, etc.) and API keys. This skill replaces that with **MeiliSearch** — a lightweight, open-source search engine running locally on your machine.

**Benefits:**
- 🔒 No API keys or external services
- ⚡ Sub-second search results
- 🔍 Typo tolerance and relevance ranking out of the box
- 📁 Indexes your existing `MEMORY.md` and daily notes
- 🔄 Auto-syncs via cron (hourly)

## Architecture

```
MEMORY.md ──┐
             ├──→ indexer.sh ──→ MeiliSearch (127.0.0.1:7700)
daily notes ─┘                       │
                                     │
memory_search ←── search.sh ←────────┘
```

- **Indexer** reads `MEMORY.md` (chunked by section) and `memory/*.md` daily notes (chunked by 1500 chars), pushes to MeiliSearch
- **Search** queries MeiliSearch with full-text search, returns ranked results
- **Cron** runs the indexer every hour to pick up new files

## Requirements

- Linux server (amd64)
- OpenClaw installed
- ~50MB disk space for MeiliSearch binary + data

## Quick Install

```bash
git clone https://github.com/enjuguna/meili-memory-skill.git
cd meili-memory-skill
bash install.sh
```

The install script will:
1. Download and install the MeiliSearch binary
2. Generate a master key
3. Set up MeiliSearch as a systemd service (auto-starts on boot)
4. Install skill files to `~/.openclaw/workspace/skills/meili-memory/`
5. Configure hourly auto-indexing via cron
6. Run the initial index

## Manual Usage

```bash
# Search
bash scripts/search.sh "your query" [limit]

# Reindex (incremental)
bash scripts/indexer.sh

# Full reindex (deletes and rebuilds)
bash scripts/indexer.sh --full

# Check service status
systemctl status meilisearch

# View logs
journalctl -u meilisearch -f
```

## Configuration

Edit the scripts to customize:
- `MS_HOST` — MeiliSearch address (default: `http://127.0.0.1:7700`)
- `MS_KEY` — Master key (auto-generated during install)
- `INDEX` — Index name (default: `memories`)
- Chunk size — 1500 chars for daily notes (edit `indexer.sh`)

## How It Integrates with OpenClaw

When the agent needs to recall something, it runs `search.sh` with the query and gets back relevant chunks from `MEMORY.md` and daily notes. This context is then used to answer the user's question — same as vector search, but with better accuracy and zero external dependencies.

## License

MIT

## Install from ClawHub

```bash
openclaw skills install meili-memory
```

Or browse at [clawhub.ai/enjuguna/meili-memory](https://clawhub.ai/enjuguna/meili-memory)
