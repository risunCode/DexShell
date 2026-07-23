# Force-working DexShell image.
# Binary lives OUTSIDE /app so Railway volume mounts on /app cannot hide it.
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

# Binary outside any likely volume mount path
COPY --from=builder /out/dexshell /usr/local/bin/dexshell
RUN chmod 755 /usr/local/bin/dexshell \
    && test -x /usr/local/bin/dexshell \
    && /usr/local/bin/dexshell 2>&1 | head -n 5 || true

# App/data dir (safe for Railway volume mount at /app)
WORKDIR /app
RUN mkdir -p /app

ENV PATH="/usr/local/bin:${PATH}"
EXPOSE 4444 2222

# Absolute path — never relative ./dexshell
CMD ["/usr/local/bin/dexshell", "bind", "4444"]
