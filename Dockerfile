# DexShell — thin Dockerfile. Heavy install logic lives in docker/install-runtime.sh
# Binary outside /app so Railway volume mounts cannot hide it.
FROM golang:1.25-trixie AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/dexshell . \
    && rm -rf /tmp/* /root/.cache 2>/dev/null || true

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/app \
    TERM=xterm-256color \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    PATH="/app/bin:/app/.local/bin:/app/.bun/bin:/app/.npm-global/bin:/app/.cargo/bin:/app/go/bin:/app/.hermes/bin:/app/.hermes/hermes-agent/.venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" \
    XDG_CONFIG_HOME=/app/.config \
    XDG_CACHE_HOME=/app/.cache \
    XDG_DATA_HOME=/app/.local/share \
    XDG_STATE_HOME=/app/.local/state \
    HERMES_HOME=/app/.hermes \
    BUN_INSTALL=/app/.bun \
    npm_config_prefix=/app/.npm-global \
    NPM_CONFIG_PREFIX=/app/.npm-global \
    NPM_CONFIG_CACHE=/app/.cache/npm \
    CARGO_HOME=/app/.cargo \
    RUSTUP_HOME=/app/.rustup \
    GOPATH=/app/go \
    GOBIN=/app/go/bin \
    GOCACHE=/app/.cache/go-build \
    PYTHONUSERBASE=/app/.local \
    PIP_USER=1 \
    UV_LINK_MODE=copy \
    UV_CACHE_DIR=/app/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/app/.local/share/uv/python \
    PNPM_HOME=/app/.local/share/pnpm \
    CLAUDE_CONFIG_DIR=/app/.config/claude \
    CODEX_HOME=/app/.codex \
    OPENCODE_CONFIG_DIR=/app/.config/opencode \
    KILO_HOME=/app/.kilo \
    DEXSHELL_SEED=/opt/dexshell/home-seed \
    TMPDIR=/tmp \
    TMP=/tmp \
    TEMP=/tmp

COPY docker/install-runtime.sh /tmp/install-runtime.sh
RUN chmod +x /tmp/install-runtime.sh && /tmp/install-runtime.sh base

COPY rootfs/ /
RUN /tmp/install-runtime.sh hermes

COPY home-seed/ /opt/dexshell/home-seed/
COPY docker/entrypoint.sh /usr/local/bin/dexshell-entrypoint
RUN /tmp/install-runtime.sh finalize && rm -f /tmp/install-runtime.sh

COPY --from=builder /out/dexshell /usr/local/bin/dexshell
RUN chmod 755 /usr/local/bin/dexshell && mkdir -p /app

WORKDIR /app
EXPOSE 4444
ENTRYPOINT ["/usr/local/bin/dexshell-entrypoint"]
CMD ["/usr/local/bin/dexshell", "ssh"]
