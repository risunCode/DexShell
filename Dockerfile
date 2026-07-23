# Build stage
FROM debian:latest AS builder

# Install build dependencies
RUN apt update && apt install -y \
    golang-go \
    git \
    build-essential \
    ca-certificates \
    wget

WORKDIR /build
COPY go.mod .
COPY go.sum .
COPY main.go .
COPY vendor/ vendor/

# Build DexShell with vendor mode
RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o dexshell .

# Verify binary exists
RUN test -f /build/dexshell && echo "Binary exists"

# Runtime stage
FROM debian:latest

# Install runtime tools and "pamer" tools
RUN apt update && apt install -y \
    bash \
    curl \
    wget \
    netcat-openbsd \
    iproute2 \
    iputils-ping \
    traceroute \
    dnsutils \
    fastfetch \
    htop \
    btop \
    glances \
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
    nmap \
    tcpdump \
    whois \
    strace \
    lsof \
    psmisc \
    zip \
    unzip \
    rsync \
    git \
    python3 \
    python3-pip \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/dexshell /app/dexshell

RUN chmod +x /app/dexshell

# Verify binary exists in runtime
RUN test -f /app/dexshell && echo "Binary exists in /app" && ls -la /app/

EXPOSE 4444 2222

CMD ["/app/dexshell", "bind", "4444"]
