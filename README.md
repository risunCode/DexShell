# DexShell

DEXSHELL - Simple Remote Shell Tool

DexShell is a simple remote shell tool for Docker containers with reverse shell, bind shell, and SSH server capabilities.

## Features

- **Reverse Shell** - Connect to a remote listener
- **Bind Shell** - Listen for incoming connections  
- **SSH Server** - Full SSH server with password authentication
- **Docker Optimized** - Built for container environments
- **Rich Toolset** - Includes fastfetch, htop, btop, tmux, and more

## Usage

### Local Build

```bash
go build -o dexshell .
./dexshell reverse 10.0.0.5:4444
./dexshell bind 4444
./dexshell ssh
```

### Docker

```bash
docker build -t dexshell .
docker run -p 4444:4444 dexshell
docker run -e SSH_PASSWORD=mypassword -p 2222:2222 dexshell ./dexshell ssh
```

### Environment Variables (SSH)

- `SSH_PASSWORD` - SSH login password (default: changeme)
- `SSH_PORT` - SSH port (default: 2222)
- `SSH_USER` - SSH username (default: root)

## Included Tools

- **System Info:** fastfetch, htop, btop, glances
- **Terminal:** tmux, vim, nano, bat, eza, ripgrep, fzf, tree
- **Network:** nmap, tcpdump, netcat, curl, wget
- **Utilities:** jq, strace, lsof, git, python3

## License

MIT
