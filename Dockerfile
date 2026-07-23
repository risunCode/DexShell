# DexShell — SSH/SFTP shell on Debian 13 with /app volume as persistent home.
# App binary stays outside /app so Railway volume mounts cannot hide it.
FROM golang:1.25-trixie AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/dexshell .

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/app \
    TERM=xterm-256color \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    PATH="/app/bin:/app/.local/bin:/app/.bun/bin:/app/.npm-global/bin:/app/.cargo/bin:/app/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" \
    XDG_CONFIG_HOME=/app/.config \
    XDG_CACHE_HOME=/app/.cache \
    XDG_DATA_HOME=/app/.local/share \
    XDG_STATE_HOME=/app/.local/state \
    HERMES_HOME=/app/.hermes \
    BUN_INSTALL=/app/.bun \
    npm_config_prefix=/app/.npm-global \
    CARGO_HOME=/app/.cargo \
    RUSTUP_HOME=/app/.rustup \
    GOPATH=/app/go \
    GOCACHE=/app/.cache/go-build \
    PYTHONUSERBASE=/app/.local \
    PIP_USER=1 \
    UV_LINK_MODE=copy \
    DEXSHELL_SEED=/opt/dexshell/home-seed

# Base tools + coding-agent installer deps.
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Optional eyecandy.
RUN apt-get update \
    && (apt-get install -y --no-install-recommends fastfetch \
        && ln -sf "$(command -v fastfetch)" /usr/local/bin/neofetch \
        || echo "fastfetch not available, skip") \
    && rm -rf /var/lib/apt/lists/*

# Node.js (for npm -g agent CLIs). Prefer NodeSource 22, fallback to distro nodejs/npm.
RUN apt-get update \
    && (curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
        && apt-get install -y --no-install-recommends nodejs \
        || apt-get install -y --no-install-recommends nodejs npm) \
    && rm -rf /var/lib/apt/lists/* \
    && node -v \
    && npm -v

# Bun runtime (system binary; user global packages still go to /app/.bun via BUN_INSTALL).
RUN curl -fsSL https://bun.sh/install | bash \
    && if [ -x /root/.bun/bin/bun ]; then install -m 755 /root/.bun/bin/bun /usr/local/bin/bun; fi \
    && if [ -x /root/.bun/bin/bunx ]; then install -m 755 /root/.bun/bin/bunx /usr/local/bin/bunx; fi \
    && rm -rf /root/.bun \
    && bun --version

# JetBrainsMono Nerd Font (for TUI glyph/icon support).
# Note: SSH clients still need a Nerd Font selected on the *client* side to render glyphs.
RUN apt-get update && apt-get install -y --no-install-recommends fontconfig \
    && mkdir -p /usr/local/share/fonts/truetype/jetbrainsmono-nerd \
    && curl -fsSL -o /tmp/JetBrainsMono.zip \
         https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    && unzip -qo /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono \
    && find /tmp/JetBrainsMono -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
         -exec cp -a {} /usr/local/share/fonts/truetype/jetbrainsmono-nerd/ \; \
    && rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip \
    && printf '%s\n' \
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
         > /etc/fonts/conf.d/59-dexshell-jetbrainsmono-nerd.conf \
    && fc-cache -f \
    && (fc-list | grep -qi 'JetBrainsMono' || fc-list | grep -qi 'JetBrains') \
    && rm -rf /var/lib/apt/lists/*

# Seed files for first boot onto the volume (copied by entrypoint if missing).
COPY home-seed/ /opt/dexshell/home-seed/
COPY entrypoint.sh /usr/local/bin/dexshell-entrypoint
RUN chmod 755 /usr/local/bin/dexshell-entrypoint \
    && find /opt/dexshell/home-seed -type f -exec chmod 644 {} \;

COPY --from=builder /out/dexshell /usr/local/bin/dexshell
RUN chmod 755 /usr/local/bin/dexshell \
    && mkdir -p /app

WORKDIR /app
EXPOSE 4444
ENTRYPOINT ["/usr/local/bin/dexshell-entrypoint"]
CMD ["/usr/local/bin/dexshell", "ssh"]
