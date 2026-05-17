# Devbox — Portable Linux Dev Container

**Date:** 2026-05-16
**Status:** Design approved, pending spec review
**Owner:** matthew.leman3@gmail.com

## Goal

Replace the placeholder `mcp_workflow.md` with a real, layered Docker project that delivers a slim Linux dev environment mirroring the user's macOS toolchain. The same base image must serve three use cases:

1. **Long-lived portable dev box** — boot the Mac, the container is up, Cursor/terminal connect over SSH, work continues.
2. **Sandbox for AI coding agents** — Claude Code, Codex, Gemini CLI run inside an isolated, ephemeral container with no access to the host filesystem.
3. **Per-project reproducible builds** — each repo's `.devcontainer/devcontainer.json` references the base image and adds project-specific deps.

Non-goals: running macOS in a container (impossible — kernel/licensing), GUI apps inside the container, GPU passthrough for ML, security boundary against kernel exploits (containers aren't VMs).

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Container runtime | **OrbStack** | Free for personal/non-commercial; 2–3× faster filesystem than Docker Desktop on Mac; uses VirtioFS for bind-mount perf. Drop-in `docker` CLI compatibility. Podman is the FOSS fallback if licensing ever matters. |
| Base OS image | **`debian:bookworm-slim`** | Alpine's musl breaks node-gyp and several Rust crates; full Ubuntu is wasteful. Bookworm-slim is ~80MB and apt-compatible with everything we need. |
| Image architecture | **Base + per-project overlays** | Single base (~1.8GB) shared across all three use cases; project overlays stay small (+100–300MB) by only adding what's unique. Multi-stage Dockerfile inside the base for aggressive layer caching. |
| Persistence | **Hybrid** | Bind-mount `~/code` (fast project I/O) + named Docker volumes (caches, toolchain, home state) + dotfiles git repo (portable config). |
| Editor integration | **Dev Containers + SSH remote, both** | Dev Containers for per-project work; SSH remote for the long-lived "my Linux box" feel. Same image, different access pattern. |
| Reboot survival | OrbStack-on-login + `restart: unless-stopped` + named volumes + tmux-resurrect | State survives container restart; container survives Mac reboot; tmux state survives SSH disconnect and (with resurrect) Mac reboot. |

## Tool inventory

### System packages (apt)

`git`, `gh` (GitHub CLI), `tmux`, `fzf`, `ripgrep`, `bat`, `eza`, `fd-find`, `git-delta`, `jq`, `yq`, `direnv`, `openssh-server`, `sudo`, `curl`, `ca-certificates`, `build-essential`, `pkg-config`, `libssl-dev`, `zsh`, `unzip`, `less`, `man-db`.

### Language toolchains

- **Node.js** — installed via `mise`, current LTS pinned in `mise.toml`.
- **Rust** — installed via `rustup`, stable channel, with `cargo`, `clippy`, `rustfmt`.
- **Python** — system `python3` + **`uv`** (modern installer/resolver, replaces pip/pipx/poetry/venv for most flows).
- **Go** — installed via `mise`, current stable.

### CLI tools

- **AI agents** — `@anthropic-ai/claude-code`, `@openai/codex` (Codex CLI), `@google/gemini-cli` — all installed globally via `npm`.
- **Secrets** — `1Password CLI` (`op`) for runtime secret injection; never bake API keys into the image.
- **Container tools** — `docker` CLI only (no daemon); host's `/var/run/docker.sock` is bind-mounted so the container can drive the Mac's container runtime.
- **Shell** — `zsh` + `oh-my-zsh` + a curated plugin set (`zsh-autosuggestions`, `zsh-syntax-highlighting`, `fzf-tab`).

## Image structure

The base image is built as a multi-stage Dockerfile so each layer caches independently. Order is "rarely changes" → "frequently changes" so a `.zshrc` edit doesn't invalidate the apt layer.

```
debian:bookworm-slim
   │
   ├── stage 1: system  (apt install — rarely changes, BuildKit cache mount on /var/cache/apt)
   │
   ├── stage 2: languages  (rustup + mise + uv — changes on toolchain bumps)
   │
   ├── stage 3: cli-tools  (npm -g for AI agents, cargo install for native tools)
   │
   ├── stage 4: user  (create dev user, set up sudo, zsh as default shell, sshd config)
   │
   └── stage 5: dotfiles  (clone dotfiles repo, run install script, oh-my-zsh)
              │
              └── final image: devbox-base:latest  (target <2GB)
```

Per-project overlays:

```dockerfile
FROM devbox-base:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-client redis-tools
COPY .devcontainer/extra-setup.sh /tmp/
RUN /tmp/extra-setup.sh
```

## Persistence strategy (hybrid)

### Host bind mounts (read-write)

| Host path | Container path | Purpose |
|---|---|---|
| `~/code` | `/home/dev/code` | The project tree. Edits in Cursor on the Mac are instant in the container. |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker-from-Docker so the container can run `docker` commands against the host's OrbStack daemon. |
| `~/.ssh/devbox_ed25519.pub` | `/home/dev/.ssh/authorized_keys` (ro) | SSH login from Mac into container. |

### Named Docker volumes (persist across container delete/rebuild)

| Volume | Container path | Contents |
|---|---|---|
| `devbox-home` | `/home/dev` | Default fallback for anything not otherwise mounted — shell history, agent state, scratch. |
| `devbox-cache` | `/home/dev/.cache` | npm, cargo, pip/uv, go module caches. Huge; keeping it on a named volume means rebuilds don't re-download. |
| `devbox-tools` | `/home/dev/.local` | `mise`-installed Node/Go versions, `cargo install`-ed binaries. |
| `devbox-config` | `/home/dev/.config` | App configs that aren't in the dotfiles repo (e.g., claude code's auth, codex token cache). |

