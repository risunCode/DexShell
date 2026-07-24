# DexShell

**Simple SSH-first remote shell for containers**

DexShell is a tiny Go binary that turns a Docker/Railway container into a usable remote Linux box over **SSH** (and **SFTP**), with optional bind/reverse shell modes. It is built for PaaS environments where a volume mount would otherwise hide your app binary.

> **v1.0.1** — Debian 13 (trixie), SSH + SFTP, PTY-ready, volume-safe `/app`, Bun/Node, Hermes Telegram + free websearch (`ddgs`) + Firecrawl support prebaked.

---

## What it is

| | |
|---|---|
| **Default mode** | Password SSH server with real PTY (PuTTY / OpenSSH / Termius) |
| **File transfer** | SFTP subsystem (WinSCP / FileZilla / `sftp` CLI) |
| **Optional modes** | `bind` shell, `reverse` shell |
| **Runtime image** | Debian 13 slim + practical admin / coding-agent installer deps |
| **Persistence** | User home, config, projects, agent data → **`/app` volume** |
| **Binary location** | `/usr/local/bin/dexshell` (outside the volume so mounts cannot hide it) |

DexShell is **not** a full VPS, not Docker-in-Docker, and not a hardened multi-tenant bastion. It is a convenience remote shell for containers you control.

---

## Features

- SSH password auth + interactive PTY (fixes “PuTTY connects then exits”)
- SFTP for uploading/downloading files to the persistent volume
- Live terminal resize (minimum useful size enforced for TUIs like `btop`: **80×24**)
- Env / dotenv config (no hardcoded secrets in the image)
- Volume-safe design for Railway-style mounts on `/app`
- Entrypoint bootstraps `$HOME` layout on the volume (bin, config, cache, agent homes)
- Seeded `fastfetch` config focused on **cgroup memory** + **`/`** and **`/app` disk** (not host-wide figures)
- Tooling deps ready for later CLI installs: `git`, `curl`, `wget`, `xz-utils`, `ripgrep`, `ffmpeg`, **Node.js**, **Bun**, `build-essential`, `python3`, etc.

---

## Quick start (local)

### Build

```bash
go build -o dexshell .
```

### Run SSH (default)

```bash
export SSH_PASSWORD='change-me-now'
./dexshell          # same as: ./dexshell ssh
# or
./dexshell ssh
```

### Other modes

```bash
./dexshell bind 4444
./dexshell reverse 10.0.0.5:4444
```

### Docker

```bash
docker build -t dexshell .
docker run --rm -it \
  -e SSH_PASSWORD='change-me-now' \
  -e SSH_USER=root \
  -e SSH_PORT=4444 \
  -p 4444:4444 \
  -v dexshell-data:/app \
  dexshell
```

Connect:

```bash
ssh -p 4444 root@127.0.0.1
sftp -P 4444 root@127.0.0.1
```

---

## Railway setup (recommended path)

### 1. Deploy from this repo

- Builder: **Dockerfile** (`railway.toml` already points at it)
- Start command (default via entrypoint):

```text
/usr/local/bin/dexshell-entrypoint /usr/local/bin/dexshell ssh
```

(or simply rely on image `CMD`)

### 2. Variables (Railway → Variables)

| Variable | Required | Default | Description |
|---|---|---|---|
| `SSH_PASSWORD` | **Yes** | _(none)_ | Login password. App **refuses to start** if empty. |
| `SSH_USER` | No | `root` | SSH / SFTP username |
| `SSH_PORT` | No | `PORT` or `4444` | Listen port inside the container |
| `HOME` | No | `/app` | Persistent home directory (must match volume mount) |
| `PORT` | No | — | Platform port fallback if `SSH_PORT` unset |

You can also place a real env file on the volume:

```text
/app/.env
```

Load order:

1. Process environment (Railway variables) — **wins**
2. `.env` in CWD
3. `/app/.env`
4. `$HOME/.env`

### 3. Volume

| Setting | Value |
|---|---|
| Mount path | **`/app`** |
| Purpose | Persistent home, projects, host key, agent data, SFTP root |

**Do not** put the DexShell binary under `/app`. The image installs it at `/usr/local/bin/dexshell` on purpose.

### 4. Networking

SSH/SFTP need **raw TCP**, not Cloudflare-proxied HTTP.

