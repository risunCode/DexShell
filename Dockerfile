# DexShell — SSH-first image.
# Binary lives OUTSIDE /app so Railway volume mounts on /app cannot hide it.
# /app is the persistent home (history, files, host key).
FROM golang:1.25-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
COPY vendor ./vendor
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -mod=vendor -trimpath -ldflags="-s -w" -o /out/dexshell . \
    && test -x /out/dexshell

FROM alpine:3.21

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    netcat-openbsd \
    iproute2 \
    iputils \
    bind-tools \
    busybox-extras \
    htop \
    tmux \
    vim \
    nano \
    jq \
    tree \
    nmap \
    tcpdump \
    openssh \
    python3 \
    && rm -rf /var/cache/apk/*

COPY --from=builder /out/dexshell /usr/local/bin/dexshell
RUN chmod 755 /usr/local/bin/dexshell \
    && test -x /usr/local/bin/dexshell

# Persistent session/data dir (Railway volume should mount here)
WORKDIR /app
RUN mkdir -p /app

ENV PATH="/usr/local/bin:${PATH}" \
    HOME=/app \
    SSH_USER=root \
    SSH_PORT=4444 \
    SSH_PASSWORD=changeme

EXPOSE 4444

# Absolute path + SSH-only
CMD ["/usr/local/bin/dexshell", "ssh"]
