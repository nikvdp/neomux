package parser

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type CLIArgs struct {
	Remote       []string
	RemoteWait   []string
	RemoteTab    []string
	RemoteExpr   []string
	Commands     []string
	HorizontalSplit bool
	VerticalSplit bool
	ReadStdin    bool
}

type CommandChain struct {
	Operations []Operation
	WindowContext int
}

type Operation struct {
	Type    OperationType
	Content string
	Options FileOptions
}

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

func ParseArgs(args []string) (*CLIArgs, error) {
	cli := &CLIArgs{}

	for i := 0; i < len(args); i++ {
		arg := args[i]

		switch {
		case arg == "--remote":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("--remote requires a file argument")
			}

			// Check for split options after --remote
			var opts FileOptions
			remainingArgs := args[i+1:]
			fileIndex := 0

			// Process options until we find the filename
			for j := 0; j < len(remainingArgs); j++ {
				nextArg := remainingArgs[j]
				if nextArg == "-o" {
					opts.HorizontalSplit = true
					fileIndex = j + 1
				} else if nextArg == "-O" {
					opts.VerticalSplit = true
					fileIndex = j + 1
				} else if nextArg == "--remote-wait" {
					opts.Wait = true
					fileIndex = j + 1
				} else if !strings.HasPrefix(nextArg, "-") {
					// This is the filename
					fileIndex = j
					break
				} else {
					// Unknown option, treat as filename
					fileIndex = j
					break
				}
			}

			if fileIndex >= len(remainingArgs) {
				return nil, fmt.Errorf("--remote requires a file argument")
			}

			filename := remainingArgs[fileIndex]
			if filename == "-" {
				opts.FromStdin = true
				cli.ReadStdin = true
			} else {
				if opts.UseTab {
					cli.RemoteTab = append(cli.RemoteTab, filename)
				} else if opts.Wait {
					cli.RemoteWait = append(cli.RemoteWait, filename)
				} else if opts.HorizontalSplit {
					cli.HorizontalSplit = true
					cli.Remote = append(cli.Remote, filename)
				} else if opts.VerticalSplit {
					cli.VerticalSplit = true
					cli.Remote = append(cli.Remote, filename)
				} else {
					cli.Remote = append(cli.Remote, filename)
				}
			}

			i += fileIndex + 1 // Skip --remote and all processed args
		case arg == "--remote-wait":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("--remote-wait requires a file argument")
			}
			cli.RemoteWait = append(cli.RemoteWait, args[i+1])
			i++
		case arg == "--remote-tab":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("--remote-tab requires a file argument")
			}
			cli.RemoteTab = append(cli.RemoteTab, args[i+1])
			i++
		case arg == "--remote-expr":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("--remote-expr requires an expression argument")
			}
			cli.RemoteExpr = append(cli.RemoteExpr, args[i+1])
			i++
		case arg == "-c" || arg == "-cc":
			if i+1 >= len(args) {
				return nil, fmt.Errorf("%s requires a command argument", arg)
			}
			cli.Commands = append(cli.Commands, args[i+1])
			i++
		default:
			// Check if it's a neomux-style command
			if isNeomuxCommand(arg) {
				chain, err := parseNeomuxCommand(arg, args[i+1:])
				if err != nil {
					return nil, fmt.Errorf("failed to parse neomux command: %v", err)
				}
				// Convert chain to CLI args
				mergeChainToCLI(chain, cli)
				i += len(chain.Operations) // Skip consumed arguments
			} else {
				fmt.Fprintf(os.Stderr, "Warning: unknown argument '%s'\n", arg)
			}
		}
	}

	return cli, nil
}

func isNeomuxCommand(arg string) bool {
	neomuxCommands := []string{
		"vim-window-print", "vimwindow", "vimwindowsplit",
		"vbpaste", "vbcopy", "vpwd", "vcd",
	}

	for _, cmd := range neomuxCommands {
		if arg == cmd {
			return true
		}
	}
	return false
}

func parseNeomuxCommand(cmd string, args []string) (*CommandChain, error) {
	chain := &CommandChain{}

	switch cmd {
	case "vim-window-print":
		if len(args) < 1 {
			return nil, fmt.Errorf("vim-window-print requires a window number")
		}
		winNum, err := strconv.Atoi(args[0])
		if err != nil {
			return nil, fmt.Errorf("invalid window number: %v", err)
		}

		chain.Operations = []Operation{
			{Type: OpCommand, Content: fmt.Sprintf("%dwincmd w", winNum)},
		}

	case "vimwindow":
		if len(args) < 2 {
			return nil, fmt.Errorf("vimwindow requires a window number and file")
		}
		winNum, err := strconv.Atoi(args[0])
		if err != nil {
			return nil, fmt.Errorf("invalid window number: %v", err)
		}

		chain.Operations = []Operation{
			{Type: OpCommand, Content: fmt.Sprintf("%dwincmd w", winNum)},
			{Type: OpCommand, Content: fmt.Sprintf("edit %s", args[1])},
		}

	case "vimwindowsplit":
		if len(args) < 2 {
			return nil, fmt.Errorf("vimwindowsplit requires a window number and file")
		}
		winNum, err := strconv.Atoi(args[0])
		if err != nil {
			return nil, fmt.Errorf("invalid window number: %v", err)
		}

		chain.Operations = []Operation{
			{Type: OpCommand, Content: fmt.Sprintf("%dwincmd w", winNum)},
			{Type: OpCommand, Content: fmt.Sprintf("split %s", args[1])},
		}

	case "vbpaste":
		chain.Operations = []Operation{
			{Type: OpExpression, Content: "getreg('+')"},
		}

	case "vbcopy":
		if len(args) < 1 {
			return nil, fmt.Errorf("vbcopy requires content")
		}
		chain.Operations = []Operation{
			{Type: OpCommand, Content: fmt.Sprintf("let @+ = '%s'", escapeVimString(strings.Join(args, " ")))},
		}

	case "vpwd":
		chain.Operations = []Operation{
			{Type: OpExpression, Content: "getcwd(-1,-1)"},
		}

	case "vcd":
		if len(args) < 1 {
			return nil, fmt.Errorf("vcd requires a directory")
		}
		chain.Operations = []Operation{
			{Type: OpCommand, Content: fmt.Sprintf("chdir %s", args[0])},
		}

	default:
		return nil, fmt.Errorf("unknown neomux command: %s", cmd)
	}

	return chain, nil
}

func mergeChainToCLI(chain *CommandChain, cli *CLIArgs) {
	for _, op := range chain.Operations {
		switch op.Type {
		case OpCommand:
			cli.Commands = append(cli.Commands, op.Content)
		case OpExpression:
			cli.RemoteExpr = append(cli.RemoteExpr, op.Content)
		case OpFile:
			if op.Options.UseTab {
				cli.RemoteTab = append(cli.RemoteTab, op.Content)
			} else if op.Options.HorizontalSplit {
				cli.HorizontalSplit = true
				cli.Remote = append(cli.Remote, op.Content)
			} else if op.Options.VerticalSplit {
				cli.VerticalSplit = true
				cli.Remote = append(cli.Remote, op.Content)
			} else {
				cli.Remote = append(cli.Remote, op.Content)
			}
		}
	}
}

func escapeVimString(s string) string {
	s = strings.ReplaceAll(s, "'", "''")
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	s = strings.ReplaceAll(s, "\n", "\\n")
	s = strings.ReplaceAll(s, "\t", "\\t")
	return s
}