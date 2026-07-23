# ---------- Builder stage ----------
FROM golang:1.25-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /dexshell .

# ---------- Runtime stage ----------
FROM debian:stable-slim
# Install utilities required at runtime
RUN apt update && apt install -y \
    bash \
    curl \
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
    python3 \
    python3-pip \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /dexshell /app/dexshell
RUN chmod +x /app/dexshell
EXPOSE 4444 2222
CMD ["/app/dexshell", "bind", "4444"]
