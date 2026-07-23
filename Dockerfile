# DexShell — SSH/SFTP on Debian 13, userland bound to /app volume.
# Binary stays outside /app so Railway volume mounts cannot hide it.
# Build-time downloads/extracts use /tmp only, then cleaned (don't bloat image or volume).
FROM golang:1.25-trixie AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/dexshell . \
    && rm -rf /tmp/* /root/.cache 2>/dev/null || true

FROM debian:trixie-slim

# Runtime defaults (volume paths). Build steps below override TMP/BUN dirs to /tmp.
ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/app \
    TERM=xterm-256color \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    PATH="/app/bin:/app/.local/bin:/app/.bun/bin:/app/.npm-global/bin:/app/.cargo/bin:/app/go/bin:/app/.hermes/bin:/app/.hermes/hermes-agent/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" \
    XDG_CONFIG_HOME=/app/.config \
    XDG_CACHE_HOME=/app/.cache \
    XDG_DATA_HOME=/app/.local/share \
    XDG_STATE_HOME=/app/.local/state \
    HERMES_HOME=/app/.hermes \
    BUN_INSTALL=/app/.bun \
    npm_config_prefix=/app/.npm-global \
    NPM_CONFIG_PREFIX=/app/.npm-global \
    NPM_CONFIG_CACHE=/app/.cache/npm \
    CARGO_HOME=/app/.cargo \
    RUSTUP_HOME=/app/.rustup \
    GOPATH=/app/go \
    GOBIN=/app/go/bin \
    GOCACHE=/app/.cache/go-build \
    PYTHONUSERBASE=/app/.local \
    PIP_USER=1 \
    UV_LINK_MODE=copy \
    UV_CACHE_DIR=/app/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/app/.local/share/uv/python \
    PNPM_HOME=/app/.local/share/pnpm \
    CLAUDE_CONFIG_DIR=/app/.config/claude \
    CODEX_HOME=/app/.codex \
    OPENCODE_CONFIG_DIR=/app/.config/opencode \
    KILO_HOME=/app/.kilo \
    DEXSHELL_SEED=/opt/dexshell/home-seed \
    TMPDIR=/tmp \
    TMP=/tmp \
    TEMP=/tmp

# Base tools + coding-agent installer deps (apt work stays in /var + /tmp, then purged).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      wget \
      git \
      xz-utils \
      openssh-client \
      netcat-openbsd \
      iproute2 \
      iputils-ping \
      dnsutils \
      traceroute \
      net-tools \
      procps \
      psmisc \
      htop \
      btop \
      tmux \
      vim \
      nano \
      less \
      jq \
      tree \
      nmap \
      tcpdump \
      strace \
      lsof \
      zip \
      unzip \
      rsync \
      python3 \
      python3-pip \
      python3-venv \
      sudo \
      locales \
      speedtest-cli \
      dialog \
      ripgrep \
      ffmpeg \
      build-essential \
      pkg-config \
      file \
      gnupg \
      fontconfig; \
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
    locale-gen en_US.UTF-8; \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# Optional eyecandy.
RUN set -eux; \
    apt-get update; \
    (apt-get install -y --no-install-recommends fastfetch \
      && ln -sf "$(command -v fastfetch)" /usr/local/bin/neofetch \
      || echo "fastfetch not available, skip"); \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# Node.js 22 — NodeSource setup uses /tmp; purge apt caches after.
RUN set -eux; \
    apt-get update; \
    (curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
      && apt-get install -y --no-install-recommends nodejs \
      || apt-get install -y --no-install-recommends nodejs npm); \
    node -v; \
    npm -v; \
    npm cache clean --force 2>/dev/null || true; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/* /root/.npm

# Bun: install into /tmp, keep only binary in /usr/local/bin (NOT /app — volume is runtime-only).
RUN set -eux; \
    BUN_INSTALL=/tmp/bun-install; \
    export BUN_INSTALL TMPDIR=/tmp TMP=/tmp TEMP=/tmp; \
    curl -fsSL https://bun.sh/install | bash; \
    install -m 755 /tmp/bun-install/bin/bun /usr/local/bin/bun; \
    if [ -x /tmp/bun-install/bin/bunx ]; then install -m 755 /tmp/bun-install/bin/bunx /usr/local/bin/bunx; fi; \
    /usr/local/bin/bun --version; \
    rm -rf /tmp/bun-install /tmp/* /root/.bun /var/tmp/*

# JetBrainsMono Nerd Font — download/unzip in /tmp only.
RUN set -eux; \
    mkdir -p /usr/local/share/fonts/truetype/jetbrainsmono-nerd /tmp/fonts; \
    curl -fsSL -o /tmp/fonts/JetBrainsMono.zip \
      https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip; \
    unzip -qo /tmp/fonts/JetBrainsMono.zip -d /tmp/fonts/JetBrainsMono; \
    find /tmp/fonts/JetBrainsMono -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
      -exec cp -a {} /usr/local/share/fonts/truetype/jetbrainsmono-nerd/ \; ; \
    printf '%s\n' \
      '<?xml version="1.0"?>' \
      '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">' \
      '<fontconfig>' \
      '  <alias>' \
      '    <family>monospace</family>' \
      '    <prefer><family>JetBrainsMono Nerd Font</family></prefer>' \
      '  </alias>' \
      '  <alias>' \
      '    <family>JetBrains Mono</family>' \
      '    <prefer><family>JetBrainsMono Nerd Font</family></prefer>' \
      '  </alias>' \
      '</fontconfig>' \
      > /etc/fonts/conf.d/59-dexshell-jetbrainsmono-nerd.conf; \
    fc-cache -f; \
    (fc-list | grep -qi 'JetBrainsMono' || fc-list | grep -qi 'JetBrains'); \
    rm -rf /tmp/fonts /tmp/* /var/tmp/* /var/cache/fontconfig/*

# Volume-bound profile + helpers (hermes wrapper, installers, path defaults).
COPY rootfs/ /
RUN mkdir -p /opt/dexshell/wrappers \
    && cp -a /usr/local/bin/hermes /opt/dexshell/wrappers/hermes \
    && chmod 755 /usr/local/bin/hermes \
                 /opt/dexshell/wrappers/hermes \
                 /usr/local/bin/dexshell-install-hermes \
                 /usr/local/bin/dexshell-volume-ready \
    && chmod 644 /etc/profile.d/dexshell-volume.sh \
    && rm -rf /tmp/* /var/tmp/*

# Seed files for first boot onto the volume (copied by entrypoint if missing).
COPY home-seed/ /opt/dexshell/home-seed/
COPY entrypoint.sh /usr/local/bin/dexshell-entrypoint
RUN chmod 755 /usr/local/bin/dexshell-entrypoint \
    && find /opt/dexshell/home-seed -type f -exec chmod 644 {} \; \
    && rm -rf /tmp/* /var/tmp/*

COPY --from=builder /out/dexshell /usr/local/bin/dexshell
RUN chmod 755 /usr/local/bin/dexshell \
    && mkdir -p /app \
    && rm -rf /tmp/* /var/tmp/* /root/.cache 2>/dev/null || true

WORKDIR /app
EXPOSE 4444
ENTRYPOINT ["/usr/local/bin/dexshell-entrypoint"]
CMD ["/usr/local/bin/dexshell", "ssh"]
