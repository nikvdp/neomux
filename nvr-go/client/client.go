package client

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/vmihailenco/msgpack/v5"
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
	Type   int           `msgpack:"type"`
	ID     uint64        `msgpack:"id"`
	Method string        `msgpack:"method"`
	Args   []interface{} `msgpack:"args"`
}

type RPCResponse struct {
	Type   int         `msgpack:"type"`
	ID     uint64      `msgpack:"id"`
	Error  interface{} `msgpack:"error"`
	Result interface{} `msgpack:"result"`
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

// Test function to verify connection
func (c *NvrClient) TestConnection() error {
	// Try to get neovim API info
	result, err := c.Call("nvim_get_api_info")
	if err != nil {
		return err
	}
	fmt.Printf("API Info: %v\n", result)
	return nil
}

func (c *NvrClient) sendRequest(req RPCRequest) error {
	// Create msgpack array: [type, msgid, method, args]
	// Type: 0 = request, 1 = response, 2 = notification
	// Msgid: request ID
	// Method: method name
	// Args: arguments array

	msg := []interface{}{req.Type, req.ID, req.Method, req.Args}

	data, err := msgpack.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %v", err)
	}

	// Write the message
	_, err = c.conn.Write(data)
	return err
}

func (c *NvrClient) readResponse() (*RPCResponse, error) {
	// Read the entire response into a buffer first
	buf := make([]byte, 8192)
	n, err := c.conn.Read(buf)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %v", err)
	}

	// Use msgpack decoder on the buffer
	decoder := msgpack.NewDecoder(bytes.NewReader(buf[:n]))

	// Response should be an array: [type, msgid, error, result]
	var respArray []interface{}
	if err := decoder.Decode(&respArray); err != nil {
		return nil, fmt.Errorf("failed to decode response: %v", err)
	}

	if len(respArray) != 4 {
		return nil, fmt.Errorf("invalid response format: expected 4 elements, got %d", len(respArray))
	}

	// Handle type conversions more flexibly
	var typeInt int
	var idInt int

	switch v := respArray[0].(type) {
	case int:
		typeInt = v
	case int8:
		typeInt = int(v)
	case uint8:
		typeInt = int(v)
	default:
		typeInt = 0
	}

	switch v := respArray[1].(type) {
	case int:
		idInt = v
	case int8:
		idInt = int(v)
	case uint8:
		idInt = int(v)
	default:
		idInt = 0
	}

	resp := &RPCResponse{
		Type:   typeInt,
		ID:     uint64(idInt),
		Error:  respArray[2],
		Result: respArray[3],
	}

	return resp, nil
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
		// Like Python nvr: use 'split' command directly
		command = fmt.Sprintf("split %s", escapedFilename)
	case opts.VerticalSplit:
		// Like Python nvr: use 'vsplit' command directly
		command = fmt.Sprintf("vsplit %s", escapedFilename)
	default:
		command = fmt.Sprintf("edit %s", escapedFilename)
	}

	if err := c.ExecuteCommand(command); err != nil {
		return fmt.Errorf("failed to execute open command: %v", err)
	}

	// Like Python nvr: balance windows after splits
	if opts.HorizontalSplit || opts.VerticalSplit {
		if err := c.ExecuteCommand("wincmd ="); err != nil {
			return fmt.Errorf("failed to balance windows: %v", err)
		}
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
	// Set up autocommand to wait for file closure
	autocmd := fmt.Sprintf("autocmd BufDelete <buffer> call rpcnotify(0, 'file_closed', '%s')", filename)
	if err := c.ExecuteCommand(autocmd); err != nil {
		return fmt.Errorf("failed to set up wait autocommand: %v", err)
	}

	// Wait for notification by listening for RPC notifications
	return c.waitForNotification("file_closed")
}

func (c *NvrClient) waitForNotification(expectedMsg string) error {
	// Simple notification listener - wait for the expected notification
	// This is a simplified version that checks for notifications periodically
	for i := 0; i < 100; i++ { // Timeout after ~10 seconds
		// Try to read a notification
		c.conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))

		// Check if there's data to read
		buf := make([]byte, 1024)
		n, err := c.conn.Read(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue // No data yet, try again
			}
			// Other error, break
			break
		}

		if n > 0 {
			// Try to decode as notification
			decoder := msgpack.NewDecoder(bytes.NewReader(buf[:n]))
			var notification []interface{}
			if decodeErr := decoder.Decode(&notification); decodeErr == nil {
				if len(notification) >= 2 {
					if msg, ok := notification[0].(string); ok && msg == expectedMsg {
						return nil // Got the expected notification
					}
				}
			}
		}
	}

	return fmt.Errorf("timeout waiting for notification: %s", expectedMsg)
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