# ─── bogan-term hooks ─────────────────────────────────────────────────────────
# Sourced by your shell from ~/.zshrc.d/bogan-term.zsh
# Reads config from ~/.config/bogan-term/config.toml
# Honours expiry from ~/.config/bogan-term/expires_at (or /tmp/bogan-term.reboot)
# Edit the config with `bogan` (the TUI) — don't hand-edit unless you mean it.

# Guard: only run for interactive zsh
[[ -o interactive ]] || return 0
[[ -n "$ZSH_VERSION" ]] || return 0

# Re-entrancy guard (some setups source rc twice)
[[ -n "${_BOGAN_LOADED:-}" ]] && return 0
typeset -g _BOGAN_LOADED=1

# Paths
typeset -g BOGAN_HOME="${BOGAN_HOME:-$HOME/.config/bogan-term}"
typeset -g BOGAN_CONFIG="$BOGAN_HOME/config.toml"
typeset -g BOGAN_CATALOG="$BOGAN_HOME/art-catalog.toml"
typeset -g BOGAN_TICKERS="$BOGAN_HOME/tickers.txt"
typeset -g BOGAN_EXPIRES_FILE="$BOGAN_HOME/expires_at"
typeset -g BOGAN_REBOOT_MARKER="/tmp/bogan-term.reboot"
typeset -g BOGAN_DAILY_MARKER="$BOGAN_HOME/.last_motd"

# ─── expiry check ─────────────────────────────────────────────────────────────
# Returns 0 if bogan-term is currently active, non-zero if expired/off.

_bogan_active() {
  # Forever or once-mode in current shell: check mode
  local mode
  mode=$(_bogan_cfg duration.mode 2>/dev/null)
  [[ -z "$mode" ]] && return 1

  case "$mode" in
    forever) return 0 ;;
    once)
      # 'once' is delivered by the activation flow that source's bogan once
      # in the spawning shell, not by the persistent rc hook. So in new
      # shells we should NOT fire.
      return 1
      ;;
    until_reboot)
      [[ -f "$BOGAN_REBOOT_MARKER" ]] || return 1
      return 0
      ;;
    time_limited)
      [[ -f "$BOGAN_EXPIRES_FILE" ]] || return 1
      local now expires
      now=$(date +%s)
      expires=$(<"$BOGAN_EXPIRES_FILE")
      [[ "$now" -lt "$expires" ]] || return 1
      return 0
      ;;
  esac
  return 1
}

# ─── tiny TOML reader (good enough for our flat config) ───────────────────────
# Usage: _bogan_cfg section.key
# Returns the value (string). Strips quotes. No arrays, no nesting beyond
# one level of [section].
_bogan_cfg() {
  local q="$1" section="${1%.*}" key="${1##*.}"
  [[ -f "$BOGAN_CONFIG" ]] || return 1
  awk -v sect="$section" -v key="$key" '
    /^\[.*\]/        { in_sect = ($0 == "["sect"]") }
    in_sect && $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      sub(/^"/, "")
      sub(/"$/, "")
      print
      exit
    }
  ' "$BOGAN_CONFIG"
}

# Returns 'true' or empty.
_bogan_feature() {
  local v
  v=$(_bogan_cfg "features.$1")
  [[ "$v" == "true" ]]
}

# Reads themes.art_rotation as a list of slugs. Handles both single-line
#   art_rotation = ["a", "b"]
# and multi-line
#   art_rotation = [
#     "a",
#     "b",
#   ]
_bogan_rotation() {
  [[ -f "$BOGAN_CONFIG" ]] || return 1
  awk '
    /^\[themes\]/ { in_t = 1; next }
    /^\[/         { in_t = 0 }
    in_t && /art_rotation[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      buf = $0
      while (buf !~ /\]/) {
        if ((getline next_line) <= 0) break
        buf = buf " " next_line
      }
      sub(/.*\[/, "", buf)
      sub(/\].*/, "", buf)
      gsub(/[",]/, " ", buf)
      print buf
      exit
    }
  ' "$BOGAN_CONFIG"
}

# ─── art rendering ────────────────────────────────────────────────────────────

# Pull the `art = """..."""` block from art-catalog.toml for a given slug.
_bogan_art_for() {
  local slug="$1"
  [[ -f "$BOGAN_CATALOG" ]] || return 1
  awk -v slug="$slug" '
    /^\[\[piece\]\]/ { in_piece = 1; matched = 0; capture = 0; next }
    in_piece && $0 ~ "^slug = \""slug"\"$" { matched = 1 }
    matched && /^source = / {
      sub(/^source = /, "")
      gsub(/"/, "")
      src = $0
    }
    matched && /^art = """/ { capture = 1; sub(/^art = """/, ""); }
    capture {
      if ($0 ~ /"""$/) { sub(/"""$/, ""); print; capture = 0; matched = 0; exit }
      else { print }
    }
    /^\[\[piece\]\]/ && in_piece && !matched { in_piece = 1 }
  ' "$BOGAN_CATALOG"
}

# Render a slug — uses chafa on a photo if features.photo_via_chafa is on AND
# a photo exists for the slug, otherwise falls back to builtin art.
_bogan_render_slug() {
  local slug="$1"
  if _bogan_feature photo_via_chafa && command -v chafa >/dev/null 2>&1; then
    local photo_dir="$BOGAN_HOME/photos/$slug"
    if [[ -d "$photo_dir" ]]; then
      local photo
      photo=$(find "$photo_dir" -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \) 2>/dev/null | sort -R | head -n1)
      if [[ -n "$photo" ]]; then
        chafa --size=60x20 --symbols=block "$photo" 2>/dev/null && return 0
      fi
    fi
  fi
  _bogan_art_for "$slug"
}

