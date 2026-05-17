#!/usr/bin/env bash
# devbox entrypoint — runs at every container start.
# Responsibilities:
#   1. Generate sshd host keys on first boot
#   2. Align the docker group GID with the mounted /var/run/docker.sock
#   3. Bootstrap dotfiles (clone DOTFILES_REPO or apply sample)
#   4. Hand off to the configured CMD (default: sshd -D)
set -euo pipefail

USERNAME="${DEV_USER:-dev}"
HOME_DIR="/home/${USERNAME}"

# ---------------------------------------------------------------------------
# 1. sshd host keys
# ---------------------------------------------------------------------------
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A
fi

# Pull in the host's public key from the staging mount.
# Compose mounts the pubkey :ro at /run/devbox/pubkey; we copy it so sshd
# sees the correct owner (dev) and mode (600) — StrictModes requires both.
if [ -f /run/devbox/pubkey ]; then
    mkdir -p "${HOME_DIR}/.ssh"
    cp /run/devbox/pubkey "${HOME_DIR}/.ssh/authorized_keys"
    chown "${USERNAME}:${USERNAME}" "${HOME_DIR}/.ssh/authorized_keys"
    chmod 600 "${HOME_DIR}/.ssh/authorized_keys"
fi

# ---------------------------------------------------------------------------
# 2. Align docker group GID with the mounted socket so `docker` works as $USERNAME
# ---------------------------------------------------------------------------
if [ -S /var/run/docker.sock ]; then
    sock_gid=$(stat -c '%g' /var/run/docker.sock)
    current_gid=$(getent group docker | cut -d: -f3 || echo "")
    if [ -n "$sock_gid" ] && [ "$sock_gid" != "$current_gid" ]; then
        if [ "$sock_gid" = "0" ]; then
            usermod -aG root "$USERNAME"
        else
            groupmod -g "$sock_gid" docker 2>/dev/null || {
                groupadd -g "$sock_gid" docker-host 2>/dev/null || true
                usermod -aG docker-host "$USERNAME"
            }
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 3. Dotfiles bootstrap (idempotent — runs on first boot, then no-ops)
# ---------------------------------------------------------------------------
if [ ! -f "${HOME_DIR}/.dotfiles-installed" ]; then
    sudo -u "$USERNAME" -H bash <<EOF
set -euo pipefail
cd "${HOME_DIR}"

if [ -n "\${DOTFILES_REPO:-}" ]; then
    echo "devbox: cloning dotfiles from \$DOTFILES_REPO"
    if [ ! -d "${HOME_DIR}/.dotfiles" ]; then
        git clone "\$DOTFILES_REPO" "${HOME_DIR}/.dotfiles"
    fi
    if [ -x "${HOME_DIR}/.dotfiles/install.sh" ]; then
        "${HOME_DIR}/.dotfiles/install.sh"
    else
        echo "devbox: no install.sh in dotfiles repo — symlinking known files"
        for f in .zshrc .tmux.conf .gitconfig; do
            [ -f "${HOME_DIR}/.dotfiles/\$f" ] && ln -sf "${HOME_DIR}/.dotfiles/\$f" "${HOME_DIR}/\$f"
        done
    fi
else
    echo "devbox: DOTFILES_REPO not set — using bundled sample"
    if [ -d "${HOME_DIR}/.dotfiles-sample" ]; then
        "${HOME_DIR}/.dotfiles-sample/install.sh"
    fi
fi

touch "${HOME_DIR}/.dotfiles-installed"
EOF
fi

# ---------------------------------------------------------------------------
# 4. Hand off
# ---------------------------------------------------------------------------
case "${1:-sshd-foreground}" in
    sshd-foreground)
        echo "devbox: starting sshd in foreground on :22"
        exec /usr/sbin/sshd -D -e
        ;;
    shell)
        exec sudo -u "$USERNAME" -H /usr/bin/zsh -l
        ;;
    *)
        exec sudo -u "$USERNAME" -H "$@"
        ;;
esac
