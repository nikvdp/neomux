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

type RPCNotification struct {
	Type   int           `msgpack:"type"`
	Method string        `msgpack:"method"`
	Args   []interface{} `msgpack:"args"`
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
	// Keep reading until we get a response (type 1), skipping notifications (type 2)
	for {
		// Read the entire message into a buffer first
		buf := make([]byte, 8192)
		n, err := c.conn.Read(buf)
		if err != nil {
			return nil, fmt.Errorf("failed to read response: %v", err)
		}

		// Use msgpack decoder on the buffer
		decoder := msgpack.NewDecoder(bytes.NewReader(buf[:n]))

		// First, check what type of message this is
		var msgArray []interface{}
		if err := decoder.Decode(&msgArray); err != nil {
			return nil, fmt.Errorf("failed to decode message: %v", err)
		}

		// Get the message type
		var msgType int
		if len(msgArray) > 0 {
			switch v := msgArray[0].(type) {
			case int:
				msgType = v
			case int8:
				msgType = int(v)
			case uint8:
				msgType = int(v)
			default:
				msgType = -1
			}
		}

		// Type 2 is notification, skip it
		if msgType == 2 {
			continue
		}

		// Type 1 is response, process it
		if msgType == 1 && len(msgArray) == 4 {
			// Handle type conversions for response
			var idInt int
			switch v := msgArray[1].(type) {
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
				Type:   msgType,
				ID:     uint64(idInt),
				Error:  msgArray[2],
				Result: msgArray[3],
			}

			return resp, nil
		}

		// Unknown message type
		return nil, fmt.Errorf("unexpected message type %d with %d elements", msgType, len(msgArray))
	}
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
		// For --remote-wait, we need to wait for the buffer to be closed
		// But we shouldn't interfere with normal buffer operations
		return c.waitForFileClose(filename)
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
	// Get the current channel ID for notifications
	channelID, err := c.getChannelID()
	if err != nil {
		return fmt.Errorf("failed to get channel ID: %v", err)
	}

	// Get current buffer for buffer-specific autocommands
	bufID, err := c.getCurrentBuffer()
	if err != nil {
		return fmt.Errorf("failed to get current buffer: %v", err)
	}

	// Set up autocommands exactly like Python nvr does
	// Python uses <buffer> without ID, which refers to the current buffer
	setupCmds := []string{
		"augroup nvr",
		fmt.Sprintf("autocmd BufDelete <buffer> silent! call rpcnotify(%d, \"BufDelete\")", channelID),
		fmt.Sprintf("autocmd VimLeave * if exists(\"v:exiting\") && v:exiting > 0 | silent! call rpcnotify(%d, \"Exit\", v:exiting) | endif", channelID),
		"augroup END",
	}

	for _, cmd := range setupCmds {
		if err := c.ExecuteCommand(cmd); err != nil {
			return fmt.Errorf("failed to setup autocommands: %v", err)
		}
	}

	// Manage buffer variables like Python nvr does
	// Python: bvars['nvr'] = [chanid] or [chanid] + bvars['nvr']
	if err := c.manageBufVars(bufID, channelID); err != nil {
		return fmt.Errorf("failed to manage buffer variables: %v", err)
	}

	// Wait for notifications
	return c.waitForNotifications()
}

func (c *NvrClient) getCurrentBuffer() (int, error) {
	result, err := c.Call("nvim_get_current_buf")
	if err != nil {
		return 0, err
	}

	// Handle different return types
	switch v := result.(type) {
	case int:
		return v, nil
	case uint64:
		return int(v), nil
	default:
		return 0, fmt.Errorf("invalid buffer ID type")
	}
}

