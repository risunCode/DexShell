// DexShell - simple SSH shell for containers.
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/binary"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"github.com/creack/pty"
	"github.com/joho/godotenv"
	"github.com/pkg/sftp"
	gossh "golang.org/x/crypto/ssh"
)

func main() {
	loadEnv()

	mode := "ssh"
	if len(os.Args) >= 2 {
		mode = os.Args[1]
	}

	switch mode {
	case "ssh":
		if err := sshServer(); err != nil {
			log.Fatalf("ssh: %v", err)
		}
	case "bind":
		if len(os.Args) < 3 {
			log.Fatal("usage: dexshell bind <port>")
		}
		if err := bindShell(os.Args[2]); err != nil {
			log.Fatalf("bind: %v", err)
		}
	case "reverse":
		if len(os.Args) < 3 {
			log.Fatal("usage: dexshell reverse <host:port>")
		}
		if err := reverseShell(os.Args[2]); err != nil {
			log.Fatalf("reverse: %v", err)
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: dexshell [ssh|bind <port>|reverse <host:port>]")
		os.Exit(1)
	}
}

// loadEnv loads .env without overriding real environment variables.
// Order: process env (Railway/etc) wins, then .env files fill missing keys.
func loadEnv() {
	paths := []string{
		".env",
		"/app/.env",
		filepath.Join(envOr("HOME", "/app"), ".env"),
	}
	for _, p := range paths {
		_ = godotenv.Load(p)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func requireEnv(key string) (string, error) {
	v := os.Getenv(key)
	if v == "" {
		return "", fmt.Errorf("%s is required (set in Railway env or /app/.env)", key)
	}
	return v, nil
}

func reverseShell(addr string) error {
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	return pipeShell(conn)
}

func bindShell(port string) error {
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		return err
	}
	defer ln.Close()
	log.Printf("bind listening on :%s", port)
	conn, err := ln.Accept()
	if err != nil {
		return err
	}
	defer conn.Close()
	return pipeShell(conn)
}

func pipeShell(rw io.ReadWriter) error {
	cmd := shellCmd("")
	ptmx, err := pty.Start(cmd)
	if err != nil {
		// fallback without pty
		cmd = shellCmd("")
		cmd.Stdin = rw.(io.Reader)
		cmd.Stdout = rw.(io.Writer)
		cmd.Stderr = rw.(io.Writer)
		return cmd.Run()
	}
	defer ptmx.Close()

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, _ = io.Copy(ptmx, rw)
	}()
	go func() {
		defer wg.Done()
		_, _ = io.Copy(rw, ptmx)
	}()
	err = cmd.Wait()
	wg.Wait()
	return err
}

func sshServer() error {
	password, err := requireEnv("SSH_PASSWORD")
	if err != nil {
		return err
	}
	user := envOr("SSH_USER", "root")
	port := envOr("SSH_PORT", envOr("PORT", "4444"))
	home := envOr("HOME", "/app")

	if err := ensureHomeLayout(home); err != nil {
		return err
	}
	applyPersistentEnv(home)

	key, err := loadOrCreateHostKey(filepath.Join(home, ".dexshell", "ssh_host_rsa_key"))
	if err != nil {
		return err
	}

	cfg := &gossh.ServerConfig{
		PasswordCallback: func(c gossh.ConnMetadata, pass []byte) (*gossh.Permissions, error) {
			if c.User() == user && string(pass) == password {
				return nil, nil
			}
			return nil, fmt.Errorf("auth failed")
		},
	}
	cfg.AddHostKey(key)

	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		return err
	}
	defer ln.Close()

	log.Printf("SSH+SFTP on :%s user=%s home=%s", port, user, home)

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept: %v", err)
			continue
		}
		go handleSSH(conn, cfg)
	}
}

func handleSSH(conn net.Conn, cfg *gossh.ServerConfig) {
	defer conn.Close()

	sconn, chans, reqs, err := gossh.NewServerConn(conn, cfg)
	if err != nil {
		log.Printf("handshake: %v", err)
		return
	}
	defer sconn.Close()
	log.Printf("login %s from %s", sconn.User(), sconn.RemoteAddr())
	go gossh.DiscardRequests(reqs)

	for nch := range chans {
		switch nch.ChannelType() {
		case "session":
			ch, requests, err := nch.Accept()
			if err != nil {
				continue
			}
			go handleSession(ch, requests)
		default:
			nch.Reject(gossh.UnknownChannelType, "only session")
		}
	}
}