| Endpoint type | Use for SSH/SFTP? |
|---|---|
| Railway **TCP proxy** (`*.proxy.rlwy.net:PORT`) | ✅ Yes |
| Custom domain + Cloudflare **orange cloud** (HTTP proxy) | ❌ No |
| Custom domain DNS-only / direct TCP | ✅ Maybe (if truly TCP) |

Example:

```bash
ssh -p 57010 root@thomas.proxy.rlwy.net
sftp -P 57010 root@thomas.proxy.rlwy.net
```

Target port in Railway should map to container **`4444`** (or whatever `SSH_PORT` you set).

### 5. First login checklist

```bash
pwd                  # /app
echo hi > test.txt   # survives redeploy if volume is mounted
neofetch             # container-oriented stats (cgroup mem + / and /app disk)
btop                 # needs ~80x24 terminal
```

---

## Environment reference

### Auth / server

```bash
SSH_PASSWORD=...          # required
SSH_USER=root
SSH_PORT=4444             # or rely on platform PORT
HOME=/app
```

### Persistence / tooling paths (set by image + entrypoint)

These default under `/app` so installs and configs survive redeploys **when stored on the volume**:

| Variable | Default | Used for |
|---|---|---|
| `HOME` | `/app` | Shell home, SFTP root |
| `XDG_CONFIG_HOME` | `/app/.config` | App configs |
| `XDG_CACHE_HOME` | `/app/.cache` | Caches |
| `XDG_DATA_HOME` | `/app/.local/share` | Data files |
| `HERMES_HOME` | `/app/.hermes` | Hermes agent data |
| `BUN_INSTALL` | `/app/.bun` | Bun global packages |
| `npm_config_prefix` | `/app/.npm-global` | `npm i -g` targets |
| `CARGO_HOME` / `RUSTUP_HOME` | `/app/.cargo` / `/app/.rustup` | Rust tooling (if installed later) |
| `GOPATH` / `GOCACHE` | `/app/go` / `/app/.cache/go-build` | Go workspace/cache |
| `PYTHONUSERBASE` + `PIP_USER=1` | `/app/.local` | `pip install --user` |

`PATH` prefers:

```text
/app/bin
/app/.local/bin
/app/.bun/bin
/app/.npm-global/bin
/app/.cargo/bin
/app/go/bin
…system paths…
```

---

## Persistence model (important)

### Survives redeploy (on volume `/app`)

- Files and projects under `/app`
- `/app/.env`, shell history/dotfiles (after first seed)
- SSH host key: `/app/.dexshell/ssh_host_rsa_key`
- SFTP uploads into `/app`
- Agent/config data intentionally placed under `/app` (e.g. `/app/.hermes`)

### Does **not** survive redeploy by itself

- Packages installed only with runtime `apt install ...`
- Binaries dropped into `/usr/local/...` outside the volume
- Anything not stored under the mounted `/app` path

### Rule of thumb

| Goal | Where |
|---|---|
| Data / config / projects | `/app` |
| Tools you always need | Bake into `Dockerfile` |
| One-off CLI agents | Install into `/app` paths (`BUN_INSTALL`, `npm_config_prefix`, `$HOME/bin`, `HERMES_HOME`) |

Empty new volumes often only show `lost+found` until you write data — that is normal.

### Storage policy: `/tmp` vs `/app`

| Kind | Path | Survives redeploy? | Railway size (typical) |
|---|---|---|---|
| **Scratch** (downloads, build caches, extract) | `/tmp` | ❌ no | ~**10GB** free & hobby |
| **Durable** (tools you keep, configs, repos) | `/app` volume | ✅ yes | **500MB** free / **5GB** hobby |

**Rule:** installers download & build in **temp**; only the finished install lands on the **volume** when possible.

```bash
volume-ready    # layout + free space checker for /app and /tmp
```

Checker warns when volume free &lt; ~100MB (critical &lt; ~30MB) or `/tmp` free &lt; ~500MB.

### Approximate disk use (planning numbers)

These are **order-of-magnitude** estimates for capacity planning, not guarantees.

#### Image build / final image (not your volume)

