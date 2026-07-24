# DexShell — Storage & Dependency Size

Estimates for **what is baked into the Docker image** after a successful build  
(final installed size, **not** peak temp during download/extract).

Numbers are **order-of-magnitude planning figures**, not exact guarantees.  
Real size varies with Debian package updates, Node/Bun versions, and Hermes support wheels.

---

## TL;DR

| | Unpacked (in container) | Compressed (registry / pull) |
|---|---|---|
| **Whole DexShell image** | **~1.8 – 2.8 GB** | **~0.9 – 1.5 GB** |
| **Most likely** | **~2.2 GB** | **~1.1 – 1.3 GB** |

This is **image layer size**, not your Railway **volume** (`/app`).

| Storage | Purpose | Railway (typical) |
|---|---|---|
| **Image** | Dockerfile deps (this doc) | ~2 GB unpacked |
| **`/tmp`** | Scratch: downloads, build caches | ~**10 GB** (free & hobby) |
| **`/app` volume** | Durable user data / Hermes install | **500 MB** free / **5 GB** hobby |

---

## Policy

| Kind | Path | Survives redeploy? |
|---|---|---|
| **Scratch** | `/tmp` | No |
| **Durable** | `/app` (volume) | Yes |

**Rule:** download & build in **temp**; keep only finished tools/config on the **volume** when possible.

```bash
volume-ready    # free-space checker for /app and /tmp
```

- Volume free &lt; ~100 MB → warn  
- Volume free &lt; ~30 MB → critical  
- `/tmp` free &lt; ~500 MB → warn  

---

## Image breakdown (after build, cleaned)

What stays in the final image from `docker/install.sh` + helpers:

| Component | What’s included | Final size (approx) |
|---|---|---|
| **Debian trixie-slim base** | Minimal OS | **70–100 MB** |
| **Apt “light” tools** | bash, curl, wget, git, net tools, htop/btop, tmux, vim/nano, jq, tree, python3, locales, openssh-client, etc. | **180–280 MB** |
| **`ffmpeg` + libs** | Codecs / media (often largest apt chunk) | **150–250 MB** |
| **`build-essential` + pkg-config** | gcc/g++/make, headers | **150–220 MB** |
| **Network / debug tools** | nmap, tcpdump, strace, lsof, etc. | **40–80 MB** |
| **Node.js 22 + npm** | Runtime for npm-based CLIs | **90–150 MB** |
| **Bun** | System binary only (`/usr/local/bin/bun`) | **40–80 MB** |
| **JetBrainsMono Nerd Font** | TTF/OTF set + fontconfig | **15–40 MB** |
| **Hermes support stack** | Isolated Python **3.11** (uv) + venv + wheels: `python-telegram-bot`, `ddgs`, `firecrawl-py`, pip/wheel/setuptools | **200–400 MB** |
| **DexShell app + helpers** | Go binary, entrypoint, `hermes*`, `volume-*` scripts | **10–25 MB** |
| **Locale / fontconfig / misc** | `en_US.UTF-8`, small metadata | **10–30 MB** |

### Subtotal

```text
Base + light apt     ~250–380 MB
ffmpeg               ~150–250 MB
build-essential      ~150–220 MB
Node 22              ~ 90–150 MB
Bun                  ~ 40– 80 MB
Fonts                ~ 15– 40 MB
Hermes support       ~200–400 MB
App / helpers        ~ 10– 25 MB
--------------------------------
TOTAL (unpacked)     ~1.8 – 2.8 GB
```

---

## Packages / components (inventory)

### Apt (runtime image)

