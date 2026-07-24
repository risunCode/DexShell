#!/usr/bin/env bash
# Image build helpers. Keep Dockerfile thin — all heavy install lives here.
# Usage: install.sh <base|hermes|finalize>
set -eu
# NOTE: do not enable pipefail globally — curl|bash / fc-list|grep can yield SIGPIPE (141).

export DEBIAN_FRONTEND=noninteractive
export TMPDIR=/tmp TMP=/tmp TEMP=/tmp

clean_tmp() {
  apt-get clean 2>/dev/null || true
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    /tmp/* /var/tmp/* /root/.cache /root/.npm 2>/dev/null || true
}

run_curl_bash() {
  # Avoid pipefail/SIGPIPE (exit 141) from curl|bash progress pipes.
  local url="$1"
  shift
  local tmp
  tmp="$(mktemp /tmp/install-script.XXXXXX.sh)"
  curl -fsSL "$url" -o "$tmp"
  bash "$tmp" "$@"
  rm -f "$tmp"
}

install_base() {
  apt-get update
  apt-get install -y --no-install-recommends \
    bash ca-certificates curl wget git xz-utils openssh-client netcat-openbsd \
    iproute2 iputils-ping dnsutils traceroute net-tools procps psmisc \
    htop btop tmux vim nano less jq tree nmap tcpdump strace lsof \
    zip unzip rsync python3 python3-pip python3-venv sudo locales \
    speedtest-cli dialog ripgrep ffmpeg build-essential pkg-config \
    file gnupg fontconfig

  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen en_US.UTF-8
  update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  clean_tmp

  # optional fastfetch
  apt-get update
  if apt-get install -y --no-install-recommends fastfetch; then
    ln -sf "$(command -v fastfetch)" /usr/local/bin/neofetch || true
  fi
  clean_tmp

  # Node 22 (fallback distro node)
  apt-get update
  if run_curl_bash https://deb.nodesource.com/setup_22.x \
    && apt-get install -y --no-install-recommends nodejs; then
    :
  else
    apt-get install -y --no-install-recommends nodejs npm
  fi
  node -v
  npm -v
  npm cache clean --force 2>/dev/null || true
  clean_tmp

  # Bun → system binary only (globals later use $BUN_INSTALL on volume)
  # Install into /tmp, copy binary out, never leave install root under /app.
  export HOME=/root
  export BUN_INSTALL=/tmp/bun-install
  mkdir -p /tmp/bun-install
  run_curl_bash https://bun.sh/install
  install -m 755 /tmp/bun-install/bin/bun /usr/local/bin/bun
  if [[ -x /tmp/bun-install/bin/bunx ]]; then
    install -m 755 /tmp/bun-install/bin/bunx /usr/local/bin/bunx
  fi
  /usr/local/bin/bun --version
  rm -rf /tmp/bun-install /root/.bun
  clean_tmp

  # JetBrainsMono Nerd Font (download/extract in /tmp only)
  mkdir -p /usr/local/share/fonts/truetype/jetbrainsmono-nerd /tmp/fonts
  curl -fsSL -o /tmp/fonts/JetBrainsMono.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
  unzip -qo /tmp/fonts/JetBrainsMono.zip -d /tmp/fonts/JetBrainsMono
  find /tmp/fonts/JetBrainsMono -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
    -exec cp -a {} /usr/local/share/fonts/truetype/jetbrainsmono-nerd/ \;
  cat >/etc/fonts/conf.d/59-dexshell-jetbrainsmono-nerd.conf <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font</family></prefer>
  </alias>
  <alias>
    <family>JetBrains Mono</family>
    <prefer><family>JetBrainsMono Nerd Font</family></prefer>
  </alias>
</fontconfig>
XML
  fc-cache -f
  # Soft-check only: font family string varies slightly across releases.
  if ! fc-list 2>/dev/null | grep -qi 'jetbrains'; then
    echo "WARN: JetBrains font not visible to fc-list yet (continuing)" >&2
  fi
  clean_tmp
  rm -rf /var/cache/fontconfig/* 2>/dev/null || true
}

install_hermes_support() {
  # Isolated Python 3.11 support stack for Hermes Telegram/web deps.
  # Override image HOME/XDG (/app) so uv never writes into the volume path during build.
  export HOME=/root
  export XDG_CONFIG_HOME=/root/.config
  export XDG_DATA_HOME=/root/.local/share
  export XDG_STATE_HOME=/root/.local/state
  export XDG_CACHE_HOME=/tmp/xdg-cache
  export UV_CACHE_DIR=/tmp/uv-cache
  export UV_LINK_MODE=copy
  export UV_PYTHON_INSTALL_DIR=/opt/dexshell/uv/python
  export PIP_CACHE_DIR=/tmp/pip-cache
  mkdir -p /tmp/xdg-cache /tmp/uv-cache /tmp/pip-cache /root/.local/bin

  run_curl_bash https://astral.sh/uv/install.sh
  UV_BIN=""
  for c in /root/.local/bin/uv /root/.cargo/bin/uv "$(command -v uv || true)"; do
    if [[ -n "$c" && -x "$c" ]]; then UV_BIN="$c"; break; fi
  done
  if [[ -z "$UV_BIN" || ! -x "$UV_BIN" ]]; then
    echo "uv binary not found after install" >&2
    exit 1
  fi
  install -m 755 "$UV_BIN" /usr/local/bin/uv
  uv --version
  uv python install 3.11

  mkdir -p /opt/dexshell/hermes-support/wheels
  # --seed ensures pip exists in the venv
  uv venv --python 3.11 --seed /opt/dexshell/hermes-support/venv
  VENV_PY=/opt/dexshell/hermes-support/venv/bin/python

  # uv has no stable `pip download`; use venv pip for wheelhouse + install.
  "$VENV_PY" -m pip install -U pip wheel setuptools
  "$VENV_PY" -m pip download \
    -d /opt/dexshell/hermes-support/wheels \
    -r /opt/dexshell/hermes-support/requirements.txt
  "$VENV_PY" -m pip install \
    --no-index --find-links=/opt/dexshell/hermes-support/wheels \
    -r /opt/dexshell/hermes-support/requirements.txt \
    || "$VENV_PY" -m pip install -r /opt/dexshell/hermes-support/requirements.txt

  "$VENV_PY" -c "import telegram, ddgs; print('hermes-support imports ok')"

  # drop any accidental writes under /app during build
  rm -rf /app/.local /app/bin /tmp/uv-cache /tmp/pip-cache /tmp/xdg-cache
  clean_tmp
}

finalize_image() {
  mkdir -p /opt/dexshell/wrappers /app
  if [[ -x /usr/local/bin/hermes ]]; then
    cp -a /usr/local/bin/hermes /opt/dexshell/wrappers/hermes
  fi
  chmod 755 /usr/local/bin/hermes \
            /opt/dexshell/wrappers/hermes \
            /usr/local/bin/hermes-install \
            /usr/local/bin/hermes-inject \
            /usr/local/bin/volume-ready \
            /usr/local/bin/dexshell-entrypoint 2>/dev/null || true
  # compat aliases for older docs/muscle memory
  ln -sfn /usr/local/bin/hermes-install /usr/local/bin/dexshell-install-hermes
  ln -sfn /usr/local/bin/hermes-inject /usr/local/bin/dexshell-inject-hermes-deps
  ln -sfn /usr/local/bin/volume-ready /usr/local/bin/dexshell-volume-ready
  chmod 644 /etc/profile.d/10-volume-env.sh 2>/dev/null || true
  # keep legacy filename symlink if something still sources the old path
  if [[ -f /etc/profile.d/10-volume-env.sh && ! -e /etc/profile.d/dexshell-volume.sh ]]; then
    ln -sfn 10-volume-env.sh /etc/profile.d/dexshell-volume.sh
  fi
  if [[ -d /opt/dexshell/home-seed ]]; then
    find /opt/dexshell/home-seed -type f -exec chmod 644 {} \;
  fi
  clean_tmp
}

cmd="${1:-}"
case "$cmd" in
  base) install_base ;;
  hermes) install_hermes_support ;;
  finalize) finalize_image ;;
  *)
    echo "usage: $0 {base|hermes|finalize}" >&2
    exit 2
    ;;
esac
