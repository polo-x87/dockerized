#!/usr/bin/env bash
# Symlink the sample dotfiles into $HOME. Idempotent.
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

link() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] || [ ! -e "$dst" ]; then
        ln -sfn "$src" "$dst"
    else
        echo "install.sh: $dst exists and is not a symlink — skipping (back it up and re-run)"
    fi
}

link "$HERE/.zshrc"                       "$HOME/.zshrc"
link "$HERE/.tmux.conf"                   "$HOME/.tmux.conf"
link "$HERE/.gitconfig"                   "$HOME/.gitconfig"
link "$HERE/.config/mise/config.toml"     "$HOME/.config/mise/config.toml"
link "$HERE/.config/jesseduffield/lazydocker/config.yml" \
     "$HOME/.config/jesseduffield/lazydocker/config.yml"

# 1Password agent env templates — copy once if missing (never overwrite user files)
mkdir -p "$HOME/.config/op"
for example in "$HERE"/.config/op/*.env.example; do
    [ -f "$example" ] || continue
    dest="$HOME/.config/op/$(basename "${example%.example}")"
    if [ ! -f "$dest" ]; then
        cp "$example" "$dest"
        echo "install.sh: seeded $dest (edit op:// references, then op signin)"
    fi
done

# Boot tmux plugin manager once so resurrect/continuum register
if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 || true
fi

echo "install.sh: dotfiles linked into \$HOME"