func (c *NvrClient) manageBufVars(bufID int, channelID int) error {
	// Get current buffer variables
	result, err := c.Call("nvim_buf_get_var", bufID, "nvr")

	var existingChannels []interface{}
	if err != nil {
		// Variable doesn't exist yet, that's ok
		existingChannels = []interface{}{}
	} else {
		// Variable exists, get the list
		switch v := result.(type) {
		case []interface{}:
			existingChannels = v
		default:
			// If it's not a list, start fresh
			existingChannels = []interface{}{}
		}
	}

	// Check if our channel ID is already in the list
	channelExists := false
	for _, ch := range existingChannels {
		switch v := ch.(type) {
		case int:
			if v == channelID {
				channelExists = true
				break
			}
		case int64:
			if int(v) == channelID {
				channelExists = true
				break
			}
		case uint64:
			if int(v) == channelID {
				channelExists = true
				break
			}
		}
	}

	// Add our channel ID at the beginning if it doesn't exist
	if !channelExists {
		newChannels := []interface{}{channelID}
		newChannels = append(newChannels, existingChannels...)

		// Set the buffer variable
		_, err = c.Call("nvim_buf_set_var", bufID, "nvr", newChannels)
		if err != nil {
			return fmt.Errorf("failed to set buffer variable: %v", err)
		}
	}

	return nil
}

func (c *NvrClient) getChannelID() (int, error) {
	// Get the current channel ID (Python nvr uses self.server.channel_id)
	// In msgpack-rpc, we need to call nvim_get_api_info and extract channel_id
	result, err := c.Call("nvim_get_api_info")
	if err != nil {
		return 0, err
	}

	// nvim_get_api_info returns [channel_id, api_metadata]
	if info, ok := result.([]interface{}); ok && len(info) >= 1 {
		switch v := info[0].(type) {
		case int:
			return v, nil
		case int64:
			return int(v), nil
		case uint64:
			return int(v), nil
		default:
			return 0, fmt.Errorf("unexpected channel ID type: %T", v)
		}
	}

	return 0, fmt.Errorf("failed to parse channel ID from api_info")
}

func (c *NvrClient) waitForNotifications() error {
	// Set a timeout to prevent hanging indefinitely
	timeout := time.After(5 * time.Minute)

	for {
		select {
		case <-timeout:
			return fmt.Errorf("timeout waiting for buffer to close")
		default:
			// Try to read a notification with a short timeout
			c.conn.SetReadDeadline(time.Now().Add(100 * time.Millisecond))

			// Read notification
			notification, err := c.readNotification()
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					// No notification available, check if we should continue
					continue
				}
				// Other error, break
				break
			}

			// Handle notification
			if notification != nil {
				switch notification.Method {
				case "BufDelete":
					// Buffer was deleted, we're done
					return nil
				case "Exit":
					// Neovim is exiting
					return nil
				}
			}
		}
	}

	return nil
}

func (c *NvrClient) readNotification() (*RPCNotification, error) {
	// Read the entire message into a buffer first
	buf := make([]byte, 8192)
	n, err := c.conn.Read(buf)
	if err != nil {
		return nil, err
	}

	// Use msgpack decoder on the buffer
	decoder := msgpack.NewDecoder(bytes.NewReader(buf[:n]))

	// Notification should be an array: [type, method, args]
	var notifArray []interface{}
	if err := decoder.Decode(&notifArray); err != nil {
		return nil, fmt.Errorf("failed to decode notification: %v", err)
	}

	if len(notifArray) != 3 {
		return nil, fmt.Errorf("invalid notification format: expected 3 elements, got %d", len(notifArray))
	}

	// Handle type conversions
	var typeInt int
	switch v := notifArray[0].(type) {
	case int:
		typeInt = v
	case int8:
		typeInt = int(v)
	case uint8:
		typeInt = int(v)
	default:
		typeInt = 0
	}

	// Only process notifications (type 2)
	if typeInt != 2 {
		return nil, nil
	}

	method, ok := notifArray[1].(string)
	if !ok {
		return nil, fmt.Errorf("invalid notification method")
	}

	args, ok := notifArray[2].([]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid notification args")
	}

	return &RPCNotification{
		Type:   typeInt,
		Method: method,
		Args:   args,
	}, nil
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