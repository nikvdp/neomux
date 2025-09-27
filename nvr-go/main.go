package main

import (
	"fmt"
	"os"
	"github.com/neomux/nvr-go/client"
	"github.com/neomux/nvr-go/parser"
)

type CLIArgs = parser.CLIArgs

func main() {
	// Check for test flag before parsing
	for _, arg := range os.Args[1:] {
		if arg == "--test" {
			testConnection()
			return
		}
	}

	args, err := parser.ParseArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing arguments: %v\n", err)
		os.Exit(1)
	}

	if len(args.Remote) == 0 && len(args.RemoteWait) == 0 && len(args.RemoteTab) == 0 &&
		len(args.RemoteExpr) == 0 && len(args.Commands) == 0 && !args.ReadStdin {
		fmt.Println("Usage: nvr [options]")
		fmt.Println()
		fmt.Println("Remote control Neovim processes.")
		fmt.Println()
		fmt.Println("Options:")
		fmt.Println("  --remote <file>       Use :edit to open files")
		fmt.Println("  --remote-wait <file>  Like --remote, but wait until buffer is closed")
		fmt.Println("  --remote-tab <file>   Like --remote, but use :tabedit")
		fmt.Println("  --remote-expr <expr>  Evaluate expression and print result")
		fmt.Println("  -c <command>          Execute a command after other options")
		fmt.Println("  -cc <command>         Execute a command before other options")
		fmt.Println("  -o                    Open files via :split")
		fmt.Println("  -O                    Open files via :vsplit")
		fmt.Println("  --test                Test connection to Neovim")
		fmt.Println()
		fmt.Println("Examples:")
		fmt.Println("  nvr file1 file2       Open files (equivalent to --remote)")
		fmt.Println("  nvr -cc split file    Split window and open file")
		fmt.Println("  nvr -c 'echo \"hi\"'     Execute command")
		fmt.Println("  echo 'text' | nvr -   Read from stdin")
		os.Exit(1)
	}

	socketPath, err := findNeovimSocket()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	nvrClient, err := client.NewNvrClient(socketPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error connecting to Neovim: %v\n", err)
		os.Exit(1)
	}
	defer nvrClient.Close()

	if err := executeCommands(nvrClient, args); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}


func findNeovimSocket() (string, error) {
	return client.FindNeovimSocket()
}

func testConnection() {
	fmt.Println("Testing connection to Neovim...")

	socketPath, err := findNeovimSocket()
	if err != nil {
		fmt.Printf("Error finding socket: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Found socket: %s\n", socketPath)

	nvrClient, err := client.NewNvrClient(socketPath)
	if err != nil {
		fmt.Printf("Error connecting: %v\n", err)
		os.Exit(1)
	}
	defer nvrClient.Close()

	fmt.Println("Connected successfully!")

	if err := nvrClient.TestConnection(); err != nil {
		fmt.Printf("Test failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Connection test completed successfully!")
}

func executeCommands(nvrClient *client.NvrClient, args *parser.CLIArgs) error {
	// Execute remote expressions first
	for _, expr := range args.RemoteExpr {
		result, err := nvrClient.ExecuteExpression(expr)
		if err != nil {
			return fmt.Errorf("failed to execute expression '%s': %v", expr, err)
		}
		fmt.Println(result)
	}

	// Execute commands
	for _, cmd := range args.Commands {
		if err := nvrClient.ExecuteCommand(cmd); err != nil {
			return fmt.Errorf("failed to execute command '%s': %v", cmd, err)
		}
	}

	// Handle file operations
	for _, file := range args.Remote {
		opts := client.FileOptions{
			HorizontalSplit: args.HorizontalSplit,
			VerticalSplit:   args.VerticalSplit,
		}
		if err := nvrClient.OpenFile(file, opts); err != nil {
			return fmt.Errorf("failed to open file '%s': %v", file, err)
		}
	}

	for _, file := range args.RemoteWait {
		opts := client.FileOptions{
			HorizontalSplit: args.HorizontalSplit,
			VerticalSplit:   args.VerticalSplit,
			Wait:           true,
		}
		if err := nvrClient.OpenFile(file, opts); err != nil {
			return fmt.Errorf("failed to open file '%s': %v", file, err)
		}
	}

	for _, file := range args.RemoteTab {
		opts := client.FileOptions{
			UseTab: true,
		}
		if err := nvrClient.OpenFile(file, opts); err != nil {
			return fmt.Errorf("failed to open file '%s': %v", file, err)
		}
	}

	// Handle stdin reading
	if args.ReadStdin {
		opts := client.FileOptions{
			FromStdin: true,
		}
		if err := nvrClient.OpenFile("", opts); err != nil {
			return fmt.Errorf("failed to read from stdin: %v", err)
		}
	}

	return nil
}