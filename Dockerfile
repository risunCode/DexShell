FROM golang:1.22-alpine

# Install runtime utilities
RUN apk add --no-cache \
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
    py3-pip \
    openssh-server

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
RUN CGO_ENABLED=0 GOOS=linux go build -o dexshell .
RUN chmod +x dexshell
EXPOSE 4444 2222
CMD ["./dexshell", "bind", "4444"]
