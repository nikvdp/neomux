package client

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/neovim/go-client/nvim"
)

type FileOptions struct {
	UseTab          bool
	HorizontalSplit bool
	VerticalSplit   bool
	Wait            bool
	FromStdin       bool
}

type NvrClient struct {
	nv      *nvim.Nvim
	waitMu  sync.Mutex
	waitCh  chan string
	waitBuf nvim.Buffer
}

func NewNvrClient(socketPath string) (*NvrClient, error) {
	nv, err := nvim.Dial(socketPath)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to socket %s: %w", socketPath, err)
	}

	client := &NvrClient{nv: nv}
	if err := client.registerNotificationHandlers(); err != nil {
		nv.Close()
		return nil, fmt.Errorf("failed to register notification handlers: %w", err)
	}

	return client, nil
}

func (c *NvrClient) registerNotificationHandlers() error {
	events := []string{"BufDelete", "Exit"}
	for _, name := range events {
		eventName := name
		if err := c.nv.RegisterHandler(eventName, func(args ...interface{}) {
			c.dispatchNotification(eventName, args)
		}); err != nil {
			return err
		}
	}
	return nil
}

func (c *NvrClient) dispatchNotification(event string, args []interface{}) {
	c.waitMu.Lock()
	ch := c.waitCh
	buf := c.waitBuf
	c.waitMu.Unlock()

	if ch == nil {
		return
	}

	if event == "BufDelete" && buf != 0 {
		if len(args) > 0 {
			if bufNo, ok := toInt(args[0]); ok && bufNo != int(buf) {
				return
			}
		}
	}

	select {
	case ch <- event:
	default:
	}
}

func toInt(v interface{}) (int, bool) {
	switch value := v.(type) {
	case int:
		return value, true
	case int64:
		return int(value), true
	case float64:
		return int(value), true
	case string:
		if strings.TrimSpace(value) == "" {
			return 0, false
		}
		// best effort conversion
		var parsed int
		_, err := fmt.Sscan(value, &parsed)
		if err != nil {
			return 0, false
		}
		return parsed, true
	default:
		return 0, false
	}
}

func (c *NvrClient) Close() error {
	if c.nv != nil {
		return c.nv.Close()
	}
	return nil
}

func (c *NvrClient) ExecuteCommand(command string) error {
	return c.nv.Command(command)
}

func (c *NvrClient) ExecuteExpression(expr string) (string, error) {
	var result interface{}
	if err := c.nv.Eval(expr, &result); err != nil {
		return "", err
	}
	return fmt.Sprintf("%v", result), nil
}

func (c *NvrClient) withDeferredBufReadPost(fn func() error) error {
	var currentIgnore string
	if err := c.nv.Option("eventignore", &currentIgnore); err != nil {
		return fmt.Errorf("failed to read eventignore: %w", err)
	}

	needsSuppression := !eventListed(currentIgnore, "BufReadPost")
	if needsSuppression {
		updated := currentIgnore
		if strings.TrimSpace(updated) == "" {
			updated = "BufReadPost"
		} else {
			updated = fmt.Sprintf("%s,%s", updated, "BufReadPost")
		}

		if err := c.nv.SetOption("eventignore", updated); err != nil {
			return fmt.Errorf("failed to set eventignore: %w", err)
		}
	}

	err := fn()

	if needsSuppression {
		if restoreErr := c.nv.SetOption("eventignore", currentIgnore); restoreErr != nil {
			if err == nil {
				err = fmt.Errorf("failed to restore eventignore: %w", restoreErr)
			}
		}

		if err == nil {
			if execErr := c.nv.Command("doautocmd BufReadPost"); execErr != nil {
				err = fmt.Errorf("failed to replay BufReadPost autocommands: %w", execErr)
			}
		}
	}

	return err
}

func eventListed(list string, event string) bool {
	if strings.TrimSpace(list) == "" {
		return false
	}

	for _, part := range strings.Split(list, ",") {
		if strings.TrimSpace(part) == event {
			return true
		}
	}
	return false
}

func (c *NvrClient) fnameEscape(path string) (string, error) {
	var escaped string
	if err := c.nv.Call("fnameescape", &escaped, path); err != nil {
		return "", err
	}
	return escaped, nil
}

// Test function to verify connection
func (c *NvrClient) TestConnection() error {
	info, err := c.nv.APIInfo()
	if err != nil {
		return err
	}
	fmt.Printf("API Info: %v\n", info)
	return nil
}

