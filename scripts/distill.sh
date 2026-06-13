#!/bin/bash
# Memory distillation: extract key facts from daily notes and append to MEMORY.md
# Runs weekly via cron
# Usage: bash distill.sh [--dry-run]

set -e

WORKSPACE="/root/.openclaw/workspace"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN="${1}"

echo "=== Memory Distillation ==="

python3 - "${WORKSPACE}" "${DRY_RUN}" << 'PYEOF'
import json, os, glob, sys, subprocess
from datetime import datetime, timedelta

workspace = sys.argv[1]
dry_run = sys.argv[2] if len(sys.argv) > 2 else None

daily_dir = f"{workspace}/memory"
memory_file = f"{workspace}/MEMORY.md"

with open(memory_file, "r") as f:
    existing_content = f.read().lower()

week_ago = datetime.now() - timedelta(days=7)
new_facts = []
files_processed = 0

# Patterns that indicate a meaningful fact (not conversation noise)
FACT_INDICATORS = [
    "is a", "was created", "has been", "will be", "should be",
    "decided to", "agreed to", "plan to", "need to", "want to",
    "installed", "configured", "set up", "deployed", "published",
    "total", "amount", "costs", "price", "budget",
    "every day", "every week", "scheduled", "cron",
    "password", "token", "key", "credential",
    "IP address", "domain", "URL", "endpoint",
    "phone", "email", "address",
]

# Patterns to skip (conversation noise)
SKIP_PATTERNS = [
    "user:", "assistant:", "tool_call", "tool_result",
    "session key", "session id", "source:", "---", "```",
    "thinking", "let me", "i'll ", "i will", "i'm going",
    "sure!", "great!", "okay", "yes,", "no,",
    "```json", "```bash", "```python",
    "curl ", "npm ", "git ", "systemctl",
    "echo ", "cat ", "grep ", "sed ",
]

def is_meaningful_fact(line):
    """Check if a line contains a meaningful fact"""
    line_lower = line.lower()

    # Skip short lines
    if len(line) < 30:
        return False

    # Skip lines that look like conversation
    for skip in SKIP_PATTERNS:
        if skip in line_lower:
            return False

    # Skip lines that are mostly code
    code_chars = sum(1 for c in line if c in '{}[]()`|><;=')
    if code_chars > len(line) * 0.15:
        return False

    # Check if it contains fact-like content
    for indicator in FACT_INDICATORS:
        if indicator in line_lower:
            return True

    # Lines with specific data patterns
    import re
    if re.search(r'\d+\s*(KES|USD|EUR|GBP|%|days?|weeks?|months?)', line):
        return True
    if re.search(r'https?://', line):
        return True

    return False

def clean_fact(line):
    """Clean up a fact line"""
    # Remove markdown formatting
    line = line.strip()
    line = line.lstrip("-*•▪▸→ ").strip()
    # Remove bold/italic markers but keep text
    import re
    line = re.sub(r'\*\*(.+?)\*\*', r'\1', line)
    line = re.sub(r'\*(.+?)\*', r'\1', line)
    line = re.sub(r'`(.+?)`', r'\1', line)
    # Truncate
    if len(line) > 200:
        line = line[:200] + "..."
    return line

for fname in sorted(glob.glob(f"{daily_dir}/*.md")):
    try:
        file_date = datetime.strptime(os.path.basename(fname)[:10], "%Y-%m-%d")
    except:
        continue
    if file_date < week_ago:
        continue

    with open(fname, "r") as f:
        content = f.read()
    if len(content) < 100:
        continue

    files_processed += 1

    # Only look at assistant messages (facts the agent stated)
    in_assistant = False
    for line in content.split("\n"):
        line = line.strip()

        # Track assistant message blocks
        if line.startswith("assistant:") or line.startswith("⚔️"):
            in_assistant = True
            continue
        if line.startswith("user:") or line.startswith("---"):
            in_assistant = False
            continue

        if not in_assistant and not line.startswith("-") and not line.startswith("*"):
            continue

        clean = clean_fact(line)
        if not clean:
            continue
        if clean.lower() in existing_content:
            continue
        if is_meaningful_fact(clean):
            new_facts.append({
                "fact": clean,
                "source": os.path.basename(fname),
                "date": file_date.strftime("%Y-%m-%d")
            })

# Deduplicate similar facts
unique_facts = []
seen_texts = set()
for f in new_facts:
    # Simple dedup: skip if first 50 chars match
    key = f["fact"][:50].lower()
    if key not in seen_texts:
        seen_texts.add(key)
        unique_facts.append(f)

print(f"Files scanned: {files_processed}")
print(f"Unique facts found: {len(unique_facts)}")

if unique_facts and not dry_run:
    distillation = f"\n\n## Recent Facts (Distilled {datetime.now().strftime('%Y-%m-%d')})\n\n"
    for f in unique_facts[:15]:
        distillation += f"- {f['fact']} *(from {f['source']})*\n"

    with open(memory_file, "a") as f:
        f.write(distillation)
    print(f"Appended {min(len(unique_facts), 15)} facts to MEMORY.md")

    print("Triggering re-index...")
    subprocess.run(["bash", f"{SKILL_DIR}/scripts/indexer.sh"], capture_output=True, text=True)
    print("Re-index complete")

elif unique_facts and dry_run:
    print("\n[DRY RUN] Would add:")
    for f in unique_facts[:15]:
        print(f"  - {f['fact'][:100]}")
else:
    print("No new facts to distill.")
PYEOF

echo "=== Done ==="
