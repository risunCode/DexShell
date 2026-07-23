FROM golang:1.25-alpine

# Install runtime utilities
RUN apk add --no-cache \
    bash \
    curl \
    netcat-openbsd \
    iproute2 \
    iputils-ping \
    traceroute \
    bind-tools \
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
    fd \
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
    py3-pip \
    openssh

WORKDIR /app
COPY go.mod go.sum ./
COPY vendor ./vendor
COPY . ./
RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o dexshell .
RUN chmod +x dexshell
EXPOSE 4444 2222
CMD ["./dexshell", "bind", "4444"]