| Component | Build scratch (temp) | Final image layer (approx) |
|---|---|---|
| Base Debian tools (apt set) | 200–500MB peak | **250–450MB** |
| Node.js 22 | 100–200MB peak | **80–150MB** |
| Bun (binary only kept) | 50–120MB peak | **40–80MB** |
| JetBrainsMono Nerd Font | 50–150MB zip peak | **10–40MB** |
| Hermes support (Python 3.11 + telegram/ddgs/firecrawl wheels) | 300–700MB peak | **150–350MB** |
| **Whole DexShell image (compressed registry)** | — | often **~0.8–1.5GB** |
| **Unpacked image on builder** | — | often **~1.5–3GB** |

Build uses `/tmp` aggressively and cleans caches each step so the builder temp (~10GB) stays workable.

#### Runtime volume `/app` (your 500MB / 5GB budget)

| What you put on volume | Approx after install |
|---|---|
| Dotfiles / host key / small config | **&lt; 5MB** |
| Hermes full install (`hermes-install`) | **250–450MB** |
| One coding CLI via npm/bun global | **50–200MB** each |
| Git repos / projects | size of the repo |
| Caches left on volume by mistake | can blow free tier fast |

**Free tier (500MB) guidance**
- Comfortable: configs + small projects + **one** agent (or Hermes alone if careful)
- Tight: Hermes + several global CLIs
- Avoid: dumping `apt` caches, large model weights, or npm/bun caches onto `/app`

**Hobby (5GB) guidance**
- Hermes + several CLIs + multiple repos is realistic
- Still keep scratch in `/tmp`

#### Peak temp during common runtime installs

| Action | Temp peak (approx) | Durable on `/app` |
|---|---|---|
| `hermes-install` | 0.5–1.5GB while downloading/building | 250–450MB |
| `npm i -g …` large CLI | 100–400MB | 50–200MB |
| `bun install -g …` | 50–300MB | varies |
| `apt install …` | uses image FS (not volume); lost on redeploy | n/a |

---

## Included image tooling (high level)

**Shell / ops:** bash, tmux, htop, btop, vim, nano, jq, tree, rsync, zip/unzip  
**Network:** curl, wget, git, openssh-client, nmap, tcpdump, netcat, dnsutils, traceroute  
**Agent installer deps:** xz-utils, ripgrep, ffmpeg, build-essential, python3, pip, venv  
**Runtimes baked for later installs:** Node.js (npm), Bun  
**Fonts:** JetBrainsMono Nerd Font (default monospace via fontconfig)  
**Info:** fastfetch (optional package; `neofetch` alias when available)

### Nerd Font note (important)

The image installs **JetBrainsMono Nerd Font** and sets it as the preferred `monospace` family for apps that honor **fontconfig** (some Linux GUI/TUI stacks).

SSH itself does **not** push fonts to your laptop. Glyphs/icons still depend on the font selected in your **SSH client**:

- Windows Terminal / VS Code terminal → set font to `JetBrainsMono Nerd Font`
- PuTTY → Appearance → Font → pick the Nerd Font installed on Windows
- macOS iTerm/Terminal → profile font → JetBrainsMono Nerd Font

