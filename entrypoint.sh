#!/usr/bin/env bash
# Bootstrap persistent HOME on the Railway volume (/app), then exec dexshell.
set -euo pipefail

HOME_DIR="${HOME:-/app}"
SEED_DIR="${DEXSHELL_SEED:-/opt/dexshell/home-seed}"

mkdir -p \
  "$HOME_DIR" \
  "$HOME_DIR/bin" \
  "$HOME_DIR/.local/bin" \
  "$HOME_DIR/.config" \
  "$HOME_DIR/.cache" \
  "$HOME_DIR/.local/share" \
  "$HOME_DIR/.dexshell" \
  "$HOME_DIR/projects" \
  "$HOME_DIR/.npm-global" \
  "$HOME_DIR/.bun" \
  "$HOME_DIR/.hermes" \
  "$HOME_DIR/.cargo/bin" \
  "$HOME_DIR/go/bin"

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

export HOME="$HOME_DIR"
export USER="${USER:-root}"
export PATH="$HOME_DIR/bin:$HOME_DIR/.local/bin:$HOME_DIR/.bun/bin:$HOME_DIR/.npm-global/bin:$HOME_DIR/.cargo/bin:$HOME_DIR/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME_DIR/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME_DIR/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME_DIR/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME_DIR/.local/state}"
export HERMES_HOME="${HERMES_HOME:-$HOME_DIR/.hermes}"
export npm_config_prefix="${npm_config_prefix:-$HOME_DIR/.npm-global}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME_DIR/.bun}"
export CARGO_HOME="${CARGO_HOME:-$HOME_DIR/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME_DIR/.rustup}"
export GOPATH="${GOPATH:-$HOME_DIR/go}"
export GOCACHE="${GOCACHE:-$HOME_DIR/.cache/go-build}"
export PIP_USER=1
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME_DIR/.local}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-$HOME_DIR/.cache/npm}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

# Default command: SSH server
if [[ $# -eq 0 ]]; then
  set -- /usr/local/bin/dexshell ssh
fi

exec "$@"
