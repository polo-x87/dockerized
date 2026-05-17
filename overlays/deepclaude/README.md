# overlays/deepclaude

Per-project overlay that extends `devbox-base` with [claude-code-router](https://github.com/musistudio/claude-code-router) (`ccr`), routing Claude Code requests through a free OpenRouter backend (default: `deepseek/deepseek-v4-flash:free`).

## What it adds

- `npm i -g @musistudio/claude-code-router` in the image
- A baked-in `ccr` config at `/home/dev/.claude-code-router/config.json` with a curated list of free OpenRouter models
- OpenRouter API key pulled from 1Password at container start via `op run` (per repo Hard Rule #4 — no keys in the image)

## Usage from the host

```bash
# Open the project in Cursor → Dev Containers: Reopen in Container
# Or, from the dockerize repo root:
cp -r overlays/deepclaude /path/to/your/project/.devcontainer
```

Inside the container, launch with:

```bash
op run --env-file=~/.config/op/openrouter.env -- ccr code
```

Or `/model openrouter,<id>` mid-session to swap among:
- `deepseek/deepseek-v4-flash:free` (default)
- `z-ai/glm-4.5-air:free`
- `meta-llama/llama-3.3-70b-instruct:free`
- `openai/gpt-oss-20b:free`

## Notes

- Mirrors the host-side setup at `~/vault/deepclaude/`. Both can coexist; this overlay is the in-container path.
- Free tier is rate-limited (~20 req/min per model).
- See `base/dotfiles-sample/.config/op/openrouter.env.example` for the env-file template.
