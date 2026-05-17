# devbox starter .zshrc — fork this into your own dotfiles repo and iterate.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf-tab
)
source "$ZSH/oh-my-zsh.sh"

# PATH: cargo, mise shims, user-local bin
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.local/share/mise/shims:$PATH"

# mise activation (shims are already on PATH; this adds hooks for `cd` autoswitching)
command -v mise >/dev/null && eval "$(mise activate zsh)"

# direnv hook
command -v direnv >/dev/null && eval "$(direnv hook zsh)"

# fzf keybindings (Ctrl-T, Alt-C — Ctrl-R is hijacked by atuin below)
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && \
  source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && \
  source /usr/share/doc/fzf/examples/completion.zsh

# zoxide — rebind `cd` to frecency engine; falls through to builtin `cd` on miss
command -v zoxide >/dev/null && eval "$(zoxide init zsh --cmd cd)"

# atuin — sqlite-backed history search. Takes Ctrl-R; ↑ kept as last-command.
command -v atuin >/dev/null && eval "$(atuin init zsh --disable-up-arrow)"

# Aliases — modern CLI replacements
alias ls='eza --group-directories-first'
alias ll='eza -lh --group-directories-first --git'
alias la='eza -lha --group-directories-first --git'
alias tree='eza --tree'
alias cat='bat --paging=never'
alias less='bat'
alias grep='rg'
alias find='fd'
alias diff='delta'

# Git
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -n 20'

# Docker — short aliases. Pair with `lazydocker` (TUI), `ctop` (live top), `dive` (layer audit).
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
alias di='docker images'
alias dlog='docker logs -f --tail=200'
alias dex='docker exec -it'
alias dprune='docker system prune -af --volumes'
alias ld='lazydocker'
alias dt='ctop'
alias ddive='dive'
alias dlint='hadolint'

# Tmux helpers
alias t='tmux'
alias ta='tmux attach || tmux new'
alias tl='tmux ls'

# devbox housekeeping
alias devbox-update-dotfiles='cd ~/.dotfiles && git pull && ./install.sh && cd -'

# 1Password CLI — if op session, this is a no-op. Otherwise prompt.
op-signin() { eval "$(op signin)"; }

# atuin sync — one-time interactive helper. Skips if already configured.
# Run `atuin-sync-setup` after first shell launch if you want history sync.
atuin-sync-setup() {
    if [ -f "$HOME/.local/share/atuin/key" ] || atuin status >/dev/null 2>&1; then
        echo "atuin: already configured. Use 'atuin login' / 'atuin register' directly if needed."
        return 0
    fi
    echo "atuin sync setup — choose one:"
    echo "  1) register new account (creates a new key)"
    echo "  2) login to existing account (paste key)"
    echo "  3) skip (use atuin offline; history still recorded locally)"
    read "?> " choice
    case "$choice" in
        1) atuin register ;;
        2) atuin login ;;
        *) echo "skipped — atuin will work offline." ;;
    esac
}

# Editor
export EDITOR=vim
export VISUAL=vim

# AI agent helpers — wrap with `op run` when ~/.config/op/<agent>.env exists.
# Templates: ~/.dotfiles-sample/.config/op/*.env.example (copy and fill op:// refs).
_op_agent() {
    local agent="$1"
    shift
    local envfile="$HOME/.config/op/${agent}.env"
    if command -v op >/dev/null && [ -f "$envfile" ]; then
        op run --env-file="$envfile" -- "$@"
    else
        command "$@"
    fi
}
claude()  { _op_agent claude  claude  "$@"; }
codex()   { _op_agent codex   codex   "$@"; }
gemini()  { _op_agent gemini  gemini  "$@"; }
deepseek() {
    if command -v op >/dev/null && [ -f "$HOME/.config/op/deepseek.env" ]; then
        op run --env-file="$HOME/.config/op/deepseek.env" -- npx -y run-deepseek-cli "$@"
    else
        npx -y run-deepseek-cli "$@"
    fi
}

# Greeting — confirms which container you're in
[ -t 1 ] && echo "devbox: $(hostname) | $(uname -sm) | $(date +%H:%M)"
