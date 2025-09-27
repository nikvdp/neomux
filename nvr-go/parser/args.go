package parser

import (
	"fmt"
	"os"
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
			cmd := args[i+1]

			// Special handling for split commands that should modify file opening
			// When used with --remote-wait, these should affect how the file is opened
			if cmd == "vsplit" || cmd == "split" {
				// Check if next arg is --remote-wait or similar
				if i+2 < len(args) && strings.HasPrefix(args[i+2], "--remote") {
					// This is a split directive for the file opening
					if cmd == "vsplit" {
						cli.VerticalSplit = true
					} else {
						cli.HorizontalSplit = true
					}
					i++ // Skip the split command
					continue
				}
			}

			cli.Commands = append(cli.Commands, cmd)
			i++
		default:
			fmt.Fprintf(os.Stderr, "Warning: unknown argument '%s'\n", arg)
		}
	}

	return cli, nil
}


func escapeVimString(s string) string {
	s = strings.ReplaceAll(s, "'", "''")
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	s = strings.ReplaceAll(s, "\n", "\\n")
	s = strings.ReplaceAll(s, "\t", "\\t")
	return s
}