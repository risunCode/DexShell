# DexShell — always bind userland to the /app volume (no manual export).
# Sourced by login shells; entrypoint also exports the same values for SSH sessions.

: "${HOME:=/app}"
export HOME

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Agent / language tool homes on the volume
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
export PIP_USER="${PIP_USER:-1}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
export YARN_CACHE_FOLDER="${YARN_CACHE_FOLDER:-$HOME/.cache/yarn}"
export COMPOSER_HOME="${COMPOSER_HOME:-$HOME/.config/composer}"
export GEM_HOME="${GEM_HOME:-$HOME/.gem}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$HOME/.nuget/packages}"

# Common AI CLI config dirs (when tools honor XDG/HOME)
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
export KILO_HOME="${KILO_HOME:-$HOME/.kilo}"

# Prefer volume bins first, then system
_dexshell_path_prefix="$HOME/bin:$HOME/.local/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:$HOME/.cargo/bin:$HOME/go/bin:$PNPM_HOME:$HOME/.gem/bin:$HOME/.hermes/hermes-agent/.venv/bin:$HOME/.hermes/bin"
case ":${PATH:-}:" in
  *":$HOME/bin:"*) ;;
  *) export PATH="$_dexshell_path_prefix:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}" ;;
esac
unset _dexshell_path_prefix
