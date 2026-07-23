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
	"sync"

	"github.com/creack/pty"
	"github.com/joho/godotenv"
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

	if err := os.MkdirAll(home, 0o755); err != nil {
		return err
	}
	_ = os.Setenv("HOME", home)

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

	log.Printf("SSH on :%s user=%s home=%s", port, user, home)

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
		if nch.ChannelType() != "session" {
			nch.Reject(gossh.UnknownChannelType, "only session")
			continue
		}
		ch, requests, err := nch.Accept()
		if err != nil {
			continue
		}
		go handleSession(ch, requests)
	}
}

func handleSession(ch gossh.Channel, requests <-chan *gossh.Request) {
	defer ch.Close()

	var (
		ptyReq  *ptyRequest
		wantTTY bool
		once    sync.Once
		start   = make(chan string, 1) // "" = shell, else exec command
	)

	go func() {
		for req := range requests {
			switch req.Type {
			case "pty-req":
				wantTTY = true
				pr, err := parsePtyReq(req.Payload)
				if err == nil {
					ptyReq = &pr
				}
				if req.WantReply {
					_ = req.Reply(true, nil)
				}
			case "window-change":
				if ptyReq != nil && len(req.Payload) >= 8 {
					w := binary.BigEndian.Uint32(req.Payload[0:4])
					h := binary.BigEndian.Uint32(req.Payload[4:8])
					ptyReq.cols, ptyReq.rows = w, h
					// resize applied after pty starts via channel below if needed
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
				once.Do(func() { start <- "" })
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
				once.Do(func() { start <- cmd })
			default:
				if req.WantReply {
					_ = req.Reply(false, nil)
				}
			}
		}
		once.Do(func() { start <- "" })
	}()

	cmdStr := <-start
	runSession(ch, cmdStr, wantTTY, ptyReq)
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
		pr.term = "xterm"
	}
	if pr.cols == 0 {
		pr.cols = 80
	}
	if pr.rows == 0 {
		pr.rows = 24
	}
	return pr, nil
}

func runSession(ch gossh.Channel, cmdStr string, wantTTY bool, pr *ptyRequest) {
	home := envOr("HOME", "/app")
	_ = os.MkdirAll(home, 0o755)

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

		if pr != nil {
			_ = setWinsize(ptmx, pr.cols, pr.rows)
		}

		// keep resizing if client sends window-change — best-effort via process group
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

func shellEnv(home, term string) []string {
	if term == "" {
		term = "xterm-256color"
	}
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