Install the same font on your client from [Nerd Fonts – JetBrainsMono](https://github.com/ryanoasis/nerd-fonts/releases/latest).

DexShell does **not** preinstall third-party coding agents (Claude Code, Codex, OpenCode, Kilo, Kimchi, Hermes, …). The image aims to make those **installable**.

Example (after deploy):

```bash
# Hermes data on volume
hermes-install
# or: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser

# Other CLIs (examples — check upstream docs)
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://opencode.ai/install | bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
curl -fsSL https://kilo.ai/cli/install | bash
```

Prefer installing globals into volume-backed prefixes (`npm_config_prefix`, `BUN_INSTALL`, `$HOME/bin`) so config/binaries are less likely to vanish on redeploy.

---

## Modes

### `ssh` (default)

```bash
dexshell ssh
# or just: dexshell
```

- Password auth (`SSH_USER` / `SSH_PASSWORD`)
- Interactive shell with PTY
- SFTP subsystem enabled
- Working directory / SFTP root: `$HOME` (`/app`)

### `bind`

```bash
dexshell bind 4444
```

Listens for one raw TCP client and attaches a shell (not SSH).

### `reverse`

```bash
dexshell reverse host:port
```

Connects out to your listener and attaches a shell.

---

## Benefits

- **Fast remote access** to a container without building a full VM image workflow
- **SSH + SFTP** with normal clients (PuTTY, OpenSSH, WinSCP)
- **Volume-safe on Railway**: binary outside `/app`, data inside `/app`
- **PTY + resize** so TUI tools (`btop`, agents, editors) behave better
- **No secret defaults in the image**: password must be provided
- **Ready deps** for common coding-agent installers (curl/git/xz/rg/ffmpeg/node/bun)
- **Small mental model**: one binary, few env vars, Debian userspace

---

## Risks & limitations

### Security

- **Password SSH as root** is convenient and dangerous if exposed broadly
- Use a **strong** `SSH_PASSWORD`; rotate it if leaked
- Prefer Railway **TCP proxy** access control / keep endpoints private when possible
- This is **not** hardened OpenSSH with keys, fail2ban, jail, or auditd
- Anyone with the password has **root inside the container**
- Do not treat this as a public shared bastion

### Platform / container reality

- You get **container root**, not host root
- No guaranteed privileged mode / DinD / full systemd “like a VPS”
- Host stats in default system tools can look “global”; use the seeded fastfetch view for more local disk/memory context
- Runtime `apt install` is **ephemeral** unless baked into the image
- Redeploy replaces the container filesystem except mounted volumes

### Operational

- Wrong volume mount path (not `/app`) → “data disappeared” confusion
- Putting the app binary under a mounted `/app` → classic **executable not found**
- Cloudflare HTTP proxy in front of SSH → broken SSH
- Tiny terminal windows break some TUIs; DexShell enforces a minimum PTY of **80×24** when clients report smaller sizes
- SFTP and shell share the same credentials

### Legal / abuse

- Remote shell tools can be misused. Only run DexShell on systems and networks you are authorized to administer.
- Network scanners and offensive tooling in the image are for **your** lab/debug use, not unauthorized scanning.

---

## Architecture (short)

```text
Client (ssh/sftp)
    │  TCP
    ▼
Railway TCP proxy  ──►  container :4444
                           │
                           ├─ /usr/local/bin/dexshell   (image, immutable across deploys)
                           ├─ entrypoint bootstraps HOME layout
                           └─ /app  ◄── volume (persistent)
                                ├─ projects, .env, dotfiles
                                ├─ .dexshell/ssh_host_rsa_key
                                ├─ .hermes / .bun / .npm-global / ...
                                └─ SFTP root
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `executable /app/./dexshell could not be found` | Volume mounted on `/app` hid the binary | Use image with binary in `/usr/local/bin` + absolute start command |
| SSH works on TCP proxy, fails on custom domain | Cloudflare HTTP proxy | Use `*.proxy.rlwy.net` or DNS-only TCP |
| PuTTY exits immediately | No/broken PTY | Use current DexShell SSH mode (PTY enabled) |
| `btop` says terminal too small | Client size &lt; 80×24 | Update to build with min PTY size; enlarge client window |
| `SSH_PASSWORD is required` | Env not set | Set Railway variable or `/app/.env` |
| `apt install` package gone after redeploy | Not on volume / not baked | Bake into Dockerfile or reinstall |
| `neofetch` shows huge host RAM/disk | Default host view | Use seeded config / `neofetch` alias after redeploy |
| Hermes extract fails (`xz`) | Missing `xz-utils` | Present in current image; `apt install xz-utils` on old deploys |

---

## Development

```bash
go mod tidy
go build -o bin/dexshell .
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bin/dexshell-linux .
```

Main pieces:

| Path | Role |
|---|---|
| `main.go` | SSH/SFTP/bind/reverse + PTY + env/home layout |
| `Dockerfile` | Multi-stage Go build + Debian 13 runtime |
| `docker/entrypoint.sh` | Volume bootstrap + persistent env, then exec |
| `docker/install.sh` | Slim Dockerfile install steps (`base` / `hermes` / `finalize`) |
| `docker/home/` | First-boot dotfiles/config copied into `/app` if missing |
| `docker/bin/` | Image helpers (`hermes`, `hermes-install`, `hermes-inject`, `volume-ready`, `volume-env.sh`) |
| `docker/hermes-requirements.txt` | Prebaked Hermes support Python deps |
| `railway.toml` | Dockerfile builder + start command |

---

## License

MIT

---

## Disclaimer

DexShell is provided as-is for legitimate remote administration and development of containers you own or are authorized to use. You are responsible for access control, secrets, and compliance with your provider’s terms.
