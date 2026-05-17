# dockerize — Gemini CLI working notes

Read **`CLAUDE.md`** for hard rules, layout, and the verify matrix. This file is a Gemini-oriented summary only.

## Three modes

1. **Long-lived dev box** — `devbox start` then `devbox ssh` (survives Mac reboots).
2. **AI sandbox** — `devbox sandbox <cmd>` (ephemeral, no host mounts).
3. **Per-project dev container** — copy `overlays/example-project/.devcontainer/` into a repo.

## What's in the image

| Category | Tools |
|---|---|
| Shell | zsh, oh-my-zsh (robbyrussell), tmux (+ resurrect, continuum) |
| Modern CLI | fzf, ripgrep, bat, eza, fd, delta, jq, yq, direnv, zoxide, atuin |
| VCS | git, gh |
| Languages | rust, node (mise), python + uv, go (mise), Java 17, Android SDK |
| AI agents | claude-code, codex (OpenAI), gemini-cli |
| Secrets | 1Password CLI (`op`) — prefer `op run` over env files in git |
| Remote | sshd on host `127.0.0.1:2222` → Cursor Remote-SSH host `devbox` |

DeepSeek is **not** baked into the image. Use `DEEPSEEK_API_KEY` via `op run` (see `base/dotfiles-sample/.config/op/deepseek.env.example`) or `npx -y run-deepseek-cli` when needed.

## Paths

- Host repo: `~/vault/mcp/dockerize`
- Inside devbox: `/home/dev/vault/mcp/dockerize`
- Code bind-mount: `/home/dev/code` ← `~/code` on Mac

## Docs to @-mention in prompts

- `CLAUDE.md`, `README.md`, `docs/usage.md`
- `docs/cli-mesh.html` when discussing versions or image size
