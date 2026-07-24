#!/usr/bin/env bash
# Bootstrap persistent HOME on the Railway volume (/app), then exec the app.
# All tool homes/PATH bind to the volume automatically — no manual export needed.
set -euo pipefail

HOME_DIR="${HOME:-/app}"
SEED_DIR="${DEXSHELL_SEED:-/opt/dexshell/home-seed}"

mkdir -p \
  "$HOME_DIR"/{bin,.local/bin,.config,.cache,.local/share,.local/state,.dexshell,projects} \
  "$HOME_DIR"/{.npm-global,.bun,.hermes,.cargo/bin,go/bin,.hermes/bin,.hermes/logs} \
  "$HOME_DIR"/{.cache/npm,.cache/uv,.cache/go-build,.local/share/uv/python} \
  "$HOME_DIR"/{.config/claude,.codex,.config/opencode,.kilo,.local/share/pnpm}

# Seed missing dotfiles only (never overwrite user changes on the volume).
if [[ -d "$SEED_DIR" ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$SEED_DIR"/}"
    dst="$HOME_DIR/$rel"
    if [[ ! -e "$dst" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -a "$src" "$dst"
    fi
  done < <(find "$SEED_DIR" -type f -print0 2>/dev/null || true)
fi

# shellcheck disable=SC1091
if [[ -f /etc/profile.d/10-volume-env.sh ]]; then
  # shellcheck source=/dev/null
  source /etc/profile.d/10-volume-env.sh
elif [[ -f /etc/profile.d/dexshell-volume.sh ]]; then
  # shellcheck source=/dev/null
  source /etc/profile.d/dexshell-volume.sh
fi

export HOME="$HOME_DIR"
export USER="${USER:-root}"

# Re-assert volume bindings (covers non-login shells / SSH sessions).
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME_DIR/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
export HERMES_HOME="${HERMES_HOME:-$HOME_DIR/.hermes}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME_DIR/.bun}"
export npm_config_prefix="${npm_config_prefix:-$HOME_DIR/.npm-global}"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$npm_config_prefix}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-$HOME_DIR/.cache/npm}"
export CARGO_HOME="${CARGO_HOME:-$HOME_DIR/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME_DIR/.rustup}"
export GOPATH="${GOPATH:-$HOME_DIR/go}"
export GOBIN="${GOBIN:-$HOME_DIR/go/bin}"
export GOCACHE="${GOCACHE:-$HOME_DIR/.cache/go-build}"
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME_DIR/.local}"
export PIP_USER="${PIP_USER:-1}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME_DIR/.cache/uv}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME_DIR/.local/share/uv/python}"
export PNPM_HOME="${PNPM_HOME:-$HOME_DIR/.local/share/pnpm}"
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.config/claude}"
export CODEX_HOME="${CODEX_HOME:-$HOME_DIR/.codex}"
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME_DIR/.config/opencode}"
export KILO_HOME="${KILO_HOME:-$HOME_DIR/.kilo}"

# Installer/build scratch always goes to container tmp, not the persistent volume.
export TMPDIR="${TMPDIR:-/tmp}"
export TMP="${TMP:-/tmp}"
export TEMP="${TEMP:-/tmp}"

export PATH="$HOME_DIR/bin:$HOME_DIR/.local/bin:$HOME_DIR/.bun/bin:$HOME_DIR/.npm-global/bin:$HOME_DIR/.cargo/bin:$HOME_DIR/go/bin:$HOME_DIR/.hermes/bin:$HOME_DIR/.hermes/hermes-agent/.venv/bin:$PNPM_HOME:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

# Soft-link common volume tools into $HOME/bin when present.
link_if() {
  local src="$1" name="${2:-}"
  [[ -e "$src" || -L "$src" ]] || return 0
  [[ -n "$name" ]] || name="$(basename "$src")"
  ln -sfn "$src" "$HOME_DIR/bin/$name" 2>/dev/null || true
}
link_if "$HOME_DIR/.bun/bin/bun" bun
link_if "$HOME_DIR/.bun/bin/bunx" bunx
link_if "$HOME_DIR/.hermes/hermes-agent/.venv/bin/hermes" hermes.bin
link_if "$HOME_DIR/.hermes/bin/hermes" hermes.bin

# Quiet capacity check (never block boot). Full report: volume-ready
if command -v df >/dev/null 2>&1; then
  vol_free="$(df -PB1 "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  tmp_free="$(df -PB1 /tmp 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -n "${vol_free:-}" && "$vol_free" -lt $((30 * 1024 * 1024)) ]]; then
    echo "[dexshell] WARN: volume $HOME_DIR almost full (run: volume-ready)" >&2
  fi
  if [[ -n "${tmp_free:-}" && "$tmp_free" -lt $((200 * 1024 * 1024)) ]]; then
    echo "[dexshell] WARN: /tmp low on space (run: volume-ready)" >&2
  fi
fi

# Seed Hermes free-first web config once (ddgs). Firecrawl used when key is set by user.
if [[ ! -f "$HOME_DIR/.hermes/config.yaml" ]]; then
  if [[ -f /opt/dexshell/home-seed/.hermes/config.yaml ]]; then
    mkdir -p "$HOME_DIR/.hermes"
    cp -a /opt/dexshell/home-seed/.hermes/config.yaml "$HOME_DIR/.hermes/config.yaml"
  fi
fi

# If Hermes already lives on the volume, quietly ensure Telegram/ddgs/firecrawl deps.
if [[ -x /usr/local/bin/hermes-inject ]]; then
  for venv in \
    "$HOME_DIR/.hermes/hermes-agent/.venv" \
    /usr/local/lib/hermes-agent/.venv
  do
    if [[ -x "$venv/bin/python" || -x "$venv/bin/python3" ]]; then
      # Only inject if telegram import missing (fast path).
      if ! "$venv/bin/python" -c "import telegram" 2>/dev/null; then
        /usr/local/bin/hermes-inject "$venv" >/tmp/dexshell-hermes-inject.log 2>&1 || true
      fi
      break
    fi
  done
fi

# Default command: SSH server
if [[ $# -eq 0 ]]; then
  set -- /usr/local/bin/dexshell ssh
fi

exec "$@"