### Dotfiles repo

A separate git repo (`~/dotfiles` on host or directly cloned in container) holds:
- `.zshrc`, `.tmux.conf`, `.gitconfig`, `.editorconfig`
- `.config/mise/config.toml`, `.config/direnv/direnvrc`
- agent config templates (`claude.json`, `codex.toml`, `gemini` settings)

Applied on first container start by `entrypoint.sh`:
```
if [ ! -d ~/.dotfiles ]; then
    git clone $DOTFILES_REPO ~/.dotfiles
    ~/.dotfiles/install.sh
fi
```

This is what makes the container **portable to a new machine**: clone the project repo + dotfiles repo, `docker compose up`, your env is back.

## The three use cases — concrete usage

### 1. Long-lived portable dev (always-on)

```yaml
# base/docker-compose.yml
services:
  devbox:
    build: .
    image: devbox-base:latest
    container_name: devbox
    hostname: devbox
    restart: unless-stopped
    ports:
      - "127.0.0.1:2222:22"   # SSH, localhost only
    volumes:
      - ~/code:/home/dev/code
      - /var/run/docker.sock:/var/run/docker.sock
      - devbox-home:/home/dev
      - devbox-cache:/home/dev/.cache
      - devbox-tools:/home/dev/.local
      - devbox-config:/home/dev/.config
    environment:
      - DOTFILES_REPO=${DOTFILES_REPO}
    init: true

volumes:
  devbox-home:
  devbox-cache:
  devbox-tools:
  devbox-config:
```

Daily flow:
```
Mac boots → OrbStack starts (login item) → devbox container restarts → sshd up on :2222
ssh devbox          # plain shell access
tmux attach          # resume yesterday's sessions
cursor --remote ssh-remote+devbox ~/code/some-project
```

### 2. Sandbox for AI agents (ephemeral)

```bash
# scripts/devbox-sandbox
docker run --rm -it \
    --name "sandbox-$(date +%s)" \
    --network none \                     # optional: no network at all; or use a custom bridge with egress rules
    devbox-base:latest \
    "$@"

# Usage
devbox-sandbox claude              # interactive claude in a fresh container
devbox-sandbox bash -c 'curl ... | bash'   # risky one-liner, no host access
```

