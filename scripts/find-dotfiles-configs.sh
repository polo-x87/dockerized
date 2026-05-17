#!/usr/bin/env bash
# find-dotfiles-configs.sh — locate real dotfiles / env / toml configs on host or in devbox.
#
# Matches paths from base/dotfiles-sample (install.sh manifest), then scans for
# dockerize-project configs (mcp.json, base/.env, Cursor MCP, vault rules, etc.).
#
# Usage:
#   scripts/find-dotfiles-configs.sh              # interactive menu per hit
#   scripts/find-dotfiles-configs.sh --list       # machine-readable report
#   scripts/find-dotfiles-configs.sh --scope all  # host + devbox container
#   DOTFILES_TARGET=~/vault/dotfiles scripts/find-dotfiles-configs.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
SAMPLE_DIR="$REPO_ROOT/base/dotfiles-sample"

HOME_DIR="${HOME_DIR:-$HOME}"
DOTFILES_TARGET="${DOTFILES_TARGET:-${DOTFILES_REPO_PATH:-$HOME/vault/dotfiles}}"
SCOPE="${SCOPE:-host}"          # host | container | all
MODE="${MODE:-}"                # list | interactive (auto from tty)
CONTAINER_NAME="${DEVBOX_CONTAINER:-devbox}"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; }

usage() {
    cat <<EOF
find-dotfiles-configs — resolve real config paths for dotfiles export

USAGE
    $(basename "$0") [options]

OPTIONS
    --list              Print findings (tab-separated); no prompts
    --interactive       Prompt per file (default when stdout is a tty)
    --scope host        Only inspect paths on this machine (\$HOME)
    --scope container   Only inspect inside the devbox container
    --scope all         Host, then container (if devbox is running)
    --target DIR        Dotfiles repo for copy actions (default: \$DOTFILES_TARGET)
    --home DIR          Home directory to inspect (default: \$HOME)
    -h, --help          Show this message

ENV
    DOTFILES_TARGET     Destination repo for copy actions
    DEVBOX_CONTAINER    Container name (default: devbox)

Each manifest entry is checked at its live path (~/.zshrc, ~/.config/op/claude.env, …).
Symlinks are resolved. Secret-bearing files are flagged; copy-as-example is preferred.
EOF
}

realpath_p() {
    local p="$1"
    [ -e "$p" ] || [ -L "$p" ] || return 1
    python3 -c 'import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$p" 2>/dev/null \
        || readlink -f "$p" 2>/dev/null \
        || printf '%s\n' "$p"
}

container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER_NAME"
}

# Run a shell snippet inside devbox; prints stdout only.
container_eval() {
    docker exec -u dev "$CONTAINER_NAME" /usr/bin/env bash -lc "$1" 2>/dev/null
}

# manifest line: category|id|home_relpath|sample_relpath|repo_relpath|notes
# sample_relpath empty => no bundled sample; repo_relpath empty => not in dockerize repo
MANIFEST=(
    'sample|zshrc|.zshrc|.zshrc||'
    'sample|tmux|.tmux.conf|.tmux.conf||'
    'sample|gitconfig|.gitconfig|.gitconfig||'
    'sample|mise|.config/mise/config.toml|.config/mise/config.toml||'
    'sample|lazydocker|.config/jesseduffield/lazydocker/config.yml|.config/jesseduffield/lazydocker/config.yml||'
    'sample|op-claude|.config/op/claude.env|.config/op/claude.env.example||live op env'
    'sample|op-codex|.config/op/codex.env|.config/op/codex.env.example||'
    'sample|op-gemini|.config/op/gemini.env|.config/op/gemini.env.example||'
    'sample|op-deepseek|.config/op/deepseek.env|.config/op/deepseek.env.example||'
    'project|dockerize-mcp|.cursor/mcp.json||mcp.json|sync-cursor-mcp.sh target'
    'project|dockerize-env-example|||base/.env.example|committed template'
    'project|dockerize-env|||base/.env|gitignored; may contain secrets'
    'project|dockerize-compose|||base/docker-compose.yml|compose file'
    'project|ssh-devbox|.ssh/config|||install-host.sh writes Host devbox'
    'project|cursor-rule|.cursor/rules/devbox-pointer.mdc||~/vault/.cursor/rules/devbox-pointer.mdc|vault Cursor rule'
    'project|code-workspace|||dockerize.code-workspace|multi-root workspace'
    'discover|atuin|.config/atuin/config.toml||optional; atuin sync|'
    'discover|direnv|.config/direnv/direnvrc||optional; mentioned in design spec|'
)

