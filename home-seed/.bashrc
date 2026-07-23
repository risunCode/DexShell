# DexShell persistent home (volume: /app) — sourced on interactive shells.
# Paths are also set by /etc/profile.d/dexshell-volume.sh and the entrypoint.

export HOME="${HOME:-/app}"

# shellcheck disable=SC1091
if [ -f /etc/profile.d/dexshell-volume.sh ]; then
  . /etc/profile.d/dexshell-volume.sh
fi

export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$HOME/go/bin:$HOME/.hermes/bin:$HOME/.hermes/hermes-agent/.venv/bin:${PNPM_HOME:-$HOME/.local/share/pnpm}:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export npm_config_prefix="${npm_config_prefix:-$HOME/.npm-global}"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-$npm_config_prefix}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-$HOME/.cache/npm}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export GOPATH="${GOPATH:-$HOME/go}"
export GOBIN="${GOBIN:-$HOME/go/bin}"
export GOCACHE="${GOCACHE:-$HOME/.cache/go-build}"
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME/.local}"
export PIP_USER=1
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
export KILO_HOME="${KILO_HOME:-$HOME/.kilo}"
export TERM="${TERM:-xterm-256color}"
export DEXSHELL_NERD_FONT="JetBrainsMono Nerd Font"

# Handy aliases
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'

# Container-oriented system info (cgroup memory + /app disk).
ff() {
  if command -v fastfetch >/dev/null 2>&1; then
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
      fastfetch --config "$HOME/.config/fastfetch/config.jsonc" "$@"
    else
      fastfetch "$@"
    fi
  elif command -v neofetch >/dev/null 2>&1; then
    neofetch "$@"
  else
    echo "fastfetch/neofetch not installed"
  fi
}
alias neofetch='ff'
alias fastfetch='ff'

# Install targets (all on the volume):
#   bun install -g ...     -> $BUN_INSTALL (/app/.bun)
#   npm install -g ...     -> $npm_config_prefix (/app/.npm-global)
#   pip install --user ... -> $PYTHONUSERBASE (/app/.local)
#   hermes                 -> dexshell-install-hermes  (onto /app/.hermes)
#   custom bins            -> $HOME/bin

PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
