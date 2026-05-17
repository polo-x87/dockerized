# dockerize — Claude working notes

This repo defines a portable Linux dev container (`devbox-base`) and the supporting workflow for using it as (a) a long-lived dev box, (b) an AI-agent sandbox, (c) a per-project dev container. Target image size: **< 2 GB**.

## Layout

```
base/                 the devbox-base image (and optional Swift sidecar)
├── Dockerfile        5-stage multi-stage build (system → user → languages → cli-tools → final)
├── Dockerfile.swift  optional sidecar, FROM devbox-base:latest
├── docker-compose.yml
├── entrypoint.sh     sshd + dotfiles bootstrap, runs on every container start
├── .env.example      copy to .env (gitignored)
└── dotfiles-sample/  starter dotfiles used when DOTFILES_REPO is unset

overlays/example-project/
└── .devcontainer/    reference .devcontainer/ users copy into their own repos

scripts/
├── devbox            daily-driver CLI (ssh, exec, build, start, status, sandbox, update)
├── devbox-sandbox    ephemeral run for AI agents (no host mounts, --rm)
├── devbox-update     git pull + rebuild + restart
└── install-host.sh   one-time host (macOS) setup

docs/
├── guide.html        SELF-CONTAINED interactive guide. No build step.
└── usage.md          daily workflows + troubleshooting

mcp_workflow.md       separate Python research-system Dockerfile pattern (consumed by guide.html)
```

## How to verify a change

| Change touches | Verify with |
|---|---|
| `base/Dockerfile` | `cd base && DOCKER_BUILDKIT=1 docker compose build` — must succeed and image must stay under 2 GB (`docker image inspect devbox-base:latest --format '{{.Size}}'`) |
| `base/docker-compose.yml` | `docker compose config` validates YAML; then `devbox start && devbox ssh` |
| `base/entrypoint.sh` | rebuild + `docker compose up -d --force-recreate`; check `docker logs devbox` |
| `scripts/*` | `shellcheck scripts/*` and run the affected command end-to-end |
| `docs/guide.html` | open in a browser; visit each tab; ensure every output is **valid for direct copy-paste** |
| `overlays/example-project/.devcontainer/` | `cp -r` into a scratch repo, `Cursor → Dev Containers: Reopen` |

## Hard rules

1. **`guide.html` is the single source of truth for user-facing artifacts** (`.env`, compose, devcontainer, MCP config, setup.sh). When you change a file under `base/` or `scripts/`, also update the matching generator in `guide.html` so they don't drift.
2. **`base/.env` is gitignored.** Never commit it. `base/.env.example` is the committed template.
3. **Image must stay under 2 GB.** If a change adds a heavy dependency, move it to a per-project overlay or to `Dockerfile.swift`. Check `docker history devbox-base:latest`.
4. **Don't bake API keys into the image.** Use `${ANTHROPIC_API_KEY:-}` style passthrough in compose, or `op run --env-file=…` at agent invocation time.
5. **Stage ordering in `Dockerfile` matters.** Cheap-and-stable layers go first (apt), expensive-and-changing layers last (dotfiles, agents). Don't reorder without checking BuildKit cache impact.
6. **The dockerize repo itself is not used inside the container.** It's the host-side scaffolding. Don't add runtime dependencies of `devbox-base` on this repo's structure.
7. **`guide.html` outputs must be valid for direct paste.** No `// comments` in JSON outputs (Claude Code's `.mcp.json` is strict JSON); use the dedicated hint `<p>` for instructions.

## Default workflow when asked to "build the devbox"

```bash
scripts/install-host.sh       # idempotent host setup (SSH key, ~/.ssh/config, base/.env)
cd base && docker compose build
docker compose up -d
devbox ssh
```

## When things go wrong

`docs/usage.md` has a "Common problems" section that covers permissions, port conflicts, slow bind-mounts, missing agent config, oversize images, tmux session loss. Read it before guessing.