func handleSession(ch gossh.Channel, requests <-chan *gossh.Request) {
	defer ch.Close()

	var (
		ptyReq  *ptyRequest
		wantTTY bool
		once    sync.Once
		// kind: "shell" | "exec" | "sftp"
		start  = make(chan sessionStart, 1)
		resize = make(chan pty.Winsize, 4)
	)

	go func() {
		for req := range requests {
			switch req.Type {
			case "pty-req":
				wantTTY = true
				pr, err := parsePtyReq(req.Payload)
				if err == nil {
					normalizePtySize(&pr)
					ptyReq = &pr
				}
				if req.WantReply {
					_ = req.Reply(true, nil)
				}
			case "window-change":
				if len(req.Payload) >= 8 {
					w := binary.BigEndian.Uint32(req.Payload[0:4])
					h := binary.BigEndian.Uint32(req.Payload[4:8])
					if w == 0 {
						w = 80
					}
					if h == 0 {
						h = 24
					}
					if ptyReq != nil {
						ptyReq.cols, ptyReq.rows = w, h
					}
					select {
					case resize <- pty.Winsize{Rows: uint16(h), Cols: uint16(w)}:
					default:
					}
				}
				if req.WantReply {
					_ = req.Reply(true, nil)
				}
			case "env":
				if req.WantReply {
					_ = req.Reply(true, nil)
				}
			case "shell":
				if req.WantReply {
					_ = req.Reply(true, nil)
				}
				once.Do(func() { start <- sessionStart{kind: "shell"} })
			case "exec":
				cmd := ""
				if len(req.Payload) >= 4 {
					n := binary.BigEndian.Uint32(req.Payload[0:4])
					if int(4+n) <= len(req.Payload) {
						cmd = string(req.Payload[4 : 4+n])
					}
				}
				if req.WantReply {
					_ = req.Reply(true, nil)
				}
				once.Do(func() { start <- sessionStart{kind: "exec", cmd: cmd} })
			case "subsystem":
				name := ""
				if len(req.Payload) >= 4 {
					n := binary.BigEndian.Uint32(req.Payload[0:4])
					if int(4+n) <= len(req.Payload) {
						name = string(req.Payload[4 : 4+n])
					}
				}
				if name == "sftp" {
					if req.WantReply {
						_ = req.Reply(true, nil)
					}
					once.Do(func() { start <- sessionStart{kind: "sftp"} })
				} else {
					if req.WantReply {
						_ = req.Reply(false, nil)
					}
				}
			default:
				if req.WantReply {
					_ = req.Reply(false, nil)
				}
			}
		}
		once.Do(func() { start <- sessionStart{kind: "shell"} })
	}()

	st := <-start
	switch st.kind {
	case "sftp":
		runSFTP(ch)
	case "exec":
		runSession(ch, st.cmd, wantTTY, ptyReq, resize)
	default:
		runSession(ch, "", wantTTY, ptyReq, resize)
	}
}

type sessionStart struct {
	kind string
	cmd  string
}

func runSFTP(ch gossh.Channel) {
	home := envOr("HOME", "/app")
	_ = os.MkdirAll(home, 0o755)

	// Root SFTP at HOME (/app volume) so uploads land on persistent storage.
	server, err := sftp.NewServer(
		ch,
		sftp.WithServerWorkingDirectory(home),
	)
	if err != nil {
		log.Printf("sftp server: %v", err)
		return
	}
	defer server.Close()

	log.Printf("sftp session root=%s", home)
	if err := server.Serve(); err != nil && err != io.EOF {
		log.Printf("sftp serve: %v", err)
	}
}

type ptyRequest struct {
	term string
	cols uint32
	rows uint32
}

func parsePtyReq(b []byte) (ptyRequest, error) {
	var pr ptyRequest
	if len(b) < 4 {
		return pr, fmt.Errorf("short pty-req")
	}
	n := binary.BigEndian.Uint32(b[0:4])
	if int(4+n) > len(b) {
		return pr, fmt.Errorf("bad term")
	}
	pr.term = string(b[4 : 4+n])
	rest := b[4+n:]
	if len(rest) < 16 {
		return pr, fmt.Errorf("short size")
	}
	pr.cols = binary.BigEndian.Uint32(rest[0:4])
	pr.rows = binary.BigEndian.Uint32(rest[4:8])
	if pr.term == "" {
		pr.term = "xterm-256color"
	}
	normalizePtySize(&pr)
	return pr, nil
}

// btop and many TUIs need at least 80x24. Some clients (or tiny windows)
// advertise smaller sizes and then apps refuse to start.
func normalizePtySize(pr *ptyRequest) {
	if pr == nil {
		return
	}
	if pr.cols < 80 {
		pr.cols = 80
	}
	if pr.rows < 24 {
		pr.rows = 24
	}
}

func runSession(ch gossh.Channel, cmdStr string, wantTTY bool, pr *ptyRequest, resize <-chan pty.Winsize) {
	home := envOr("HOME", "/app")
	_ = ensureHomeLayout(home)

	if pr == nil {
		pr = &ptyRequest{term: "xterm-256color", cols: 80, rows: 24}
	} else {
		normalizePtySize(pr)
	}

	var cmd *exec.Cmd
	if cmdStr != "" {
		cmd = exec.Command("/bin/bash", "-lc", cmdStr)
	} else {
		cmd = shellCmd(termFrom(pr))
	}
	cmd.Dir = home
	cmd.Env = shellEnv(home, termFrom(pr))

	// PuTTY and normal SSH clients need a real PTY.
	if wantTTY || cmdStr == "" {
		ptmx, err := pty.Start(cmd)
		if err != nil {
			log.Printf("pty start: %v — fallback plain", err)
			cmd.Stdin = ch
			cmd.Stdout = ch
			cmd.Stderr = ch
			_ = cmd.Run()
			return
		}
		defer func() {
			_ = ptmx.Close()
			_, _ = cmd.Process.Wait()
		}()

		_ = setWinsize(ptmx, pr.cols, pr.rows)

		// Apply live window-change events from the SSH client.
		go func() {
			for ws := range resize {
				if ws.Cols < 80 {
					ws.Cols = 80
				}
				if ws.Rows < 24 {
					ws.Rows = 24
				}
				_ = pty.Setsize(ptmx, &ws)
			}
		}()

		go func() {
			_, _ = io.Copy(ptmx, ch)
			_ = ptmx.Close()
		}()
		_, _ = io.Copy(ch, ptmx)
		_ = cmd.Wait()
		return
	}

	cmd.Stdin = ch
	cmd.Stdout = ch
	cmd.Stderr = ch
	_ = cmd.Run()
}

