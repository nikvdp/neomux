package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
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

func main() {
	args := parseArgs(os.Args[1:])

	if len(args.Remote) == 0 && len(args.RemoteWait) == 0 && len(args.RemoteTab) == 0 &&
		len(args.RemoteExpr) == 0 && len(args.Commands) == 0 && !args.ReadStdin {
		fmt.Println("Usage: nvr [options]")
		fmt.Println("  --remote <file>       Open file in existing window")
		fmt.Println("  --remote-wait <file>  Open file and wait for completion")
		fmt.Println("  --remote-tab <file>   Open file in new tab")
		fmt.Println("  --remote-expr <expr>   Evaluate and return result")
		fmt.Println("  -c <command>          Execute Vim command")
		fmt.Println("  -cc <command>         Execute Vim command (alias)")
		fmt.Println("  -o                    Open file in horizontal split")
		fmt.Println("  -O                    Open file in vertical split")
		os.Exit(1)
	}

	socketPath, err := findNeovimSocket()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	client, err := NewNvrClient(socketPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error connecting to Neovim: %v\n", err)
		os.Exit(1)
	}
	defer client.Close()

	if err := executeCommands(client, args); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func parseArgs(args []string) *CLIArgs {
	cli := &CLIArgs{}

	flagSet := flag.NewFlagSet("nvr", flag.ExitOnError)
	flagSet.BoolVar(&cli.HorizontalSplit, "o", false, "Open file in horizontal split")
	flagSet.BoolVar(&cli.VerticalSplit, "O", false, "Open file in vertical split")

	var remote, remoteWait, remoteTab, remoteExpr, commands []string
	flagSet.Func("remote", "Open file in existing window", func(s string) error {
		remote = append(remote, s)
		return nil
	})
	flagSet.Func("remote-wait", "Open file and wait for completion", func(s string) error {
		remoteWait = append(remoteWait, s)
		return nil
	})
	flagSet.Func("remote-tab", "Open file in new tab", func(s string) error {
		remoteTab = append(remoteTab, s)
		return nil
	})
	flagSet.Func("remote-expr", "Evaluate and return result", func(s string) error {
		remoteExpr = append(remoteExpr, s)
		return nil
	})
	flagSet.Func("c", "Execute Vim command", func(s string) error {
		commands = append(commands, s)
		return nil
	})
	flagSet.Func("cc", "Execute Vim command (alias)", func(s string) error {
		commands = append(commands, s)
		return nil
	})

	flagSet.Parse(args)

	cli.Remote = remote
	cli.RemoteWait = remoteWait
	cli.RemoteTab = remoteTab
	cli.RemoteExpr = remoteExpr
	cli.Commands = commands

	// Check for stdin reading
	for i, arg := range args {
		if arg == "--remote" && i+1 < len(args) && args[i+1] == "-" {
			cli.ReadStdin = true
			break
		}
	}

	return cli
}

func findNeovimSocket() (string, error) {
	// Check NVIM_LISTEN_ADDRESS environment variable
	if socket := os.Getenv("NVIM_LISTEN_ADDRESS"); socket != "" {
		return socket, nil
	}

	// Check NVIM environment variable and derive socket path
	if nvim := os.Getenv("NVIM"); nvim != "" {
		socket := filepath.Join("/tmp", nvim+"0")
		if _, err := os.Stat(socket); err == nil {
			return socket, nil
		}
	}

	// Search for active sockets in /tmp/nvim*/0 pattern
	matches, err := filepath.Glob("/tmp/nvim*/0")
	if err != nil {
		return "", fmt.Errorf("error searching for Neovim sockets: %v", err)
	}

	if len(matches) == 0 {
		return "", fmt.Errorf("no Neovim instance found. Is Neovim running with RPC enabled?")
	}

	// Return the first active socket
	return matches[0], nil
}

func executeCommands(client *NvrClient, args *CLIArgs) error {
	// Execute remote expressions first
	for _, expr := range args.RemoteExpr {
		result, err := client.ExecuteExpression(expr)
		if err != nil {
			return fmt.Errorf("failed to execute expression '%s': %v", expr, err)
		}
		fmt.Println(result)
	}

	// Execute commands
	for _, cmd := range args.Commands {
		if err := client.ExecuteCommand(cmd); err != nil {
			return fmt.Errorf("failed to execute command '%s': %v", cmd, err)
		}
	}

	// Handle file operations
	for _, file := range args.Remote {
		opts := FileOptions{
			HorizontalSplit: args.HorizontalSplit,
			VerticalSplit:   args.VerticalSplit,
		}
		if err := client.OpenFile(file, opts); err != nil {
			return fmt.Errorf("failed to open file '%s': %v", file, err)
		}
	}

	for _, file := range args.RemoteWait {
		opts := FileOptions{
			HorizontalSplit: args.HorizontalSplit,
			VerticalSplit:   args.VerticalSplit,
			Wait:           true,
		}
		if err := client.OpenFile(file, opts); err != nil {
			return fmt.Errorf("failed to open file '%s': %v", file, err)
		}
	}

	for _, file := range args.RemoteTab {
		opts := FileOptions{
			UseTab: true,
		}
		if err := client.OpenFile(file, opts); err != nil {
			return fmt.Errorf("failed to open file '%s': %v", file, err)
		}
	}

	// Handle stdin reading
	if args.ReadStdin {
		opts := FileOptions{
			FromStdin: true,
		}
		if err := client.OpenFile("", opts); err != nil {
			return fmt.Errorf("failed to read from stdin: %v", err)
		}
	}

	return nil
}