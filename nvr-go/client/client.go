package client

import (
	"bufio"
	"bytes"
	"encoding/binary"
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

	var buf bytes.Buffer

	// Format: [0, msgid, method, args]
	buf.WriteByte(0x94) // Fixarray with 4 elements

	// Type: 0 for request
	buf.WriteByte(0x00)

	// Message ID
	if err := encodeUint(&buf, req.ID); err != nil {
		return err
	}

	// Method
	if err := encodeString(&buf, req.Method); err != nil {
		return err
	}

	// Args
	if err := encodeArray(&buf, req.Args); err != nil {
		return err
	}

	// Write the message
	_, err := c.conn.Write(buf.Bytes())
	return err
}

func (c *NvrClient) readResponse() (*RPCResponse, error) {
	// Read response header (4 bytes for msgpack array format)
	header := make([]byte, 4)
	if _, err := c.conn.Read(header); err != nil {
		return nil, fmt.Errorf("failed to read response header: %v", err)
	}

	// Check if it's a msgpack array with 4 elements [type, msgid, error, result]
	if header[0] != 0x94 {
		return nil, fmt.Errorf("invalid msgpack response format: expected array with 4 elements")
	}

	// For now, we'll implement a simple parser that extracts basic information
	// A full msgpack decoder would be more complex

	// Read the rest of the response
	buf := make([]byte, 8192)
	n, err := c.conn.Read(buf)
	if err != nil {
		return nil, fmt.Errorf("failed to read response data: %v", err)
	}

	var resp RPCResponse
	resp.Type = 1 // Response type

	// Try to extract meaningful data from the response
	// This is a simplified approach - a proper msgpack decoder would be better
	data := string(buf[:n])

	// Look for string patterns that might be the actual result
	if len(data) > 0 {
		// Try to find string content (this is very simplified)
		resp.Result = extractMeaningfulData(buf[:n])
	} else {
		resp.Result = ""
	}

	resp.Error = nil

	return &resp, nil
}

func extractMeaningfulData(data []byte) interface{} {
	// Simple heuristic to extract meaningful data from msgpack
	// Look for string patterns or numeric values

	for i := 0; i < len(data)-1; i++ {
		// Look for string format markers
		if data[i] >= 0xA0 && data[i] <= 0xBF { // Fixstr format
			strLen := int(data[i] & 0x1F)
			if i+1+strLen <= len(data) {
				return string(data[i+1 : i+1+strLen])
			}
		} else if data[i] == 0xDB { // str32 format
			if i+5 <= len(data) {
				strLen := int(data[i+1])<<24 | int(data[i+2])<<16 | int(data[i+3])<<8 | int(data[i+4])
				if i+5+strLen <= len(data) {
					return string(data[i+5 : i+5+strLen])
				}
			}
		} else if data[i] == 0xDA { // str16 format
			if i+3 <= len(data) {
				strLen := int(data[i+1])<<8 | int(data[i+2])
				if i+3+strLen <= len(data) {
					return string(data[i+3 : i+3+strLen])
				}
			}
		}
	}

	// Fallback: try to interpret as numeric
	if len(data) >= 1 {
		switch data[0] {
		case 0x00: // positive fixint
			return int(data[0])
		case 0xCC: // uint8
			if len(data) >= 2 {
				return int(data[1])
			}
		case 0xCD: // uint16
			if len(data) >= 3 {
				return int(data[1])<<8 | int(data[2])
			}
		}
	}

	return "unknown"
}

func encodeUint(buf *bytes.Buffer, value uint64) error {
	if value <= 127 {
		buf.WriteByte(byte(value))
	} else if value <= 255 {
		buf.WriteByte(0xCC) // uint8
		buf.WriteByte(byte(value))
	} else if value <= 65535 {
		buf.WriteByte(0xCD) // uint16
		binary.Write(buf, binary.BigEndian, uint16(value))
	} else if value <= 4294967295 {
		buf.WriteByte(0xCE) // uint32
		binary.Write(buf, binary.BigEndian, uint32(value))
	} else {
		buf.WriteByte(0xCF) // uint64
		binary.Write(buf, binary.BigEndian, value)
	}
	return nil
}

func encodeString(buf *bytes.Buffer, s string) error {
	strBytes := []byte(s)
	if len(strBytes) <= 31 {
		buf.WriteByte(0xA0 | byte(len(strBytes))) // Fixstr
	} else if len(strBytes) <= 255 {
		buf.WriteByte(0xD9) // str8
		buf.WriteByte(byte(len(strBytes)))
	} else if len(strBytes) <= 65535 {
		buf.WriteByte(0xDA) // str16
		binary.Write(buf, binary.BigEndian, uint16(len(strBytes)))
	} else {
		buf.WriteByte(0xDB) // str32
		binary.Write(buf, binary.BigEndian, uint32(len(strBytes)))
	}
	buf.Write(strBytes)
	return nil
}

func encodeArray(buf *bytes.Buffer, arr []interface{}) error {
	if len(arr) <= 15 {
		buf.WriteByte(0x90 | byte(len(arr))) // Fixarray
	} else {
		buf.WriteByte(0xDC) // array16
		binary.Write(buf, binary.BigEndian, uint16(len(arr)))
	}

	for _, item := range arr {
		switch v := item.(type) {
		case string:
			encodeString(buf, v)
		case int:
			encodeUint(buf, uint64(v))
		case uint64:
			encodeUint(buf, v)
		default:
			// Fallback to string representation
			encodeString(buf, fmt.Sprintf("%v", v))
		}
	}
	return nil
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