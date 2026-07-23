// DexShell - Simple remote shell tool untuk Docker containers.
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"

	gossh "golang.org/x/crypto/ssh"
)

const (
	defaultHome    = "/app"
	hostKeyRelPath = ".dexshell/ssh_host_rsa_key"
)

func main() {
	// Default mode: SSH (deploy target). Other modes remain for local use.
	mode := "ssh"
	if len(os.Args) >= 2 {
		mode = os.Args[1]
	}

	switch mode {
	case "reverse":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: dexshell reverse <host:port>\n")
			os.Exit(1)
		}
		if err := reverseShell(os.Args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "reverse shell error: %v\n", err)
			os.Exit(1)
		}

	case "bind":
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Usage: dexshell bind <port>\n")
			os.Exit(1)
		}
		if err := bindShell(os.Args[2]); err != nil {
			fmt.Fprintf(os.Stderr, "bind shell error: %v\n", err)
			os.Exit(1)
		}

	case "ssh":
		if err := sshServer(); err != nil {
			fmt.Fprintf(os.Stderr, "ssh server error: %v\n", err)
			os.Exit(1)
		}

	default:
		printUsage()
		os.Exit(1)
	}
}

func reverseShell(addr string) error {
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		return fmt.Errorf("dial %s: %w", addr, err)
	}
	defer conn.Close()

	fmt.Fprintf(os.Stderr, "[*] connected to %s\n", addr)

	cmd := shellCommand()
	cmd.Stdin = conn
	cmd.Stdout = conn
	cmd.Stderr = conn

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start shell: %w", err)
	}

	return cmd.Wait()
}

func bindShell(port string) error {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		return fmt.Errorf("listen :%s: %w", port, err)
	}
	defer ln.Close()

	fmt.Fprintf(os.Stderr, "[*] bind shell listening on 0.0.0.0:%s\n", port)

	conn, err := ln.Accept()
	if err != nil {
		return fmt.Errorf("accept: %w", err)
	}
	defer conn.Close()

	fmt.Fprintf(os.Stderr, "[*] connection from %s\n", conn.RemoteAddr())

	cmd := shellCommand()
	cmd.Stdin = conn
	cmd.Stdout = conn
	cmd.Stderr = conn

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start shell: %w", err)
	}

	return cmd.Wait()
}

func sshServer() error {
	password := getEnv("SSH_PASSWORD", "risuncode")
	// Prefer explicit SSH_PORT, then platform PORT, then 4444 (public TCP).
	port := getEnv("SSH_PORT", getEnv("PORT", "4444"))
	user := getEnv("SSH_USER", "root")
	home := getEnv("HOME", defaultHome)

	if err := os.MkdirAll(home, 0o755); err != nil {
		return fmt.Errorf("prepare home %s: %w", home, err)
	}
	// Keep process home on the volume so shell history/files persist.
	_ = os.Setenv("HOME", home)

	key, err := loadOrCreateHostKey(filepath.Join(home, hostKeyRelPath))
	if err != nil {
		return fmt.Errorf("host key: %w", err)
	}

	config := &gossh.ServerConfig{
		PasswordCallback: func(c gossh.ConnMetadata, pass []byte) (*gossh.Permissions, error) {
			if c.User() == user && string(pass) == password {
				return nil, nil
			}
			return nil, fmt.Errorf("authentication failed")
		},
	}
	config.AddHostKey(key)

	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		return fmt.Errorf("listen :%s: %w", port, err)
	}
	defer ln.Close()

	fmt.Fprintf(os.Stderr, "[*] SSH server listening on 0.0.0.0:%s\n", port)
	fmt.Fprintf(os.Stderr, "[*] User: %s\n", user)
	fmt.Fprintf(os.Stderr, "[*] Home (volume): %s\n", home)
	fmt.Fprintf(os.Stderr, "[*] Connect: ssh -p %s %s@<host>\n", port, user)

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept error: %v", err)
			continue
		}
		go handleSSHConnection(conn, config)
	}
}

func handleSSHConnection(conn net.Conn, config *gossh.ServerConfig) {
	defer conn.Close()

	sshConn, chans, reqs, err := gossh.NewServerConn(conn, config)
	if err != nil {
		log.Printf("handshake error: %v", err)
		return
	}
	defer sshConn.Close()

	log.Printf("connection from %s as %s", sshConn.RemoteAddr(), sshConn.User())
	go gossh.DiscardRequests(reqs)

	for newChannel := range chans {
		if newChannel.ChannelType() != "session" {
			newChannel.Reject(gossh.UnknownChannelType, "unknown channel type")
			continue
		}

		channel, requests, err := newChannel.Accept()
		if err != nil {
			log.Printf("accept channel error: %v", err)
			continue
		}

		go handleSSHSession(channel, requests)
	}
}

