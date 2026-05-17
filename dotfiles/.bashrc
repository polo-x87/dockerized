# Container-side .bashrc — minimal. The primary shell inside devbox is zsh
# (see .zshrc). This file exists so login bash sessions don't break and so
# tools that probe ~/.bashrc (e.g. some VS Code terminal probes) find one.

# Pull in /etc/bash.bashrc if present (Debian default location).
[ -r /etc/bash.bashrc ] && . /etc/bash.bashrc

# Common PATH additions mirroring .zprofile.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Prompt: leave bash default — devbox auto-launches zsh for interactive shells.
