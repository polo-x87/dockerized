#!/usr/bin/env bash
# sync-cursor-mcp.sh — install repo mcp.json to ~/.cursor/mcp.json (valid JSON, no comments).
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC="$HERE/../mcp.json"
DEST="${CURSOR_MCP_DEST:-$HOME/.cursor/mcp.json}"

if [ ! -f "$SRC" ]; then
    echo "sync-cursor-mcp: missing $SRC" >&2
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
python3 - "$SRC" "$DEST" <<'PY'
import json, re, sys
src, dest = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
text = re.sub(r"^\s*//.*\n", "", text, flags=re.M)
data = json.loads(text)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"sync-cursor-mcp: wrote {dest}")
PY
