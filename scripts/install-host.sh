#!/usr/bin/env bash
# install-host.sh — one-time host (macOS) setup for devbox.
#
# Idempotent. Run from anywhere; uses the dockerize repo this script lives in.
#
# Does:
#   1. Checks for OrbStack (or Docker Desktop); prompts if absent.
#   2. Generates ~/.ssh/devbox_ed25519 if missing.
#   3. Adds an entry to ~/.ssh/config (idempotent).
#   4. Copies base/.env.example → base/.env if .env doesn't exist.
#   5. Ensures ~/code exists.
#   6. Adds the dockerize/scripts dir to PATH (via ~/.zshrc, if missing).
#   7. Installs the docs-sync git pre-commit hook (CLAUDE.md Hard rule #8).
set -euo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$HERE/.." && pwd )"
BASE_DIR="$REPO_ROOT/base"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*" >&2; }

# 1. Container runtime check
say "checking container runtime"
if command -v orb >/dev/null 2>&1; then
    say "  OrbStack found"
elif docker info >/dev/null 2>&1; then
    say "  docker found (assuming Docker Desktop or Podman)"
else
    warn "no container runtime running."
    warn "install OrbStack (recommended on macOS):  brew install orbstack"
    warn "or:                                       https://orbstack.dev/download"
    exit 1
fi

# 2. SSH key
SSH_KEY="$HOME/.ssh/devbox_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    say "generating SSH key at $SSH_KEY"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "devbox@$(hostname)"
else
    say "SSH key already exists: $SSH_KEY"
fi

# 3. ~/.ssh/config entry
SSH_CFG="$HOME/.ssh/config"
touch "$SSH_CFG"
chmod 600 "$SSH_CFG"
if ! grep -q '^Host devbox$' "$SSH_CFG" 2>/dev/null; then
    say "adding 'devbox' to $SSH_CFG"
    {
        echo ""
        echo "Host devbox"
        echo "    HostName 127.0.0.1"
        echo "    Port 2222"
        echo "    User dev"
        echo "    IdentityFile $SSH_KEY"
        echo "    ForwardAgent yes"
        echo "    StrictHostKeyChecking accept-new"
        echo "    UserKnownHostsFile ~/.ssh/known_hosts_devbox"
    } >> "$SSH_CFG"
else
    say "'devbox' already in $SSH_CFG"
fi

# 4. base/.env
if [ ! -f "$BASE_DIR/.env" ]; then
    say "creating $BASE_DIR/.env from .env.example"
    cp "$BASE_DIR/.env.example" "$BASE_DIR/.env"
    say "  edit $BASE_DIR/.env to set DOTFILES_REPO and DEVBOX_HOST_CODE_DIR"
else
    say "$BASE_DIR/.env already exists"
fi

# 5. ~/code
if [ ! -d "$HOME/code" ]; then
    say "creating $HOME/code"
    mkdir -p "$HOME/code"
fi

# 6. PATH
ZSHRC="$HOME/.zshrc"
SCRIPTS_DIR="$REPO_ROOT/scripts"
if [ -f "$ZSHRC" ] && ! grep -q "$SCRIPTS_DIR" "$ZSHRC"; then
    say "adding $SCRIPTS_DIR to PATH in $ZSHRC"
    echo "" >> "$ZSHRC"
    echo "# devbox" >> "$ZSHRC"
    echo "export PATH=\"$SCRIPTS_DIR:\$PATH\"" >> "$ZSHRC"
fi

# 7. Git hooks (docs-sync — CLAUDE.md Hard rule #8)
if [ -d "$REPO_ROOT/.git" ]; then
    say "installing git hooks (docs-sync)"
    "$SCRIPTS_DIR/install-git-hooks.sh"
fi

say "done"
cat <<EOF

next steps:
  1. open $BASE_DIR/.env and set DOTFILES_REPO (or leave blank to use the sample)
  2. source your shell: exec zsh   (or open a new terminal)
  3. build the image:   devbox build
  4. start it:          devbox start
  5. log in:            devbox ssh    (first time: accept the host key)
  6. configure Cursor:  Cmd+Shift+P → Remote-SSH: Connect to Host → devbox

troubleshooting:
  - "permission denied (publickey)" — make sure DEVBOX_HOST_SSH_PUBKEY in
    base/.env points to $SSH_KEY.pub
  - "port 2222 already in use" — change the host port in base/docker-compose.yml
EOF
