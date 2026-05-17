#!/usr/bin/env bash
# seed-op-env.sh — copy op/*.env.example to ~/.config/op/ on the Mac host (never overwrite).
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC="$HERE/../base/dotfiles-sample/.config/op"
DEST="${OP_ENV_DEST:-$HOME/.config/op}"

mkdir -p "$DEST"
for example in "$SRC"/*.env.example; do
    [ -f "$example" ] || continue
    target="$DEST/$(basename "${example%.example}")"
    if [ ! -f "$target" ]; then
        cp "$example" "$target"
        echo "seed-op-env: created $target"
    fi
done
echo "seed-op-env: edit op:// references, then: op signin"
