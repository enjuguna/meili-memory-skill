# MeiliSearch Memory Skill

Local full-text search for OpenClaw memory recall. No API keys, no cloud services, no GPU needed — runs entirely on your server.

## Why?

OpenClaw's built-in vector search requires embedding APIs (Jina, OpenAI, etc.) and API keys. This skill replaces that with **MeiliSearch** — a lightweight, open-source search engine running locally on your machine.

**Benefits:**
- 🔒 No API keys or external services
- ⚡ Sub-second search results
- 🔍 Typo tolerance and relevance ranking out of the box
- 📁 Indexes your existing `MEMORY.md` and daily notes
- 🔄 Auto-syncs via cron (hourly indexing + weekly distillation)
- 🧠 Three-tier memory system that mimics human recall

## Architecture

```
MEMORY.md ──┐
             ├──→ indexer.sh ──→ MeiliSearch (127.0.0.1:7700)
daily notes ─┘                       │
                                     │
memory_search ←── search.sh ←────────┘
```

### Three-Tier Memory System

| Tier | Source | Retention | Importance |
|------|--------|-----------|------------|
| **Core** | MEMORY.md sections | Always | 0.95 |
| **Working** | Daily notes (last 7 days) | 7 days | 0.60 |
| **Archive** | Older daily notes | Forever | 0.30 |

Search queries hit all tiers in order: core → working → archive. Results are ranked by tier priority and importance score — so your most important memories surface first.

### Synonym Expansion

Queries are automatically expanded with related terms. For example, searching "debts" also matches "liabilities", "rent", "KES", "loan", "HELB", etc. Configured in `synonyms.json`.

### Relationship Tags

Each memory chunk is auto-tagged based on content:
- `#finance/debts`, `#finance/budget`
- `#project/molthub`, `#project/budget-tracker`
- `#identity`, `#auth/github`, `#auth/google`
- `#schedule`, `#skills`, `#infrastructure/openclaw`

### Memory Distillation

A weekly cron job scans recent daily notes, extracts meaningful facts, and appends them to `MEMORY.md`. This keeps your core memory fresh without manual editing. Raw daily notes stay in the archive for deep recall.

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
5. Configure hourly auto-indexing + weekly distillation via cron
6. Run the initial index

## Manual Usage

```bash
# Search all tiers
bash scripts/search.sh "your query" [limit]

# Search core only (fast, high-priority memories)
bash scripts/search.sh "your query" 5 core

# Reindex (incremental)
bash scripts/indexer.sh

# Full reindex (wipes and rebuilds)
bash scripts/indexer.sh --full

# Preview distillation
bash scripts/distill.sh --dry-run

# Run distillation now
bash scripts/distill.sh

# Check service status
systemctl status meilisearch
```

## File Structure

```
meili-memory/
├── SKILL.md              # Skill documentation
├── synonyms.json         # Query synonym mappings
├── scripts/
│   ├── search.sh         # Tiered search with synonym expansion
│   ├── indexer.sh        # Tiered indexer (core/working/archive)
│   └── distill.sh        # Weekly memory distillation
└── install.sh            # One-command installer
```

## Configuration

Edit the scripts to customize:
- `MS_HOST` — MeiliSearch address (default: `http://127.0.0.1:7700`)
- `MS_KEY` — Master key (auto-generated during install)
- `synonyms.json` — Add your own synonym groups
- Chunk size — 1500 chars for daily notes (edit `indexer.sh`)
- Distillation schedule — Edit the cron job (`crontab -e`)

## Cron Jobs

```
# Hourly: reindex new daily notes
0 * * * * cd ~/.openclaw/workspace/skills/meili-memory && bash scripts/indexer.sh >> /tmp/meili-indexer.log 2>&1

# Weekly (Sunday 2 AM): distill facts into MEMORY.md
0 2 * * 0 cd ~/.openclaw/workspace/skills/meili-memory && bash scripts/distill.sh >> /tmp/meili-distill.log 2>&1
```

## How It Integrates with OpenClaw

When the agent needs to recall something, it runs `search.sh` with the query and gets back relevant chunks from `MEMORY.md` and daily notes. Results are ranked by importance (core > working > archive) and include relationship tags for finding related context. This replaces vector search with better accuracy and zero external dependencies.

## Install from ClawHub

```bash
openclaw skills install meili-memory
```

Or browse at [clawhub.ai/enjuguna/meili-memory](https://clawhub.ai/enjuguna/meili-memory)

## License

MIT