resolve_repo_path() {
    local rel="$1"
    [ -n "$rel" ] || return 1
    if [ "${rel#\~/}" != "$rel" ]; then
        rel="${HOME_DIR}/${rel#\~/}"
    fi
    case "$rel" in
        /*) printf '%s\n' "$rel" ;;
        *)  printf '%s/%s\n' "$REPO_ROOT" "$rel" ;;
    esac
}

looks_secret() {
    local path="$1"
    case "$path" in
        *.env|*.env.*) return 0 ;;
    esac
    case "$(basename "$path")" in
        .env) return 0 ;;
    esac
    return 1
}

# Probe one side (host paths use HOME_DIR; container uses /home/dev inside eval)
probe_entry() {
    local where="$1"
    IFS='|' read -r cat id home_rel sample_rel repo_rel notes <<<"$2"

    local live="" sample="" repo="" status="missing"

    # Paths under ~ (or repo-only entries on host)
    if [ -n "$home_rel" ]; then
        case "$home_rel" in
            "${HOME}"/*) home_rel="${home_rel#"${HOME}"/}" ;;
            "${HOME_DIR}"/*) home_rel="${home_rel#"${HOME_DIR}"/}" ;;
        esac
        if [ "$where" = host ]; then
            live="$HOME_DIR/$home_rel"
            if [ -e "$live" ] || [ -L "$live" ]; then
                status=found
                live="$(realpath_p "$live" 2>/dev/null || echo "$live")"
            fi
        elif container_running; then
            local qhome_rel="${home_rel//\'/\'\\\'\'}"
            live="$(container_eval "
                p=\"\$HOME/$qhome_rel\"
                if [ -e \"\$p\" ] || [ -L \"\$p\" ]; then
                    realpath \"\$p\" 2>/dev/null || readlink -f \"\$p\" 2>/dev/null || echo \"\$p\"
                fi
            " || true)"
            if [ -n "$live" ]; then
                status=found
            fi
        else
            status=skipped
        fi
    fi

    if [ -n "$sample_rel" ]; then
        sample="$SAMPLE_DIR/$sample_rel"
        [ -f "$sample" ] || sample=""
    fi

  # Repo paths (always resolved on host filesystem)
    if [ -n "$repo_rel" ] && [ "$where" = host ]; then
        repo="$(resolve_repo_path "$repo_rel" 2>/dev/null || true)"
        if [ -n "$repo" ] && [ -e "$repo" ]; then
            repo="$(realpath_p "$repo" 2>/dev/null || echo "$repo")"
            if [ "$status" != found ]; then
                live="$repo"
                status=found
            fi
        else
            repo=""
        fi
    fi

    # ssh config — only count if Host devbox is present
    if [ "$id" = ssh-devbox ] && [ "$status" = found ] && [ "$where" = host ]; then
        grep -q '^Host devbox$' "$live" 2>/dev/null || status=missing
    fi

    # Skip duplicate repo-only rows on container pass
    if [ -z "$home_rel" ] && [ "$where" = container ]; then
        return 0
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$where" "$cat" "$id" "$status" "${live:-}" "${sample:-}" "${repo:-}" "$notes"
}

collect_findings() {
    local where
    for where in $(scopes_to_probe); do
        local line
        for line in "${MANIFEST[@]}"; do
            probe_entry "$where" "$line"
        done
    done

    # Extra: any live ~/.config/op/*.env not in manifest
    local opdir="$HOME_DIR/.config/op"
    if [ -d "$opdir" ] && [[ " $(scopes_to_probe) " == *" host "* ]]; then
        local f
        for f in "$opdir"/*.env; do
            [ -f "$f" ] || continue
            local bname; bname="$(basename "$f")"
            local id="op-${bname%.env}"
            local dup=0
            for line in "${MANIFEST[@]}"; do
                IFS='|' read -r _ mid _ _ _ <<<"$line"
                [ "$mid" = "$id" ] && dup=1 && break
            done
            [ "$dup" -eq 1 ] && continue
            local resolved; resolved="$(realpath_p "$f" 2>/dev/null || echo "$f")"
            printf 'host\tdiscover\t%s\tfound\t%s\t\t\textra op env\n' "$id" "$resolved"
        done
    fi
}

scopes_to_probe() {
    case "$SCOPE" in
        host)      printf 'host\n' ;;
        container) printf 'container\n' ;;
        all)       printf 'host\ncontainer\n' ;;
        *)         err "unknown scope: $SCOPE"; exit 2 ;;
    esac
}

print_list() {
    printf 'where\tcategory\tid\tstatus\tlive_path\tsample_path\trepo_path\tnotes\n'
    collect_findings | sort -t$'\t' -k1,1 -k3,3
}

show_info() {
    local live="$1"
    say "live:  $live"
    if [ -L "${live%/*}/$(basename "$live")" ] 2>/dev/null; then
        :
    fi
    if [ -f "$live" ]; then
        ls -la "$live"
        wc -c "$live" | awk '{print "size: " $1 " bytes"}'
    fi
    if looks_secret "$live"; then
        warn "treat as secret — prefer copying as *.env.example only"
    fi
}

show_diff() {
    local live="$1" sample="$2"
    if [ -z "$sample" ]; then
        warn "no sample file in dotfiles-sample"
        return
    fi
    if [ ! -f "$live" ]; then
        warn "live file missing"
        return
    fi
    diff -u "$sample" "$live" || true
}

redact_env_to_example() {
    local src="$1" dest="$2"
    awk '
        /^[[:space:]]*#/ { print; next }
        /^[[:space:]]*$/ { print; next }
        /^[A-Za-z_][A-Za-z0-9_]*=/ {
            split($0, a, "=")
            key=a[1]
            if (key ~ /(KEY|TOKEN|SECRET|PASSWORD)/) {
                print key "=op://VAULT/Item/field"
            } else {
                print key "="
            }
            next
        }
        { print }
    ' "$src" >"$dest"
}

copy_to_dotfiles() {
    local live="$1" sample_rel="$2" as_example="${3:-0}"
    local dest_root="${DOTFILES_TARGET:-$HOME/vault/dotfiles}"

    if [ ! -d "$dest_root" ]; then
        warn "dotfiles target missing: $dest_root"
        read -r -p "Create it? [y/N] " ans
        case "$ans" in
            y|Y) mkdir -p "$dest_root" ;;
            *) return 1 ;;
        esac
    fi

    local rel="$sample_rel"
    if [ -z "$rel" ]; then
        # infer from live path under HOME
        case "$live" in
            "$HOME_DIR"/*) rel="${live#"$HOME_DIR"/}" ;;
            *) err "cannot infer dotfiles path for $live"; return 1 ;;
        esac
    fi

    if [ "$as_example" -eq 1 ]; then
        rel="${rel%.env}.env.example"
    fi

    local dest="$dest_root/$rel"
    mkdir -p "$(dirname "$dest")"

    if looks_secret "$live" && [ "$as_example" -eq 0 ]; then
        warn "refusing verbatim copy of likely-secret file"
        warn "use option: copy as .env.example (redacted)"
        return 1
    fi

    if [ "$as_example" -eq 1 ]; then
        redact_env_to_example "$live" "$dest"
        say "wrote redacted example → $dest"
    else
        cp -f "$live" "$dest"
        say "copied → $dest"
    fi
}

interactive_loop() {
    local target_dir="${DOTFILES_TARGET:-$HOME/vault/dotfiles}"
    target_dir="$(cd "$target_dir" 2>/dev/null && pwd || echo "$target_dir")"
    DOTFILES_TARGET="$target_dir"
    say "dotfiles target: $DOTFILES_TARGET"
    say "sample dir:      $SAMPLE_DIR"
    echo

    while IFS= read -r row; do
        [ -z "$row" ] && continue
        IFS=$'\t' read -r where cat id status live sample repo notes <<<"$row"
        [ "$status" = skipped ] && continue

        printf '\n\033[1m[%s/%s] %s\033[0m  (%s)\n' "$where" "$cat" "$id" "$status"
        [ -n "$live" ]  && printf '  live:   %s\n' "$live"
        [ -n "$sample" ] && printf '  sample: %s\n' "$sample"
        [ -n "$repo" ]  && printf '  repo:   %s\n' "$repo"
        [ -n "$notes" ] && printf '  note:   %s\n' "$notes"

        if [ "$status" != found ]; then
            printf '  (s)kip  (q)uit > '
            read -r choice || break
            case "$choice" in q|Q) break ;; *) continue ;; esac
        fi

        local sample_rel=""
        if [ -n "$sample" ]; then
            sample_rel="${sample#"$SAMPLE_DIR"/}"
        fi

        cat <<MENU
  (i) info   (d) diff vs sample   (c) copy to dotfiles repo
  (e) copy as .env.example (redacted)   (s)kip   (q)uit
MENU
        printf '> '
        read -r choice || break
        case "$choice" in
            i|I) show_info "$live" ;;
            d|D) show_diff "$live" "$sample" ;;
            c|C) copy_to_dotfiles "$live" "$sample_rel" 0 ;;
            e|E)
                if looks_secret "$live"; then
                    copy_to_dotfiles "$live" "$sample_rel" 1
                else
                    warn "not a secret env file; use (c)opy instead"
                fi
                ;;
            q|Q) break ;;
            s|S|"") continue ;;
            *) warn "unknown choice" ;;
        esac
    done < <(collect_findings | sort -t$'\t' -k1,1 -k3,3)
}

# --- parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --list)        MODE=list; shift ;;
        --interactive) MODE=interactive; shift ;;
        --scope)       SCOPE="$2"; shift 2 ;;
        --target)      DOTFILES_TARGET="$2"; shift 2 ;;
        --home)        HOME_DIR="$2"; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        *)             err "unknown arg: $1"; usage; exit 2 ;;
    esac
done

if [ -z "$MODE" ]; then
    if [ -t 1 ]; then
        MODE=interactive
    else
        MODE=list
    fi
fi

case "$MODE" in
    list)
        print_list
        ;;
    interactive)
        interactive_loop
        ;;
    *)
        err "unknown mode: $MODE"
        exit 2
        ;;
esac
