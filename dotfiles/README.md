# dockerize/dotfiles

Personal host dotfiles, mirrored from this Mac (`~/.zshrc`, `~/.tmux.conf`, etc.) for use inside the devbox container. Drop-in replacement target for `base/dotfiles-sample/` when `DOTFILES_REPO` is unset.

## Use

Point the devbox at this directory instead of the sample:

```bash
# In base/.env
DOTFILES_LOCAL=/path/to/dockerize/dotfiles
```

Then rebuild — `entrypoint.sh` rsyncs this tree into `/home/dev/` on container start.

## What's here

| File | Source | Purpose |
|---|---|---|
| `.zshrc` | `~/.zshrc` | Interactive shell config (oh-my-zsh + plugins) |
| `.zprofile`, `.zshenv` | host equiv | Login + env-wide zsh shims |
| `.bashrc`, `.bash_profile` | written here | Minimal bash fallback for non-zsh callers |
| `.tmux.conf` | `~/.tmux.conf` | Tmux config (resurrect / continuum compatible) |
| `.gitconfig` | `~/.gitconfig` | git identity + aliases (review before sharing) |
| `.config/nvim/` | `~/.config/nvim/` | nvim + lazy.nvim setup |
| `.config/git/ignore` | `~/.config/git/ignore` | global gitignore |
| `.config/gh/config.yml` | `~/.config/gh/config.yml` | gh CLI settings (no auth — `hosts.yml` intentionally omitted) |
| `.config/bogan-term/` | `~/.config/bogan-term/` | bogan-term config |
| `.config/op/openrouter.env.example` | new | 1Password env template for ccr (`overlays/deepclaude`) |

## Not included (intentional)

- `~/.config/gh/hosts.yml` — contains GitHub auth tokens
- `~/.config/op/` state — 1Password CLI daemon state (host-specific)
- Anything under `~/.ssh`, `~/.aws`, `~/.config/anthropic` etc. — credentials
- Termux configs (`~/.termux`, `~/storage/shared/.termux`) — Termux is Android-only and not present on this Mac. If/when you sync Termux configs, drop them under `.termux/` here.

## Reviewing before commit

`.gitconfig` contains your email and signing key references. If you commit this dotfiles tree to a public repo, scrub or templatize those lines first.
