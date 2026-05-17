# dockerize — portable Linux dev container

A slim Debian-based Docker image that mirrors a macOS dev environment, usable three ways:

1. **Long-lived portable dev box** — boot the Mac, container is up, you SSH in.
2. **Sandbox for AI agents** — Claude Code / Codex / Gemini run ephemerally with no host access.
3. **Per-project dev containers** — each repo's `.devcontainer/devcontainer.json` extends the base.

Target image size: **<2 GB**. Runtime: **OrbStack** on macOS (free for personal use, drop-in `docker` CLI). Falls back to Podman or Docker Desktop without code changes.

## Quick start

```bash
# 1. One-time host setup (SSH key, ~/.ssh/config entry, base/.env)
scripts/install-host.sh

# 2. Build the base image (multi-stage with BuildKit cache — first run ~5–10 min)
devbox build

# 3. Start the long-lived container
devbox start

# 4. Log in
devbox ssh
```

In Cursor: `Cmd+Shift+P → Remote-SSH: Connect to Host → devbox`. Your editor UI stays native on macOS; language servers, terminals, and AI agent tool calls all run inside the container.

## What's inside

| Category | Tools |
|---|---|
| Shell | zsh, oh-my-zsh, tmux (+ resurrect, continuum) |
| Modern CLI | fzf, ripgrep, bat, eza, fd, delta, jq, yq, direnv |
| VCS | git, gh |
| Languages | rust (stable), node (via mise), python + uv, go (via mise) |
| AI agents | claude-code, codex, gemini-cli |
| Secrets | 1Password CLI (`op`) |
| Container ops | docker CLI (talks to host's daemon over the mounted socket) |
| Remote access | sshd on `127.0.0.1:2222` |

## What's where

```
dockerize/
├── base/                 the devbox-base image
│   ├── Dockerfile        multi-stage build
│   ├── docker-compose.yml
│   ├── entrypoint.sh     sshd + dotfiles bootstrap
│   ├── .env.example      copy to .env and fill in
│   └── dotfiles-sample/  starter dotfiles (used when DOTFILES_REPO is unset)
├── overlays/
│   └── example-project/  reference .devcontainer/ for per-project use
├── scripts/
│   ├── devbox            daily-driver CLI (ssh, exec, status, build, etc.)
│   ├── devbox-sandbox    ephemeral run for AI agents
│   ├── devbox-update     pull + rebuild + restart
│   └── install-host.sh   one-time host setup
└── docs/
    ├── usage.md          daily workflows + troubleshooting
    └── superpowers/specs/2026-05-16-devbox-design.md
```

## How "synced on reboot" works

| Layer | Mechanism |
|---|---|
| OrbStack runtime | Open at Login (set in OrbStack preferences) |
| devbox container | `restart: unless-stopped` in compose |
| Shell history / agent state | Named volume `devbox-home` |
| Caches (npm, cargo, pip, go) | Named volume `devbox-cache` |
| Toolchain (mise-installed) | Named volume `devbox-tools` |
| App config (claude/codex/etc.) | Named volume `devbox-config` |
| Your code | Bind-mounted from `~/code` on the Mac (always lives on host) |
| Dotfiles | Cloned from `DOTFILES_REPO` on first boot; `git pull` to update |
| tmux sessions | tmux-resurrect + tmux-continuum (autosave every 15 min) |

Wipe everything and start over: `cd base && docker compose down -v && docker compose up -d` — image rebuilds, volumes get re-created, dotfiles repo re-clones, you're back where you were.

## See also

- `docs/usage.md` — daily workflows, AI agent setup, common problems
- `docs/superpowers/specs/2026-05-16-devbox-design.md` — full design spec
