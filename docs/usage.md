# devbox — daily usage

## Three modes of running

### Mode 1: Long-lived dev box (default)

Start it once, leave it running. Survives Mac reboots.

```bash
devbox start         # docker compose up -d
devbox ssh           # log in as `dev`
devbox shell         # alternative: docker exec, no SSH
devbox status        # is it running? what's the image size?
devbox stop          # docker compose stop
devbox restart       # picks up dotfiles changes
```

Inside the container:

```bash
tmux attach          # resume yesterday's session (continuum auto-restores)
cd ~/code/some-repo
claude               # AI agent in your project context
```

### Mode 2: AI agent sandbox

Ephemeral container, no host mounts, destroyed on exit.

```bash
devbox sandbox claude                       # default network access
devbox sandbox --offline bash               # no network at all
devbox sandbox bash -c 'curl ... | bash'    # risky one-liner, contained
```

Use when you want to let an agent loose without giving it access to your real filesystem.

### Mode 3: Per-project dev container

Copy `overlays/example-project/.devcontainer/` into a project repo, customize the Dockerfile if it needs extra packages, then in Cursor: `Cmd+Shift+P → Dev Containers: Reopen in Container`.

The `.devcontainer/devcontainer.json` declares VS Code extensions that install inside the container, mounts the project as the workspace, and runs `postCreateCommand` to install language-specific deps.

## AI agent secrets

Avoid baking API keys into the image. Two good options:

### Option A: env vars at runtime (simple)

In `base/.env`:
```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...
```
Compose injects them into the container. Downside: keys live in plaintext on disk.

### Option B: 1Password CLI at runtime (recommended)

1. Sign into `op` from the host once (biometric).
2. Forward `op` via SSH agent or use a service account token mounted at runtime.
3. Wrap each agent invocation with `op run`:
   ```bash
   op run --env-file=~/.config/op/claude.env -- claude
   ```
   …where `~/.config/op/claude.env` contains:
   ```
   ANTHROPIC_API_KEY=op://Personal/Anthropic/api_key
   ```

The aliases in the sample `.zshrc` are commented out — uncomment after configuring `op`.

## Cursor integration — both flavors

### Dev Containers (per-project)

In a project with `.devcontainer/devcontainer.json`: `Cmd+Shift+P → Dev Containers: Reopen in Container`. Cursor builds/starts the container, installs declared extensions inside it, and connects through `docker exec`. No SSH needed.

### SSH remote (long-lived devbox)

`scripts/install-host.sh` already wrote a `~/.ssh/config` entry for you. In Cursor: `Cmd+Shift+P → Remote-SSH: Connect to Host → devbox`. The whole window now runs against the container; extensions installed inside it.

Both can coexist — use Dev Containers for project work where reproducibility matters, SSH for general "my Linux box" exploration.

## Updating

```bash
devbox update        # git pull + rebuild + restart
```

When the Dockerfile changes, BuildKit reuses cached layers and only rebuilds from the changed stage forward — usually <30 s for a tweak to the dotfiles stage.

## Wiping clean

```bash
cd base
docker compose down -v       # also deletes the named volumes
docker compose up -d
```

The image will rebuild, volumes are fresh, `entrypoint.sh` re-clones `DOTFILES_REPO`, you're at zero.

## Common problems

**"permission denied (publickey)" when running `devbox ssh`**
The public key in `base/.env` (`DEVBOX_HOST_SSH_PUBKEY`) needs to match the private key in `~/.ssh/config`. Defaults: `~/.ssh/devbox_ed25519.pub` ↔ `~/.ssh/devbox_ed25519`. `scripts/install-host.sh` sets both consistently.

**"port 2222 already in use"**
Edit `base/docker-compose.yml`, change `127.0.0.1:2222:22` to another port, also update `~/.ssh/config`.

**"docker: not found" inside the container**
The CLI is installed but it needs the socket bind-mount (`/var/run/docker.sock`). Compose does this; if you ran a one-off `docker run` that omitted it, that's why.

**Container can run `docker` but gets permission errors on the socket**
`entrypoint.sh` re-aligns the docker group's GID to match the mounted socket. If you bypassed the entrypoint (e.g., `docker run … bash`), `sudo` is your friend or use `--entrypoint` to invoke the real one.

**Slow filesystem on bind-mounted `~/code`**
You're probably on Docker Desktop's default config. Switch to OrbStack — it uses VirtioFS and is dramatically faster. Or in Docker Desktop, enable the new virtualization framework.

**tmux sessions don't restore after reboot**
First time only: run `tmux` once, hit `Ctrl-a + I` (capital i) to install plugins via tpm. After that, `tmux-continuum` autosaves every 15 minutes and restores on next launch.

**Claude/Codex/Gemini complains about missing config**
First-run they want auth. Run each one once interactively (`devbox ssh`, then `claude` etc.) to log in; the config lands in `~/.config/...` which is on the `devbox-config` named volume and persists.

**Image is bigger than 2GB**
Run `docker history devbox-base:latest` to see which layer is heavy. Common culprits: too many cargo binaries baked in (move some to a per-project overlay), keeping `apt-get update` cache (already handled), npm cache not pruned (handled by the cache mount).