func (c *NvrClient) OpenFile(filename string, opts FileOptions) error {
	if opts.FromStdin {
		return c.openFromStdin(opts)
	}

	absPath := filename
	if !strings.HasPrefix(filename, "/") && !strings.HasPrefix(filename, "~") {
		if abs, err := filepath.Abs(filename); err == nil {
			absPath = abs
		}
	}

	escapedPath, err := c.fnameEscape(absPath)
	if err != nil {
		escapedPath = escapeVimString(absPath)
	}

	var oldShortmess string
	shortmessSet := false
	if err := c.nv.Option("shortmess", &oldShortmess); err == nil {
		newShortmess := strings.ReplaceAll(oldShortmess, "F", "")
		if err := c.nv.SetOption("shortmess", newShortmess); err == nil {
			shortmessSet = true
			defer c.nv.SetOption("shortmess", oldShortmess)
		}
	}

	var command string
	switch {
	case opts.UseTab:
		command = fmt.Sprintf("tabedit %s", escapedPath)
	case opts.HorizontalSplit:
		command = fmt.Sprintf("split %s", escapedPath)
	case opts.VerticalSplit:
		command = fmt.Sprintf("vsplit %s", escapedPath)
	default:
		command = fmt.Sprintf("edit %s", escapedPath)
	}

	openErr := c.withDeferredBufReadPost(func() error {
		return c.nv.Command(command)
	})

	if !shortmessSet {
		// restore even if setting failed earlier but we changed it manually
		if strings.Contains(oldShortmess, "F") {
			_ = c.nv.SetOption("shortmess", oldShortmess)
		}
	}

	if openErr != nil {
		return fmt.Errorf("failed to execute open command: %v", openErr)
	}

	if opts.HorizontalSplit || opts.VerticalSplit {
		if err := c.nv.Command("wincmd ="); err != nil {
			return fmt.Errorf("failed to balance windows: %v", err)
		}
	}

	if opts.Wait {
		return c.waitForFileClose(filename)
	}

	return nil
}

func (c *NvrClient) openFromStdin(opts FileOptions) error {
	content, err := readAllStdin()
	if err != nil {
		return fmt.Errorf("failed to read from stdin: %v", err)
	}

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
	channelID := c.nv.ChannelID()
	buf, err := c.nv.CurrentBuffer()
	if err != nil {
		return fmt.Errorf("failed to get current buffer: %w", err)
	}

	setup := fmt.Sprintf(`augroup nvr
autocmd!
autocmd BufDelete <buffer> silent! call rpcnotify(%d, 'BufDelete', str2nr(expand('<abuf>')))
autocmd VimLeave * if exists('v:exiting') && v:exiting > 0 | silent! call rpcnotify(%d, 'Exit', v:exiting) | endif
augroup END`, channelID, channelID)

	if _, err := c.nv.Exec(setup, false); err != nil {
		return fmt.Errorf("failed to setup autocommands: %w", err)
	}
	defer c.nv.Exec("augroup nvr\nautocmd!\naugroup END", false)

	if err := c.manageBufVars(buf, channelID); err != nil {
		return err
	}

	waitCh := make(chan string, 2)
	c.waitMu.Lock()
	c.waitCh = waitCh
	c.waitBuf = buf
	c.waitMu.Unlock()
	defer func() {
		c.waitMu.Lock()
		if c.waitCh == waitCh {
			c.waitCh = nil
			c.waitBuf = 0
		}
		c.waitMu.Unlock()
	}()

	timeout := time.After(5 * time.Minute)
	for {
		select {
		case evt := <-waitCh:
			if evt == "BufDelete" || evt == "Exit" {
				return nil
			}
		case <-timeout:
			return fmt.Errorf("timeout waiting for buffer to close")
		}
	}
}

func (c *NvrClient) manageBufVars(buf nvim.Buffer, channelID int) error {
	var raw interface{}
	existing := []int{}

	if err := c.nv.BufferVar(buf, "nvr", &raw); err == nil {
		switch v := raw.(type) {
		case []interface{}:
			for _, item := range v {
				if id, ok := toInt(item); ok {
					existing = append(existing, id)
				}
			}
		case []int:
			existing = append(existing, v...)
		case []int64:
			for _, id := range v {
				existing = append(existing, int(id))
			}
		}
	}

	for _, id := range existing {
		if id == channelID {
			return nil
		}
	}

	newChannels := append([]int{channelID}, existing...)
	if err := c.nv.SetBufferVar(buf, "nvr", newChannels); err != nil {
		return fmt.Errorf("failed to set buffer variable: %w", err)
	}

	return nil
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
			content.WriteString(line)
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
	s = strings.ReplaceAll(s, "'", "''")
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	s = strings.ReplaceAll(s, "\n", "\\n")
	s = strings.ReplaceAll(s, "\t", "\\t")
	return s
}