# ─── MOTD ─────────────────────────────────────────────────────────────────────

_bogan_motd() {
  _bogan_feature motd || return 0

  # Daily-only mode: skip if we've already fired today.
  if _bogan_feature daily_motd; then
    local today=$(date +%Y-%m-%d)
    [[ -f "$BOGAN_DAILY_MARKER" && "$(<"$BOGAN_DAILY_MARKER")" == "$today" ]] && return 0
    print -r -- "$today" > "$BOGAN_DAILY_MARKER"
  fi

  local rotation slugs slug count idx
  rotation=$(_bogan_rotation)
  slugs=( ${(z)rotation} )
  count=${#slugs[@]}
  (( count == 0 )) && return 0
  idx=$(( (RANDOM % count) + 1 ))
  slug="${slugs[idx]}"

  # Banner header in yellow + bold
  print -P -- "%F{yellow}%B█▓▒░ G'DAY CUNT ░▒▓█%b%f"

  _bogan_render_slug "$slug"

  if _bogan_feature figlet_lolcat_time && command -v figlet >/dev/null 2>&1; then
    if command -v lolcat >/dev/null 2>&1; then
      figlet -f small "$(date +%H:%M)" | lolcat
    else
      print -P -- "%F{cyan}$(figlet -f small "$(date +%H:%M)")%f"
    fi
  fi

  # One ticker line under the banner if ticker feature is on
  if _bogan_feature ticker && [[ -f "$BOGAN_TICKERS" ]]; then
    local line
    line=$(grep -v '^\s*#' "$BOGAN_TICKERS" | grep -v '^\s*$' | sort -R | head -n1)
    [[ -n "$line" ]] && print -P -- "  %F{magenta}— $line%f"
  fi
  print
}

# ─── PS1 ──────────────────────────────────────────────────────────────────────

_bogan_apply_ps1() {
  _bogan_feature ps1 || return 0
  local static_word failure_word
  static_word=$(_bogan_cfg themes.ps1_static_word); : "${static_word:=oi}"
  failure_word=$(_bogan_cfg themes.ps1_failure_word); : "${failure_word:=wadiyatalkinabeet}"

  # %(?.A.B) — A on success, B on failure.
  # Yellow oi> on success, red wadiyatalkinabeet> on failure.
  # 🍺 is the VB-can stand-in.
  PROMPT='%F{8}%~%f %(?.%F{yellow}%B🍺 '"$static_word"'>%b%f.%F{red}%B🍺 '"$failure_word"'>%b%f) '

  if _bogan_feature rprompt; then
    RPROMPT='%(?.%F{8}🦘 0%f.%F{red}🦘 %?%f)'
  fi

  if _bogan_feature title_bar; then
    # zsh sets the terminal title via this escape on each precmd
    _bogan_set_title() { print -Pn -- $'\e]0;oi: %~\a'; }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _bogan_set_title
  fi
}

# Transient prompt: when you hit Enter, the previous prompt collapses
# to just '<static_word>>'. The active prompt is the full PROMPT.
_bogan_apply_transient_prompt() {
  _bogan_feature transient_prompt || return 0
  autoload -Uz add-zsh-hook
  local static_word
  static_word=$(_bogan_cfg themes.ps1_static_word); : "${static_word:=oi}"
  _bogan_collapse_prompt() {
    local prev=$PROMPT
    PROMPT="%F{8}$static_word>%f "
    zle reset-prompt
    PROMPT=$prev
  }
  zle -N _bogan_collapse_prompt
  bindkey '^M' _bogan_collapse_prompt 2>/dev/null
}

# ─── per-command hooks ────────────────────────────────────────────────────────

_bogan_apply_preexec() {
  _bogan_feature preexec_bogan || return 0
  autoload -Uz add-zsh-hook
  _bogan_preexec_hook() {
    # 15% chance per command
    (( RANDOM % 100 < 15 )) || return 0
    local line
    [[ -f "$BOGAN_TICKERS" ]] || return 0
    line=$(grep -v '^\s*#' "$BOGAN_TICKERS" | grep -v '^\s*$' | sort -R | head -n1)
    [[ -n "$line" ]] && print -P -- "%F{8}— $line%f"
  }
  add-zsh-hook preexec _bogan_preexec_hook
}

_bogan_apply_chpwd() {
  _bogan_feature chpwd_bogan || return 0
  autoload -Uz add-zsh-hook
  _bogan_chpwd_hook() {
    (( RANDOM % 100 < 25 )) || return 0
    local lines=(
      "oi where ya off to"
      "different patch of dirt eh"
      "fuckin' wandering again"
      "any goon in this directory"
      "settle down ya bloody nomad"
    )
    print -P -- "%F{yellow}${lines[RANDOM % ${#lines[@]} + 1]}%f"
  }
  add-zsh-hook chpwd _bogan_chpwd_hook
}

_bogan_apply_command_not_found() {
  _bogan_feature command_not_found_bogan || return 0
  command_not_found_handler() {
    local cmd="$1"
    print -P -- "%F{red}nah cunt '%B$cmd%b' ain't a real command%f"
    # zsh's correction suggestion if available
    if (( ${+functions[_approximate]} )); then
      print -P -- "%F{8}   try one of the suggestions or fuck off%f"
    fi
    return 127
  }
}

# ─── activate ─────────────────────────────────────────────────────────────────

_bogan_init() {
  _bogan_active || return 0
  _bogan_motd
  _bogan_apply_ps1
  _bogan_apply_transient_prompt
  _bogan_apply_preexec
  _bogan_apply_chpwd
  _bogan_apply_command_not_found
}

_bogan_init
