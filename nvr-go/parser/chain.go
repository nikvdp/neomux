package parser

import (
	"fmt"
	"strconv"
	"strings"
)

func ParseComplexCommand(args []string) (*CommandChain, error) {
	chain := &CommandChain{
		Operations:   make([]Operation, 0),
		WindowContext: 0,
	}

	for i := 0; i < len(args); i++ {
		arg := args[i]

		switch {
		case strings.HasPrefix(arg, "-c") || strings.HasPrefix(arg, "-cc"):
			// Handle command arguments
			var cmd string
			if strings.HasPrefix(arg, "-c") && len(arg) > 2 {
				cmd = arg[2:]
			} else if strings.HasPrefix(arg, "-cc") && len(arg) > 3 {
				cmd = arg[3:]
			} else if i+1 < len(args) {
				cmd = args[i+1]
				i++
			} else {
				return nil, fmt.Errorf("command argument missing value")
			}

			// Parse window switching commands
			if isWindowSwitchCommand(cmd) {
				if err := parseWindowCommand(cmd, chain); err != nil {
					return nil, err
				}
			} else {
				chain.Operations = append(chain.Operations, Operation{
					Type:    OpCommand,
					Content: cmd,
				})
			}

		case strings.HasPrefix(arg, "--remote"):
			// Handle file operations with window context preservation
			if err := parseRemoteOperation(arg, args, &i, chain); err != nil {
				return nil, err
			}

		case arg == "--remote-expr":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("--remote-expr requires an expression")
			}
			chain.Operations = append(chain.Operations, Operation{
				Type:    OpExpression,
				Content: args[i+1],
			})
			i++

		default:
			// Try to parse as neomux-specific command
			if isNeomuxSpecificCommand(arg) {
				if err := parseNeomuxSpecific(arg, args, &i, chain); err != nil {
					return nil, err
				}
			} else {
				// Default to simple file operation
				chain.Operations = append(chain.Operations, Operation{
					Type:    OpFile,
					Content: arg,
				})
			}
		}
	}

	return chain, nil
}

func isWindowSwitchCommand(cmd string) bool {
	return strings.Contains(cmd, "wincmd") ||
		   strings.Contains(cmd, "buffer") ||
		   strings.Contains(cmd, "tabnext") ||
		   strings.Contains(cmd, "tabprevious")
}

func parseWindowCommand(cmd string, chain *CommandChain) error {
	// Extract window number from commands like "1wincmd w", "2wincmd w", etc.
	if strings.Contains(cmd, "wincmd w") {
		parts := strings.Fields(cmd)
		if len(parts) >= 2 {
			if winNum, err := strconv.Atoi(parts[0]); err == nil {
				chain.WindowContext = winNum
			}
		}
	}

	chain.Operations = append(chain.Operations, Operation{
		Type:    OpCommand,
		Content: cmd,
	})

	return nil
}

func parseRemoteOperation(arg string, args []string, index *int, chain *CommandChain) error {
	var file string
	var opts FileOptions

	switch arg {
	case "--remote":
		if *index+1 >= len(args) {
			return fmt.Errorf("--remote requires a file argument")
		}
		file = args[*index+1]
		*index++
	case "--remote-wait":
		if *index+1 >= len(args) {
			return fmt.Errorf("--remote-wait requires a file argument")
		}
		file = args[*index+1]
		opts.Wait = true
		*index++
	case "--remote-tab":
		if *index+1 >= len(args) {
			return fmt.Errorf("--remote-tab requires a file argument")
		}
		file = args[*index+1]
		opts.UseTab = true
		*index++
	default:
		return fmt.Errorf("unknown remote operation: %s", arg)
	}

	chain.Operations = append(chain.Operations, Operation{
		Type:    OpFile,
		Content: file,
		Options: opts,
	})

	return nil
}

func isNeomuxSpecificCommand(cmd string) bool {
	neomuxCmds := []string{
		"vim-window-print", "vimwindow", "vimwindowsplit",
		"vbpaste", "vbcopy", "vpwd", "vcd", "vs", "e", "t",
	}

	for _, nc := range neomuxCmds {
		if cmd == nc {
			return true
		}
	}
	return false
}

func parseNeomuxSpecific(cmd string, args []string, index *int, chain *CommandChain) error {
	switch cmd {
	case "vs", "vsplit":
		if *index+1 >= len(args) {
			return fmt.Errorf("%s requires a file argument", cmd)
		}
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpFile,
			Content: args[*index+1],
			Options: FileOptions{VerticalSplit: true},
		})
		*index++

	case "s", "split":
		if *index+1 >= len(args) {
			return fmt.Errorf("%s requires a file argument", cmd)
		}
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpFile,
			Content: args[*index+1],
			Options: FileOptions{HorizontalSplit: true},
		})
		*index++

	case "e", "edit":
		if *index+1 >= len(args) {
			return fmt.Errorf("%s requires a file argument", cmd)
		}
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpFile,
			Content: args[*index+1],
		})
		*index++

	case "t", "tabedit":
		if *index+1 >= len(args) {
			return fmt.Errorf("%s requires a file argument", cmd)
		}
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpFile,
			Content: args[*index+1],
			Options: FileOptions{UseTab: true},
		})
		*index++

	case "vbpaste":
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpExpression,
			Content: "getreg('+')",
		})

	case "vbcopy":
		if *index+1 >= len(args) {
			return fmt.Errorf("vbcopy requires content")
		}
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpCommand,
			Content: fmt.Sprintf("let @+ = '%s'", escapeVimString(args[*index+1])),
		})
		*index++

	case "vpwd":
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpExpression,
			Content: "getcwd(-1,-1)",
		})

	case "vcd":
		if *index+1 >= len(args) {
			return fmt.Errorf("vcd requires a directory")
		}
		chain.Operations = append(chain.Operations, Operation{
			Type:    OpCommand,
			Content: fmt.Sprintf("chdir %s", args[*index+1]),
		})
		*index++

	default:
		return fmt.Errorf("unsupported neomux command: %s", cmd)
	}

	return nil
}

// ExecuteCommandChain executes a series of operations with proper window context
func ExecuteCommandChain(chain *CommandChain, executor func(op Operation) error) error {
	// If window context is specified, switch to that window first
	if chain.WindowContext > 0 {
		if err := executor(Operation{
			Type:    OpCommand,
			Content: fmt.Sprintf("%dwincmd w", chain.WindowContext),
		}); err != nil {
			return fmt.Errorf("failed to switch to window %d: %v", chain.WindowContext, err)
		}
	}

	// Execute all operations in the chain
	for _, op := range chain.Operations {
		if err := executor(op); err != nil {
			return fmt.Errorf("failed to execute operation: %v", err)
		}
	}

	return nil
}