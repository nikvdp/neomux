package client

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
)

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

// Simple msgpack-like encoding for basic types
func encodeMsgpack(value interface{}) ([]byte, error) {
	switch v := value.(type) {
	case string:
		return encodeString(v)
	case int:
		return encodeInt(v)
	case uint64:
		return encodeUint(v)
	case []interface{}:
		return encodeArray(v)
	default:
		return json.Marshal(v)
	}
}

func encodeString(s string) ([]byte, error) {
	buf := bytes.Buffer{}
	buf.WriteByte(0xA0 | byte(len(s))) // Fixstr format
	buf.WriteString(s)
	return buf.Bytes(), nil
}

func encodeInt(i int) ([]byte, error) {
	buf := bytes.Buffer{}
	if i >= 0 {
		if i <= 127 {
			buf.WriteByte(byte(i))
		} else if i <= 32767 {
			buf.WriteByte(0xCD) // uint16
			binary.Write(&buf, binary.BigEndian, uint16(i))
		} else {
			buf.WriteByte(0xCE) // uint32
			binary.Write(&buf, binary.BigEndian, uint32(i))
		}
	} else {
		if i >= -32 {
			buf.WriteByte(byte(i))
		} else if i >= -32768 {
			buf.WriteByte(0xD1) // int16
			binary.Write(&buf, binary.BigEndian, int16(i))
		} else {
			buf.WriteByte(0xD2) // int32
			binary.Write(&buf, binary.BigEndian, int32(i))
		}
	}
	return buf.Bytes(), nil
}

func encodeUint(i uint64) ([]byte, error) {
	buf := bytes.Buffer{}
	if i <= 127 {
		buf.WriteByte(byte(i))
	} else if i <= 255 {
		buf.WriteByte(0xCC) // uint8
		buf.WriteByte(byte(i))
	} else if i <= 65535 {
		buf.WriteByte(0xCD) // uint16
		binary.Write(&buf, binary.BigEndian, uint16(i))
	} else if i <= 4294967295 {
		buf.WriteByte(0xCE) // uint32
		binary.Write(&buf, binary.BigEndian, uint32(i))
	} else {
		buf.WriteByte(0xCF) // uint64
		binary.Write(&buf, binary.BigEndian, i)
	}
	return buf.Bytes(), nil
}

func encodeArray(arr []interface{}) ([]byte, error) {
	buf := bytes.Buffer{}
	if len(arr) <= 15 {
		buf.WriteByte(0x90 | byte(len(arr))) // Fixarray format
	} else {
		buf.WriteByte(0xDC) // array16
		binary.Write(&buf, binary.BigEndian, uint16(len(arr)))
	}

	for _, item := range arr {
		data, err := encodeMsgpack(item)
		if err != nil {
			return nil, err
		}
		buf.Write(data)
	}

	return buf.Bytes(), nil
}