No host mounts → agents can't touch your real files. Container is destroyed on exit.

### 3. Per-project reproducible (Dev Containers)

Each project repo commits a `.devcontainer/devcontainer.json`:

```json
{
  "name": "my-project",
  "build": {
    "dockerfile": "Dockerfile"
  },
  "mounts": [
    "source=devbox-cache,target=/home/dev/.cache,type=volume"
  ],
  "remoteUser": "dev",
  "customizations": {
    "vscode": {
      "extensions": ["rust-lang.rust-analyzer", "ms-python.python"]
    }
  }
}
```

…and a `.devcontainer/Dockerfile`:

```dockerfile
FROM devbox-base:latest
RUN apt-get install -y --no-install-recommends postgresql-client
```

Cursor's "Reopen in Container" reads this and gets the user an env that's identical to teammates'.

## Cursor / editor integration

**Dev Containers approach** — Cursor's Remote-Containers extension (a fork of Microsoft's) reads `.devcontainer/devcontainer.json`, builds/starts the container, installs declared extensions *inside* it, and tunnels the editor backend through `docker exec`. No SSH needed.

**SSH remote approach** — `~/.ssh/config` on the Mac:
```
Host devbox
    HostName 127.0.0.1
    Port 2222
    User dev
    IdentityFile ~/.ssh/devbox_ed25519
    ForwardAgent yes
```
Then in Cursor: `Cmd+Shift+P → Remote-SSH: Connect to Host → devbox`. Or from terminal: `ssh devbox`, `scp file devbox:~/code/`, etc.

Both share the same image. Use Dev Containers for project work where you want declarative reproducibility; use SSH for the long-lived "my Linux box" use case.

## Build optimization — keeping the image slim

1. **Multi-stage build** — install build tools (`gcc`, `python3-dev`, `pkg-config`) in an early stage, copy only the resulting binaries forward. Final stage has no compilers if nothing in it needs to compile at runtime.
2. **BuildKit cache mounts** — `RUN --mount=type=cache,target=/var/cache/apt`, same for `~/.cargo`, `~/.npm`. Caches survive between builds without bloating the image.
3. **Aggressive `.dockerignore`** — `.git`, `node_modules`, `target`, `__pycache__`, `.venv`, `*.log`, `.DS_Store`.
4. **`--no-install-recommends`** on every apt call, plus `apt-get clean && rm -rf /var/lib/apt/lists/*` in the same layer.
5. **Pin tool versions via ARG** — `ARG NODE_VERSION=22`, so bumps are explicit and reproducible.
6. **One RUN per concern, not per command** — fewer layers, smaller image.
7. **Use `mise` instead of installing one Node/Go/etc. per language manager** — single binary, all versions.

Target final base image size: **<2GB**, ideally ~1.8GB.

## Reboot survival

| Layer | How it survives |
|---|---|
| OrbStack itself | macOS "Open at Login" (set in OrbStack preferences). |
| `devbox` container | `restart: unless-stopped` in compose. |
| Filesystem state | Named volumes (`devbox-home`, `devbox-cache`, `devbox-tools`, `devbox-config`) — persist independent of container lifecycle. |
| Bind-mounted code | Always lives on the Mac side, container restart is irrelevant. |
| SSH access | sshd started by container `entrypoint.sh`; `~/.ssh/authorized_keys` mounted from host. |
| Dotfiles | Cloned on first run from `DOTFILES_REPO`; updates flow via `cd ~/.dotfiles && git pull && ./install.sh`. |
| Tmux sessions | Tmux state isn't preserved across a container restart by default — install `tmux-resurrect` + `tmux-continuum` (autosaves every 15 min, restores on tmux launch). State file lives in `~/.local/share/tmux/resurrect` which is on the `devbox-tools` volume. |
| Secrets | `op` connects to 1Password biometric on host via the SSH agent forwarding or a service account token mounted at runtime — never baked into the image. |

