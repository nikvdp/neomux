package client

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
)

func FindNeovimSocket() (string, error) {
	// Check NVIM_LISTEN_ADDRESS environment variable
	if socket := os.Getenv("NVIM_LISTEN_ADDRESS"); socket != "" {
		if testSocketConnection(socket) {
			return socket, nil
		}
	}

	// Check NVIM environment variable and derive socket path
	if nvim := os.Getenv("NVIM"); nvim != "" {
		socket := filepath.Join("/tmp", nvim+"0")
		if _, err := os.Stat(socket); err == nil {
			if testSocketConnection(socket) {
				return socket, nil
			}
		}
	}

	// Search for active sockets in /tmp/nvim*/0 pattern
	matches, err := filepath.Glob("/tmp/nvim*/0")
	if err != nil {
		return "", fmt.Errorf("error searching for Neovim sockets: %v", err)
	}

	for _, socket := range matches {
		if testSocketConnection(socket) {
			return socket, nil
		}
	}

	return "", fmt.Errorf("no active Neovim instance found. Is Neovim running with RPC enabled?")
}

func testSocketConnection(socketPath string) bool {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}