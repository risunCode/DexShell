# Build stage
FROM debian:trixie-slim AS builder

# Install build dependencies
RUN apt update && apt upgrade -y && \
    apt install -y \
    golang-go \
    git \
    build-essential \
    ca-certificates \
    wget

WORKDIR /build
COPY go.mod .
COPY main.go .

# Build DexShell
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o dexshell .

# Runtime stage
FROM debian:trixie-slim

# Install runtime tools and "pamer" tools
RUN apt update && apt upgrade -y && \
    apt install -y \
    # Shell & basic tools
    bash \
    curl \
    wget \
    netcat-openbsd \
    iproute2 \
    iputils-ping \
    traceroute \
    dnsutils \
    # System info & monitoring (pamer tools)
    fastfetch \
    htop \
    btop \
    glances \
    # Terminal tools
    tmux \
    vim \
    nano \
    jq \
    bat \
    eza \
    ripgrep \
    fd-find \
    fzf \
    tree \
    # Network tools
    nmap \
    tcpdump \
    whois \
    # System utilities
    strace \
    lsof \
    psmisc \
    # File tools
    zip \
    unzip \
    rsync \
    # Development
    git \
    python3 \
    python3-pip \
    # SSH server
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/dexshell .
COPY .env.example .env

# Expose default shell port and SSH port
EXPOSE 4444 2222

# Default to bind shell on port 4444
CMD ["./dexshell", "bind", "4444"]