func shellCmd(term string) *exec.Cmd {
	home := envOr("HOME", "/app")
	cmd := exec.Command("/bin/bash", "-il")
	if _, err := exec.LookPath("/bin/bash"); err != nil {
		cmd = exec.Command("/bin/sh", "-i")
	}
	cmd.Dir = home
	cmd.Env = shellEnv(home, term)
	return cmd
}

func termFrom(pr *ptyRequest) string {
	if pr != nil && pr.term != "" {
		return pr.term
	}
	return envOr("TERM", "xterm-256color")
}

func ensureHomeLayout(home string) error {
	dirs := []string{
		home,
		filepath.Join(home, "bin"),
		filepath.Join(home, ".local", "bin"),
		filepath.Join(home, ".config"),
		filepath.Join(home, ".cache"),
		filepath.Join(home, ".local", "share"),
		filepath.Join(home, ".local", "state"),
		filepath.Join(home, ".dexshell"),
		filepath.Join(home, "projects"),
		filepath.Join(home, ".npm-global"),
		filepath.Join(home, ".bun"),
		filepath.Join(home, ".hermes"),
		filepath.Join(home, ".cargo", "bin"),
		filepath.Join(home, "go", "bin"),
	}
	for _, d := range dirs {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}
	return nil
}

func applyPersistentEnv(home string) {
	_ = os.Setenv("HOME", home)
	_ = os.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	_ = os.Setenv("XDG_CACHE_HOME", filepath.Join(home, ".cache"))
	_ = os.Setenv("XDG_DATA_HOME", filepath.Join(home, ".local", "share"))
	_ = os.Setenv("XDG_STATE_HOME", filepath.Join(home, ".local", "state"))
	_ = os.Setenv("HERMES_HOME", filepath.Join(home, ".hermes"))
	_ = os.Setenv("BUN_INSTALL", filepath.Join(home, ".bun"))
	_ = os.Setenv("npm_config_prefix", filepath.Join(home, ".npm-global"))
	_ = os.Setenv("CARGO_HOME", filepath.Join(home, ".cargo"))
	_ = os.Setenv("RUSTUP_HOME", filepath.Join(home, ".rustup"))
	_ = os.Setenv("GOPATH", filepath.Join(home, "go"))
	_ = os.Setenv("GOCACHE", filepath.Join(home, ".cache", "go-build"))
	_ = os.Setenv("PYTHONUSERBASE", filepath.Join(home, ".local"))
	_ = os.Setenv("PIP_USER", "1")
	_ = os.Setenv("UV_LINK_MODE", "copy")
	_ = os.Setenv("NPM_CONFIG_CACHE", filepath.Join(home, ".cache", "npm"))

	pathPrefix := strings.Join([]string{
		filepath.Join(home, "bin"),
		filepath.Join(home, ".local", "bin"),
		filepath.Join(home, ".bun", "bin"),
		filepath.Join(home, ".npm-global", "bin"),
		filepath.Join(home, ".cargo", "bin"),
		filepath.Join(home, "go", "bin"),
	}, string(os.PathListSeparator))
	cur := os.Getenv("PATH")
	if cur == "" {
		_ = os.Setenv("PATH", pathPrefix)
		return
	}
	_ = os.Setenv("PATH", pathPrefix+string(os.PathListSeparator)+cur)
}

func shellEnv(home, term string) []string {
	if term == "" {
		term = "xterm-256color"
	}
	_ = ensureHomeLayout(home)
	applyPersistentEnv(home)

	env := os.Environ()
	env = append(env,
		"HOME="+home,
		"PWD="+home,
		"TERM="+term,
	)
	return env
}

func setWinsize(f *os.File, cols, rows uint32) error {
	return pty.Setsize(f, &pty.Winsize{
		Rows: uint16(rows),
		Cols: uint16(cols),
	})
}

func loadOrCreateHostKey(path string) (gossh.Signer, error) {
	if b, err := os.ReadFile(path); err == nil {
		return gossh.ParsePrivateKey(b)
	}

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, pemBytes, 0o600); err != nil {
		return nil, err
	}
	log.Printf("host key created: %s", path)
	return gossh.ParsePrivateKey(pemBytes)
}
