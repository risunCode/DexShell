FROM debian:latest

# Install everything in one stage
RUN apt update && apt install -y \
    golang-go \
    git \
    build-essential \
    ca-certificates \
    wget \
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
COPY go.mod go.sum main.go vendor/ ./

RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -o dexshell .

EXPOSE 4444 2222

CMD ["./dexshell", "bind", "4444"]