func handleSSHSession(channel gossh.Channel, requests <-chan *gossh.Request) {
	defer channel.Close()

	cmd := shellCommand()
	ready := make(chan struct{})
	var execPayload string

	go func() {
		for req := range requests {
			switch req.Type {
			case "shell":
				if req.WantReply {
					req.Reply(true, nil)
				}
				close(ready)
				return
			case "exec":
				// payload is a length-prefixed string in SSH, but x/crypto exposes raw bytes
				// after the uint32 length for standard clients; keep simple: run interactive shell.
				if req.WantReply {
					req.Reply(true, nil)
				}
				if len(req.Payload) >= 4 {
					// skip 4-byte length prefix when present
					n := int(req.Payload[0])<<24 | int(req.Payload[1])<<16 | int(req.Payload[2])<<8 | int(req.Payload[3])
					if n > 0 && 4+n <= len(req.Payload) {
						execPayload = string(req.Payload[4 : 4+n])
					} else {
						execPayload = string(req.Payload)
					}
				}
				close(ready)
				return
			case "pty-req", "env", "window-change":
				if req.WantReply {
					req.Reply(true, nil)
				}
			default:
				if req.WantReply {
					req.Reply(false, nil)
				}
			}
		}
	}()

	<-ready

	if execPayload != "" {
		home := getEnv("HOME", defaultHome)
		cmd = exec.Command("/bin/sh", "-lc", execPayload)
		cmd.Dir = home
		cmd.Env = shellEnv(home)
	}

	cmd.Stdin = channel
	cmd.Stdout = channel
	cmd.Stderr = channel

	if err := cmd.Start(); err != nil {
		log.Printf("start shell error: %v", err)
		return
	}

	_ = cmd.Wait()
}

func loadOrCreateHostKey(path string) (gossh.Signer, error) {
	if data, err := os.ReadFile(path); err == nil {
		signer, err := gossh.ParsePrivateKey(data)
		if err != nil {
			return nil, fmt.Errorf("parse host key %s: %w", path, err)
		}
		log.Printf("loaded host key from %s", path)
		return signer, nil
	}

	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}

	block := &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
	}
	pemBytes := pem.EncodeToMemory(block)

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, pemBytes, 0o600); err != nil {
		return nil, fmt.Errorf("write host key %s: %w", path, err)
	}
	log.Printf("generated host key at %s", path)

	return gossh.ParsePrivateKey(pemBytes)
}

func shellCommand() *exec.Cmd {
	home := getEnv("HOME", defaultHome)
	_ = os.MkdirAll(home, 0o755)

	var cmd *exec.Cmd
	for _, sh := range []string{"/bin/bash", "/bin/sh", "/bin/ash"} {
		if path, err := exec.LookPath(sh); err == nil {
			// login-ish interactive shell so rc files under HOME are picked up
			if filepath.Base(path) == "bash" {
				cmd = exec.Command(path, "-il")
			} else {
				cmd = exec.Command(path, "-i")
			}
			break
		}
	}
	if cmd == nil {
		cmd = exec.Command("/bin/sh", "-i")
	}

	cmd.Dir = home
	cmd.Env = shellEnv(home)
	return cmd
}

func shellEnv(home string) []string {
	env := os.Environ()
	env = append(env,
		"HOME="+home,
		"PWD="+home,
		"TERM=xterm-256color",
	)
	return env
}

func getEnv(key, defaultVal string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultVal
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `DexShell - Simple remote shell tool untuk Docker containers

Penggunaan:
  dexshell                Jalankan SSH server (default)
  dexshell ssh            Jalankan SSH server
  dexshell reverse <host:port>
  dexshell bind <port>

Environment:
  SSH_PASSWORD   Password login (default: changeme)
  SSH_PORT       Port SSH (default: PORT atau 4444)
  SSH_USER       Username (default: root)
  HOME           Home/session dir (default: /app, mount volume di sini)

Contoh:
  dexshell
  ssh -p 4444 root@vps.sunwa.web.id
`)
}