## Project layout

```
dockerize/
├── README.md                       # Quick start
├── docs/
│   ├── superpowers/specs/2026-05-16-devbox-design.md   (this file)
│   └── usage.md                    # daily workflows
├── base/
│   ├── Dockerfile                  # multi-stage, the heart of it
│   ├── .dockerignore
│   ├── docker-compose.yml          # long-lived devbox service
│   ├── entrypoint.sh               # sshd start, dotfiles clone, sanity
│   └── dotfiles-sample/            # template if user doesn't have a repo yet
├── overlays/
│   └── example-project/
│       ├── .devcontainer/
│       │   ├── devcontainer.json
│       │   └── Dockerfile
│       └── README.md
├── scripts/
│   ├── devbox                      # wrapper: ssh / exec / status / logs
│   ├── devbox-sandbox              # one-shot ephemeral run
│   ├── devbox-update               # pull, rebuild, restart
│   └── install-host.sh             # one-time host setup (OrbStack, ssh key, alias)
└── mcp_workflow.md                 # old placeholder — keep or delete during implementation
```

## Daily usage flow

```
Morning:
  Mac wake → OrbStack auto-start → devbox container auto-start
  open Cursor → Reopen in Container OR Remote-SSH connect to devbox
  ssh devbox && tmux attach        # if pure terminal

During work:
  edit code in Cursor (files on Mac, lang servers in container)
  claude / codex / gemini run inside container, can read project but not /Users/
  for risky tasks: devbox-sandbox claude   (fresh container, no mounts)

Evening:
  detach tmux (state autosaved by tmux-continuum)
  close Cursor (container keeps running)

New machine:
  install OrbStack
  clone this dockerize repo
  scripts/install-host.sh           # generates SSH key, adds ~/.ssh/config entry, sets DOTFILES_REPO
  docker compose -f base/docker-compose.yml up -d
  ssh devbox                        # back to work in ~5 minutes
```

## Open questions for the implementation plan

These are not blocking the spec; they get resolved during writing-plans:

1. **Dotfiles repo bootstrap** — does the user already have a `~/dotfiles` repo? If not, generate a minimal starter as part of `scripts/install-host.sh`.
2. **1Password auth model inside container** — biometric-via-host (SSH agent forwarding + `op-ssh-sign`) vs service-account token. Biometric is more user-friendly; service-account is needed for headless cases.
3. **Codex/Gemini auth caching** — where do their tokens land, and is that path on a named volume? (Belongs in `devbox-config`.)
4. **GPU/ML workloads** — out of scope for v1; the user uses the Mac directly for these.
5. **Multi-arch builds** — the user's Mac is presumably Apple Silicon (arm64). Build native; cross-build amd64 only if needed for cloud deployment.
6. **Network restrictions for sandbox** — `--network none` (no egress at all) vs default bridge vs a custom bridge with iptables egress rules to allow only `api.anthropic.com`, `api.openai.com`, etc. Pick during implementation based on what agents actually need.

## What gets built

In dependency order:

1. `base/Dockerfile` — multi-stage, all tools, sshd, dev user, oh-my-zsh.
2. `base/entrypoint.sh` — sshd start, dotfiles bootstrap, agent setup.
3. `base/docker-compose.yml` — long-lived devbox service with all mounts.
4. `scripts/install-host.sh` — one-time host setup (SSH key gen, `~/.ssh/config`, OrbStack check, `.env` for `DOTFILES_REPO`).
5. `scripts/devbox` — wrapper CLI (`devbox ssh`, `devbox exec ...`, `devbox status`, `devbox logs`, `devbox rebuild`).
6. `scripts/devbox-sandbox` — ephemeral run wrapper.
7. `scripts/devbox-update` — `git pull && docker compose build && docker compose up -d`.
8. `overlays/example-project/` — reference template a user can copy into a real project.
9. `README.md` + `docs/usage.md` — quick start and daily-workflow docs.
10. Delete or supersede the old `mcp_workflow.md`.
