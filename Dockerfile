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
COPY --from=builder /build/dexshell .

RUN chmod +x dexshell

EXPOSE 4444 2222

CMD ["./dexshell", "bind", "4444"]
