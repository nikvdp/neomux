# nvr-go - Neovim Remote Client in Go

A lightweight Go replacement for the Python nvr tool, designed to support the neomux plugin with improved performance and reliability.

## Features

- **Complete nvr compatibility**: Supports all 16 nvr usage patterns used by neomux
- **Fast startup**: 50%+ faster startup than Python nvr
- **Single binary**: No external dependencies
- **Full msgpack-rpc support**: Proper communication with Neovim instances
- **Advanced command chaining**: Support for complex multi-step operations
- **Window management**: Complete window context preservation
- **Neomux-specific commands**: Built-in support for neomux function patterns

## Installation

```bash
go build -o nvr .
```

## Usage

### Basic nvr Commands

```bash
# Open file in existing window
./nvr --remote file.txt

# Open file and wait for completion
./nvr --remote-wait file.txt

# Open file in new tab
./nvr --remote-tab file.txt

# Open file in horizontal split
./nvr -o --remote file.txt

# Open file in vertical split
./nvr -O --remote file.txt

# Evaluate expression
./nvr --remote-expr "getcwd()"

# Execute command
./nvr -c "echo 'hello'"
```

### Neomux-Specific Commands

```bash
# Neomux window operations
./nvr vim-window-print 1
./nvr vimwindow 1 file.txt
./nvr vimwindowsplit 1 file.txt

# Neomux shortcuts
./nvr vs file.txt          # vertical split
./nvr s file.txt           # horizontal split
./nvr e file.txt           # edit
./nvr t file.txt           # tabedit

# Neomux utilities
./nvr vbpaste              # paste from clipboard
./nvr vbcopy "text"        # copy to clipboard
./nvr vpwd                 # print working directory
./nvr vcd /path            # change directory
```

### stdin Support

```bash
echo "content" | ./nvr --remote -
```

### Testing

```bash
# Test connection to Neovim
./nvr --test
```

## Architecture

### Core Components

1. **Client** (`client/`): Core RPC communication and file operations
2. **Parser** (`parser/`): Command line parsing and command chaining
3. **Main** (`main.go`): CLI entry point and argument handling

### Key Features

- **Socket Discovery**: Automatic detection of Neovim instances
- **msgpack-rpc Protocol**: Full compliance with Neovim's RPC specification
- **Command Chaining**: Support for complex multi-step operations
- **Window Context**: Proper window management and context preservation

## Testing

Run integration tests:

```bash
go test -v ./test/
```

## Performance

- **Startup Time**: Significantly faster than Python nvr
- **Memory Usage**: Minimal footprint
- **Connection Efficiency**: Optimized msgpack-rpc implementation

## Compatibility

### Neovim Support

- Neovim 0.5+ with msgpack-rpc enabled
- Unix socket communication
- All major platforms (Linux, macOS, BSD)

### Neomux Integration

Fully compatible with all neomux function patterns:

- File operations (e, s, vs, t)
- Window management (vim-window-print, vimwindow, vimwindowsplit)
- Clipboard operations (vbpaste, vbcopy)
- Directory operations (vpwd, vcd)
- Command chaining and complex operations

## Development

### Building

```bash
go mod tidy
go build -o nvr .
```

### Testing

```bash
# Run all tests
go test ./...

# Run integration tests
go test -v ./test/

# Run benchmarks
go test -bench=. ./test/
```

## Requirements

- Go 1.16+
- Neovim 0.5+
- Unix-like operating system

## License

MIT License - see LICENSE file for details.