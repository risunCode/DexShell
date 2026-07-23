# DexShell — simple SSH shell on Debian 13 (trixie)
# Binary outside /app so Railway volume on /app won't hide it.
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
    PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"

# apt-get update is required during image build (package index is not cached in slim).
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    wget \
    git \
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
    sudo \
    locales \
    speedtest-cli \
    dialog \
    && rm -rf /var/lib/apt/lists/*

# Optional: fastfetch (+ neofetch alias). Skip if package missing.
RUN apt-get update \
    && (apt-get install -y --no-install-recommends fastfetch \
        && ln -sf "$(command -v fastfetch)" /usr/local/bin/neofetch \
        || echo "fastfetch not available, skip") \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /out/dexshell /usr/local/bin/dexshell
RUN chmod 755 /usr/local/bin/dexshell && mkdir -p /app

WORKDIR /app
EXPOSE 4444
CMD ["/usr/local/bin/dexshell", "ssh"]
