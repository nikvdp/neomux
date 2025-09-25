package client

import (
	"encoding/binary"
	"fmt"
	"net"
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

func (c *NvrClient) sendRequest(req RPCRequest) error {
	// For now, we'll implement a simple text-based protocol
	// In a real implementation, we'd use proper msgpack encoding
	msg := fmt.Sprintf("%d %s %v", req.ID, req.Method, req.Args)
	_, err := c.conn.Write([]byte(msg + "\n"))
	return err
}

func (c *NvrClient) readResponse() (*RPCResponse, error) {
	// Simple response reading for now
	buf := make([]byte, 1024)
	n, err := c.conn.Read(buf)
	if err != nil {
		return nil, err
	}

	// For now, just return a simple response
	return &RPCResponse{
		Type:   1, // Response type
		Result: string(buf[:n-1]), // Remove newline
	}, nil
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

func (c *NvrClient) OpenFile(filename string, opts FileOptions) error {
	var command string

	if opts.FromStdin {
		return c.openFromStdin(opts)
	}

	switch {
	case opts.UseTab:
		command = fmt.Sprintf("tabedit %s", filename)
	case opts.HorizontalSplit:
		command = fmt.Sprintf("split | edit %s", filename)
	case opts.VerticalSplit:
		command = fmt.Sprintf("vsplit | edit %s", filename)
	default:
		command = fmt.Sprintf("edit %s", filename)
	}

	if opts.Wait {
		command += " | autocmd BufDelete <buffer> echo 'File closed'"
	}

	return c.ExecuteCommand(command)
}

func (c *NvrClient) openFromStdin(opts FileOptions) error {
	// Read from stdin and create buffer
	// This is a simplified implementation
	command := "enew"
	if opts.UseTab {
		command = "tabnew"
	} else if opts.HorizontalSplit {
		command = "split"
	} else if opts.VerticalSplit {
		command = "vsplit"
	}

	return c.ExecuteCommand(command)
}