#!/usr/bin/env bash
# check-docs-sync.sh — enforce CLAUDE.md Hard rule #8.
#
# Fails (exit 1) if the staged changeset touches code/config paths
# without also touching at least one doc file. Run by the pre-commit
# hook installed via scripts/install-git-hooks.sh.
#
# Override for genuine doc-only-irrelevant changes:
#   SKIP_DOCS_CHECK=1 git commit -m '...'
#   git commit --no-verify ...           # bypasses ALL hooks
#
# Exit codes:
#   0  ok (no code paths staged, or docs updated alongside)
#   1  code paths staged without docs — commit blocked
#   2  not in a git repo / no staged files
set -euo pipefail

if [ "${SKIP_DOCS_CHECK:-0}" = "1" ]; then
    exit 0
fi

# Paths that, when staged, require a matching docs update.
# Regex anchored to the start of each path (output of `git diff --cached --name-only`).
CODE_PATTERNS=(
    '^base/'
    '^scripts/'
    '^overlays/'
    '^mcp\.json$'
    '^devcontainer\.json$'
    '^docker-compose(\..+)?\.yml$'
    '^Dockerfile(\..+)?$'
    '^env\.txt$'
)

# Paths that count as "docs touched".
DOC_PATTERNS=(
    '^CLAUDE\.md$'
    '^README\.md$'
    '^docs/'
    '\.md$'           # any markdown anywhere (mcp_workflow.md, overlays/.../README.md, …)
)

# Staged file list (added, copied, modified, renamed, type-changed).
if ! staged=$(git diff --cached --name-only --diff-filter=ACMRT 2>/dev/null); then
    echo "check-docs-sync: not a git repository or git unavailable" >&2
    exit 2
fi

if [ -z "$staged" ]; then
    exit 0
fi

matches_any() {
    local file="$1"; shift
    local pat
    for pat in "$@"; do
        if printf '%s' "$file" | grep -Eq "$pat"; then
            return 0
        fi
    done
    return 1
}

code_hits=()
doc_hits=()

while IFS= read -r f; do
    [ -z "$f" ] && continue
    if matches_any "$f" "${CODE_PATTERNS[@]}"; then
        code_hits+=("$f")
    fi
    if matches_any "$f" "${DOC_PATTERNS[@]}"; then
        doc_hits+=("$f")
    fi
done <<< "$staged"

# No code paths staged → nothing to enforce.
if [ "${#code_hits[@]}" -eq 0 ]; then
    exit 0
fi

# Code staged AND docs staged → ok.
if [ "${#doc_hits[@]}" -gt 0 ]; then
    exit 0
fi

# Code staged, no docs → block.
{
    printf '\n\033[1;31m✘ docs-sync rule (CLAUDE.md Hard rule #8) violated\033[0m\n'
    printf '\nstaged code/config files:\n'
    for f in "${code_hits[@]}"; do printf '  - %s\n' "$f"; done
    printf '\nno doc files staged. update one or more of:\n'
    printf '  - CLAUDE.md           (rules, workflow, layout)\n'
    printf '  - README.md           (user-facing what'\''s where / quick-start)\n'
    printf '  - docs/usage.md       (daily workflows, common problems)\n'
    printf '  - docs/guide.html     (any generated artifact)\n'
    printf '  - docs/cli-mesh.html  (tools, configs, risk nodes in the mesh)\n'
    printf '  - mcp_workflow.md     (Python research-system Dockerfile pattern)\n'
    printf '\noverride (use sparingly):\n'
    printf '  SKIP_DOCS_CHECK=1 git commit ...\n'
    printf '  git commit --no-verify ...\n\n'
} >&2

exit 1