`bash`, `ca-certificates`, `curl`, `wget`, `git`, `xz-utils`, `openssh-client`,  
`netcat-openbsd`, `iproute2`, `iputils-ping`, `dnsutils`, `traceroute`, `net-tools`,  
`procps`, `psmisc`, `htop`, `btop`, `tmux`, `vim`, `nano`, `less`, `jq`, `tree`,  
`nmap`, `tcpdump`, `strace`, `lsof`, `zip`, `unzip`, `rsync`,  
`python3`, `python3-pip`, `python3-venv`, `sudo`, `locales`,  
`speedtest-cli`, `dialog`, `ripgrep`, `ffmpeg`,  
`build-essential`, `pkg-config`, `file`, `gnupg`, `fontconfig`,  
optional: `fastfetch`

### Runtimes (baked)

- **Node.js 22** + npm (NodeSource, with distro fallback)
- **Bun** (binary copied to `/usr/local/bin`; install tree discarded)

### Fonts

- JetBrainsMono Nerd Font → `/usr/local/share/fonts/...`
- Default monospace via fontconfig

### Hermes support (image, not full Hermes app)

From `docker/hermes-requirements.txt`, installed into  
`/opt/dexshell/hermes-support` (Python 3.11 via `uv`):

| Package | Role |
|---|---|
| `python-telegram-bot[webhooks]>=22.6,<23` | Telegram adapter |
| `ddgs` | Free DuckDuckGo web search |
| `firecrawl-py` | Firecrawl client (needs API key at runtime) |
| `pip` / `wheel` / `setuptools` | Install tooling |

Full Hermes agent (`hermes-install`) goes to **`/app/.hermes` (volume)**, not the image.

---

## Not left in the final image

| Item | Why |
|---|---|
| `/tmp` zips, extracts, installer roots | `clean_tmp` after each step |
| apt lists / archives | purged |
| npm / uv build caches | purged |
| Bun install root (`/tmp/bun-install`) | only binary kept |
| Full Hermes agent checkout | installed later on **volume** |

---

## Runtime volume `/app` (separate budget)

| What you put on volume | Approx after install |
|---|---|
| Dotfiles / host key / small config | **&lt; 5 MB** |
| Hermes full install (`hermes-install`) | **250–450 MB** |
| One coding CLI (npm/bun global) | **50–200 MB** each |
| Git repos / projects | size of the repo |
| Caches wrongly left on volume | can exhaust free tier |

### Free volume (500 MB)

- OK: configs + small projects + **one** agent, or Hermes alone if careful  
- Tight: Hermes + several global CLIs  
- Avoid: apt caches, large weights, npm/bun caches on `/app`

### Hobby volume (5 GB)

- Hermes + several CLIs + multiple repos is realistic  
- Still use `/tmp` for scratch

### Peak temp during common *runtime* installs

| Action | Temp peak (approx) | Durable on `/app` |
|---|---|---|
| `hermes-install` | 0.5–1.5 GB | 250–450 MB |
| `npm i -g` large CLI | 100–400 MB | 50–200 MB |
| `bun install -g` | 50–300 MB | varies |
| `apt install` | image FS (lost on redeploy) | n/a |

---

## Biggest image weight (diet levers)

1. **`ffmpeg`**  
2. **`build-essential`**  
3. **Hermes support (Python 3.11 + wheels)**  
4. **Node 22**  
5. Remaining apt tools  

Optional diet (rough savings, unpacked):

| Change | Possible savings |
|---|---|
| Drop `build-essential` | ~150–220 MB |
| Drop / optional `ffmpeg` | ~150–250 MB |
| Don’t prebake Hermes wheels in image | ~200–400 MB |
| Combined | often **~400–800 MB** |

---

## How to measure on a running container

```bash
df -h /
df -h /app /tmp

du -sh /usr /opt /var 2>/dev/null
du -sh /opt/dexshell /usr/local /usr/lib 2>/dev/null

dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n | tail -20

volume-ready
```

`dpkg-query` sizes are in **KB**.

---

## Related

- Volume layout & env: `README.md` (Persistence / Environment)
- Checker command: `volume-ready`
- Build install logic: `docker/install.sh`
- Hermes support pins: `docker/hermes-requirements.txt`
