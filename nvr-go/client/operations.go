package client

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
)

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

func (c *NvrClient) SwitchToWindow(winNum int) error {
	command := fmt.Sprintf("%dwincmd w", winNum)
	return c.ExecuteCommand(command)
}

func (c *NvrClient) GetCurrentWindow() (int, error) {
	result, err := c.ExecuteExpression("tabpagewinnr(tabpagenr())")
	if err != nil {
		return 0, fmt.Errorf("failed to get current window: %v", err)
	}

	// Convert string result to int
	var winNum int
	if _, err := fmt.Sscanf(result, "%d", &winNum); err != nil {
		return 0, fmt.Errorf("failed to parse window number: %v", err)
	}

	return winNum, nil
}

func (c *NvrClient) ExecuteCommandChain(commands []string) error {
	for _, cmd := range commands {
		if err := c.ExecuteCommand(cmd); err != nil {
			return fmt.Errorf("failed to execute command '%s': %v", cmd, err)
		}
	}
	return nil
}

func (c *NvrClient) HandleComplexExpression(expr string) (string, error) {
	result, err := c.ExecuteExpression(expr)
	if err != nil {
		return "", fmt.Errorf("failed to execute expression '%s': %v", expr, err)
	}

	// Post-process result for better formatting
	return formatExpressionResult(result), nil
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

func formatExpressionResult(result string) string {
	// Clean up expression results for better output
	result = strings.TrimSpace(result)
	if strings.HasPrefix(result, "'") && strings.HasSuffix(result, "'") {
		result = result[1 : len(result)-1]
	}
	return result
}