#!/usr/bin/env bash
# install-git-hooks.sh — wire repo-side git hooks into .git/hooks.
#
# Idempotent. Run from anywhere; uses the dockerize repo this script lives in.
# Installs:
#   pre-commit  → scripts/check-docs-sync.sh   (CLAUDE.md Hard rule #8)
#
# To uninstall:  rm .git/hooks/pre-commit
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$HERE/.." && pwd )"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK="$HOOKS_DIR/pre-commit"
CHECKER_REL="scripts/check-docs-sync.sh"
CHECKER="$REPO_ROOT/$CHECKER_REL"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }
fail() { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$REPO_ROOT/.git" ] || fail "$REPO_ROOT is not a git repository"
[ -f "$CHECKER" ]        || fail "checker missing: $CHECKER"
chmod +x "$CHECKER"

mkdir -p "$HOOKS_DIR"

# If a pre-commit already exists and isn't ours, keep it and append.
if [ -e "$HOOK" ] && ! grep -q 'dockerize: docs-sync' "$HOOK" 2>/dev/null; then
    say "existing pre-commit hook found at $HOOK — appending our check"
    cat >> "$HOOK" <<'EOF'

# dockerize: docs-sync (added by scripts/install-git-hooks.sh)
"$(git rev-parse --show-toplevel)/scripts/check-docs-sync.sh" || exit $?
EOF
    chmod +x "$HOOK"
    say "appended."
    exit 0
fi

# Fresh install (or already ours — overwrite to pick up changes).
say "installing pre-commit hook at $HOOK"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# dockerize: docs-sync (installed by scripts/install-git-hooks.sh)
# Enforces CLAUDE.md Hard rule #8 — code/config changes must include docs.
set -e
ROOT="$(git rev-parse --show-toplevel)"
exec "$ROOT/scripts/check-docs-sync.sh"
EOF
chmod +x "$HOOK"
say "done. test it:"
say "  touch base/Dockerfile && git add base/Dockerfile && git commit -m 'test'"
say "  (should fail — then stage a doc file and retry)"
