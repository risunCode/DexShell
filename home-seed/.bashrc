# DexShell persistent home (volume: /app)
export HOME="${HOME:-/app}"
export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$HOME/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export npm_config_prefix="${npm_config_prefix:-$HOME/.npm-global}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export GOPATH="${GOPATH:-$HOME/go}"
export GOCACHE="${GOCACHE:-$HOME/.cache/go-build}"
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME/.local}"
export PIP_USER=1
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export TERM="${TERM:-xterm-256color}"

# Handy aliases
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'

# Container-oriented system info (cgroup memory + /app disk).
# Host-wide Memory/Disk from default fastfetch is often misleading on Railway.
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

# Keep agent CLIs / tools on the volume when possible:
#   bun install -g ...        -> $HOME/.bun
#   npm install -g ...        -> $HOME/.npm-global
#   pip install --user ...    -> $HOME/.local
#   hermes (HERMES_HOME)      -> $HOME/.hermes
#   put binaries in           -> $HOME/bin

PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
