package client

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
)

type OperationType int

const (
	OpFile OperationType = iota
	OpCommand
	OpExpression
)

type FileOptions struct {
	UseTab          bool
	HorizontalSplit bool
	VerticalSplit   bool
	Wait           bool
	FromStdin      bool
}

type Operation struct {
	Type    OperationType
	Content string
	Options FileOptions
}

type RPCRequest struct {
	Type   int         `msgpack:"type"`
	ID     uint64      `msgpack:"id"`
	Method string      `msgpack:"method"`
	Args   []interface{} `msgpack:"args"`
}

type RPCResponse struct {
	Type   int           `msgpack:"type"`
	ID     uint64        `msgpack:"id"`
	Error  interface{}   `msgpack:"error"`
	Result interface{}   `msgpack:"result"`
}

type NvrClient struct {
	conn     net.Conn
	nextID   uint64
	mu       sync.Mutex
}

func NewNvrClient(socketPath string) (*NvrClient, error) {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to socket %s: %v", socketPath, err)
	}

	return &NvrClient{
		conn:   conn,
		nextID: 1,
	}, nil
}

func (c *NvrClient) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

func (c *NvrClient) Call(method string, args ...interface{}) (interface{}, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	id := c.nextID
	c.nextID++

	// Simple messagepack encoding for the request
	req := RPCRequest{
		Type:   0, // Request type
		ID:     id,
		Method: method,
		Args:   args,
	}

	if err := c.sendRequest(req); err != nil {
		return nil, err
	}

	resp, err := c.readResponse()
	if err != nil {
		return nil, err
	}

	if resp.Error != nil {
		return nil, fmt.Errorf("RPC error: %v", resp.Error)
	}

	return resp.Result, nil
}

func (c *NvrClient) ExecuteCommand(command string) error {
	_, err := c.Call("nvim_command", command)
	return err
}

func (c *NvrClient) ExecuteExpression(expr string) (string, error) {
	result, err := c.Call("nvim_eval", expr)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%v", result), nil
}

func (c *NvrClient) sendRequest(req RPCRequest) error {
	// Use JSON encoding for simplicity (in production, use msgpack)
	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %v", err)
	}

	// Write length prefix (4 bytes, big endian)
	length := make([]byte, 4)
	binary.BigEndian.PutUint32(length, uint32(len(data)))

	// Write length + data
	if _, err := c.conn.Write(length); err != nil {
		return fmt.Errorf("failed to write length: %v", err)
	}

	if _, err := c.conn.Write(data); err != nil {
		return fmt.Errorf("failed to write data: %v", err)
	}

	return nil
}

func (c *NvrClient) readResponse() (*RPCResponse, error) {
	// Read length prefix (4 bytes)
	lengthBuf := make([]byte, 4)
	if _, err := c.conn.Read(lengthBuf); err != nil {
		return nil, fmt.Errorf("failed to read length: %v", err)
	}

	length := binary.BigEndian.Uint32(lengthBuf)
	if length > 1024*1024 { // 1MB limit
		return nil, fmt.Errorf("response too large: %d bytes", length)
	}

	// Read response data
	data := make([]byte, length)
	if _, err := c.conn.Read(data); err != nil {
		return nil, fmt.Errorf("failed to read response: %v", err)
	}

	// Parse as JSON
	var resp RPCResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %v", err)
	}

	return &resp, nil
}

func (c *NvrClient) OpenFile(filename string, opts FileOptions) error {
	var command string

	if opts.FromStdin {
		return c.openFromStdin(opts)
	}

	// Escape filename for vim command
	escapedFilename := escapeVimString(filename)

	switch {
	case opts.UseTab:
		command = fmt.Sprintf("tabedit %s", escapedFilename)
	case opts.HorizontalSplit:
		command = fmt.Sprintf("split | edit %s", escapedFilename)
	case opts.VerticalSplit:
		command = fmt.Sprintf("vsplit | edit %s", escapedFilename)
	default:
		command = fmt.Sprintf("edit %s", escapedFilename)
	}

	if err := c.ExecuteCommand(command); err != nil {
		return fmt.Errorf("failed to execute open command: %v", err)
	}

	if opts.Wait {
		// Set up autocommand to wait for file closure
		autocmd := fmt.Sprintf("autocmd BufDelete <buffer> call rpcnotify(0, 'file_closed', '%s')", escapedFilename)
		if err := c.ExecuteCommand(autocmd); err != nil {
			return fmt.Errorf("failed to set up wait autocommand: %v", err)
		}

		// Wait for notification (simplified for now)
		return c.waitForFileClose(escapedFilename)
	}

	return nil
}

func (c *NvrClient) openFromStdin(opts FileOptions) error {
	// Read all content from stdin
	content, err := readAllStdin()
	if err != nil {
		return fmt.Errorf("failed to read from stdin: %v", err)
	}

	// Create appropriate command based on options
	var command string
	switch {
	case opts.UseTab:
		command = "tabnew"
	case opts.HorizontalSplit:
		command = "split"
	case opts.VerticalSplit:
		command = "vsplit"
	default:
		command = "enew"
	}

	if err := c.ExecuteCommand(command); err != nil {
		return fmt.Errorf("failed to create buffer: %v", err)
	}

	// Set buffer content line by line
	lines := strings.Split(content, "\n")
	for i, line := range lines {
		setLineCmd := fmt.Sprintf("call setline(%d, '%s')", i+1, escapeVimString(line))
		if err := c.ExecuteCommand(setLineCmd); err != nil {
			return fmt.Errorf("failed to set line %d: %v", i+1, err)
		}
	}

	return nil
}

func (c *NvrClient) waitForFileClose(filename string) error {
	// Simplified wait mechanism
	// In a full implementation, this would use nvim_buf_attach or similar
	// For now, just wait a short time and assume the operation completes
	_, err := c.ExecuteExpression("sleep 100m")
	return err
}

func readAllStdin() (string, error) {
	stat, _ := os.Stdin.Stat()
	if (stat.Mode() & os.ModeCharDevice) != 0 {
		return "", fmt.Errorf("no input provided on stdin")
	}

	reader := bufio.NewReader(os.Stdin)
	var content strings.Builder

	for {
		line, err := reader.ReadString('\n')
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}
		content.WriteString(line)
	}

	return content.String(), nil
}

func escapeVimString(s string) string {
	// Escape special characters for vim commands
	s = strings.ReplaceAll(s, "'", "''")
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	s = strings.ReplaceAll(s, "\n", "\\n")
	s = strings.ReplaceAll(s, "\t", "\\t")
	return s
}