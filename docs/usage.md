# devbox — daily usage

> **Docs-sync rule** (CLAUDE.md Hard rule #8): any change to `base/`, `scripts/`, `overlays/`, or root configs must update the docs in the same change — `CLAUDE.md`, `README.md`, this file, `docs/guide.html`, and `docs/cli-mesh.html` as applicable. All agents read the docs as ground truth; stale docs cause divergent behavior.
>
> Enforced by `scripts/check-docs-sync.sh` via a pre-commit hook (installed by `scripts/install-host.sh` or `scripts/install-git-hooks.sh`). The same hook also runs `hadolint base/Dockerfile` when that file is staged, and `shellcheck` on any staged `scripts/*.sh` files. Both linters warn and skip gracefully if not on PATH (`brew install hadolint shellcheck`). Bypass the entire hook: `SKIP_DOCS_CHECK=1 git commit …` or `git commit --no-verify`.

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

## Auditing the image

```bash
devbox audit         # hadolint + size check + dive + shell-start benchmark
```

Run before committing changes to `base/Dockerfile`. Falls back gracefully on tools you haven't brewed yet:
- `brew install hadolint dive hyperfine` to enable the full suite on macOS.

## atuin (shell history) sync — optional

Inside the container, on first launch:

```bash
atuin-sync-setup     # interactive: register / login / skip
```

Sync is end-to-end encrypted and entirely optional — atuin works fully offline. The local sqlite database lives at `~/.local/share/atuin/history.db` and survives container restarts via the `devbox-home` named volume.

## lazydocker

```bash
ld                   # short alias for lazydocker
```

Config seed lives at `~/.config/jesseduffield/lazydocker/config.yml` (linked from `~/.dotfiles-sample/.config/jesseduffield/lazydocker/config.yml` by `install.sh`).

## Host-side tool version parity (mise)

`base/dotfiles-sample/.config/mise/config.toml` pins the same CLI tool versions
(zoxide, atuin, dive, ctop, and friends) that are baked into `base/Dockerfile`.
It is for **host-side management only** — inside the container the tools are
installed system-wide by the image build and are not managed by mise. To match
the container's versions on your Mac, install [mise](https://mise.jdx.dev/) and
run `mise install` from any directory where the config is active (or copy the
`[tools]` block into your `~/.config/mise/config.toml`).

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

If the key and config look right, check for a stale host-key entry: `rm -f ~/.ssh/known_hosts_devbox` then retry. This happens after a container recreate changes the sshd host key.

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

**`mise: command not found` or `node: command not found` in non-interactive SSH sessions**
When you run `devbox ssh -- <cmd>` (a non-interactive SSH command), PAM's `pam_env.so` module (configured in `/etc/pam.d/sshd`) runs at login and overwrites the `PATH` set by Docker's `ENV` instruction. This strips `.local/bin` and the mise shims directory, so tools like `mise`, `node`, and `go` are not found even though they are correctly installed in the image.

The fix: the Dockerfile's final stage writes the correct `PATH` to `/etc/environment`, which PAM reads and merges — making the full path available in all SSH session types, including non-interactive ones. This is already applied in the current image. If you see this on an older image, rebuild with `devbox update` or `docker compose build`.

**`mise: command not found` in `devbox-sandbox -- <cmd>`**
A different code path from SSH. Sandbox runs the command through `entrypoint.sh`, which `sudo`s to the dev user. Sudo's `secure_path` overrides PATH for command lookup, hiding mise shims even when `/etc/environment` is correct. The entrypoint wraps the command in `env PATH="$PATH" <cmd>` so PATH lookup uses the image PATH, not sudo's secure_path. Already applied — rebuild if you see this on an old image.

**`devbox-sandbox` fails with "the input device is not a TTY"**
Old versions of the script passed `-it` to `docker run` unconditionally, which requires a real terminal. Non-interactive callers (CI, scripts, agents) have no TTY. The script now uses `-i` always and adds `-t` only when stdin is a TTY (`[ -t 0 ]`). Pull/update if you hit this.

**Image is bigger than 2GB**
Run `docker history devbox-base:latest` to see which layer is heavy. Common culprits: too many cargo binaries baked in (move some to a per-project overlay), keeping `apt-get update` cache (already handled), npm cache not pruned (handled by the cache mount).

**`setup.sh` re-prompts for the same value every run**
The script saves your answers to `<repo-root>/.devbox.env` after the first interactive run. If that file is missing or read-only, every run starts from the embedded defaults again. Check `ls -l .devbox.env` and re-run once to regenerate.

**`setup.sh` shows the validation menu for a path you know exists**
Validators expand `~` to `$HOME` before checking. If you set `DEVBOX_VAULT_DIR=~vault` (missing slash) or pasted a Windows-style path, the expansion still won't match. The menu's `m` option lets you type the value directly; the `a` option (only on path-like vars) accepts the invalid value anyway — useful when a later step will create the directory.

## `setup.sh` — config flow

`setup.sh` (downloaded from the **guide.html** Configure tab) handles one-time devbox bootstrap. Beyond running the install steps, it manages a small config layer with this precedence:

```
CLI flags     >   .devbox.env     >   ENV vars     >   embedded defaults
(--code-dir=…)    (saved answers)     (DEVBOX_* in     (the values you
                                       your shell)      filled in guide.html)
```

**Embedded defaults** sit at the top of the script as `: "${VAR:=default}"` — they only apply when nothing higher has set the variable. ENV vars therefore win over the defaults.

**`.devbox.env`** is auto-written at `$REPO_ROOT/.devbox.env` at the end of the first interactive run. It stores each `DEVBOX_*` answer using `printf %q` for safe round-tripping (handles spaces, tildes, quotes). Sourcing it on the next run replays your choices without re-prompting. Safe to edit by hand.

**Validation + fallback menu.** Each variable has a validator. When a value fails validation, the script auto-detects candidates (e.g. `~/code`, `~/src` for `DEVBOX_CODE_DIR`; all `~/.ssh/*.pub` for `DEVBOX_SSH_PUBKEY`) and shows a numbered menu. The choices: pick a number, `m` to type your own value, `h` to print copy-paste shell commands you can run in another terminal then paste the result back, or `a` (only for path-like vars — soft validation) to accept the invalid value anyway and let a later step create it.

Hard-validated vars (`DEVBOX_DOTFILES_REPO`, `DEVBOX_DEV_USER`) refuse to proceed with an invalid value. Soft-validated vars (`DEVBOX_CODE_DIR`, `DEVBOX_VAULT_DIR`, `DEVBOX_SSH_PUBKEY`) warn and let you continue — useful when `install-host.sh` will create the SSH key the script is checking for.

**Non-interactive mode** (no TTY, e.g. piped or CI): soft validators warn and accept; hard validators exit 1 immediately.

**Mode menu.** Running `./setup.sh` with no arguments in a terminal opens a mode picker after `ensure_config` finishes:

```
1) Dry-run all steps (preview only)
2) Run all steps live
3) Step-by-step (confirm each step)
4) Run a single step
5) Just save .devbox.env and exit
q) Quit
```

Mode 3 (step-by-step) prompts before each step with `y` (run), `n` (skip), `d` (dry-run this one), `a` (run all remaining without prompting), or `q` (quit). Mode 4 lists every `step_*` function and asks for a number, then run-vs-dry. Pass `--menu` to force the picker even when other flags are supplied; pass any positional `step_name` to bypass it entirely (existing CLI behavior is unchanged).

Regenerating `setup.sh` from `guide.html` is safe: `.devbox.env` lives separately and is re-sourced by the new copy.
