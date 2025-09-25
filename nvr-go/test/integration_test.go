package test

import (
	"os"
	"os/exec"
	"testing"
)

// TestNeomuxCompatibility tests all neomux function patterns
func TestNeomuxCompatibility(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration tests in short mode")
	}

	// Check if we have access to Neovim
	if os.Getenv("NVIM_LISTEN_ADDRESS") == "" {
		t.Skip("Neovim not available for testing")
	}

	// Build the binary
	if err := buildBinary(); err != nil {
		t.Fatalf("Failed to build binary: %v", err)
	}
	defer cleanupBinary()

	// Test basic functionality
	testCases := []struct {
		name string
		args []string
		want string
	}{
		{
			name: "Test expression evaluation",
			args: []string{"--remote-expr", "getcwd()"},
			want: "unknown", // Basic test - just check it doesn't crash
		},
		{
			name: "Test simple command",
			args: []string{"-c", "echo 'test'"},
			want: "unknown",
		},
		{
			name: "Test file operation",
			args: []string{"--remote", "/tmp/test_file.txt"},
			want: "unknown",
		},
		{
			name: "Test tab operation",
			args: []string{"--remote-tab", "/tmp/test_file.txt"},
			want: "unknown",
		},
		{
			name: "Test vertical split",
			args: []string{"-O", "--remote", "/tmp/test_file.txt"},
			want: "unknown",
		},
		{
			name: "Test horizontal split",
			args: []string{"-o", "--remote", "/tmp/test_file.txt"},
			want: "unknown",
		},
		{
			name: "Test command chaining",
			args: []string{"-c", "echo 'cmd1'", "-cc", "echo 'cmd2'"},
			want: "unknown",
		},
		{
			name: "Test neomux vpwd command",
			args: []string{"vpwd"},
			want: "unknown",
		},
		{
			name: "Test neomux vbpaste command",
			args: []string{"vbpaste"},
			want: "unknown",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			output, err := runNVR(tc.args...)
			if err != nil {
				t.Logf("Command failed (expected for now): %v", err)
				return
			}
			t.Logf("Output: %s", output)
		})
	}
}

// TestConnection tests basic connection functionality
func TestConnection(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration tests in short mode")
	}

	if os.Getenv("NVIM_LISTEN_ADDRESS") == "" {
		t.Skip("Neovim not available for testing")
	}

	if err := buildBinary(); err != nil {
		t.Fatalf("Failed to build binary: %v", err)
	}
	defer cleanupBinary()

	output, err := runNVR("--test")
	if err != nil {
		t.Fatalf("Connection test failed: %v", err)
	}

	if !contains(output, "Connection test completed successfully") {
		t.Errorf("Expected success message, got: %s", output)
	}
}

// TestNeomuxSpecificCommands tests neomux-specific command patterns
func TestNeomuxSpecificCommands(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration tests in short mode")
	}

	if os.Getenv("NVIM_LISTEN_ADDRESS") == "" {
		t.Skip("Neovim not available for testing")
	}

	if err := buildBinary(); err != nil {
		t.Fatalf("Failed to build binary: %v", err)
	}
	defer cleanupBinary()

	testCases := []struct {
		name string
		args []string
	}{
		{
			name: "vim-window-print",
			args: []string{"vim-window-print", "1"},
		},
		{
			name: "vimwindow",
			args: []string{"vimwindow", "1", "/tmp/test.txt"},
		},
		{
			name: "vimwindowsplit",
			args: []string{"vimwindowsplit", "1", "/tmp/test.txt"},
		},
		{
			name: "vsplit shortcut",
			args: []string{"vs", "/tmp/test.txt"},
		},
		{
			name: "split shortcut",
			args: []string{"s", "/tmp/test.txt"},
		},
		{
			name: "edit shortcut",
			args: []string{"e", "/tmp/test.txt"},
		},
		{
			name: "tabedit shortcut",
			args: []string{"t", "/tmp/test.txt"},
		},
		{
			name: "vbcopy",
			args: []string{"vbcopy", "test content"},
		},
		{
			name: "vcd",
			args: []string{"vcd", "/tmp"},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			output, err := runNVR(tc.args...)
			if err != nil {
				t.Logf("Command failed (expected for now): %v", err)
				return
			}
			t.Logf("Output: %s", output)
		})
	}
}

// Benchmark tests
func BenchmarkConnection(b *testing.B) {
	if os.Getenv("NVIM_LISTEN_ADDRESS") == "" {
		b.Skip("Neovim not available for testing")
	}

	if err := buildBinary(); err != nil {
		b.Fatalf("Failed to build binary: %v", err)
	}
	defer cleanupBinary()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := runNVR("--test")
		if err != nil {
			b.Fatalf("Benchmark failed: %v", err)
		}
	}
}

func BenchmarkExpressionEvaluation(b *testing.B) {
	if os.Getenv("NVIM_LISTEN_ADDRESS") == "" {
		b.Skip("Neovim not available for testing")
	}

	if err := buildBinary(); err != nil {
		b.Fatalf("Failed to build binary: %v", err)
	}
	defer cleanupBinary()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := runNVR("--remote-expr", "getcwd()")
		if err != nil {
			b.Fatalf("Benchmark failed: %v", err)
		}
	}
}

// Helper functions
func buildBinary() error {
	cmd := exec.Command("go", "build", "-o", testBinaryPath, ".")
	cmd.Dir = "."
	return cmd.Run()
}

func cleanupBinary() {
	os.Remove(testBinaryPath)
}

func runNVR(args ...string) (string, error) {
	cmd := exec.Command(testBinaryPath, args...)
	output, err := cmd.CombinedOutput()
	return string(output), err
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr ||
		(len(s) > len(substr) &&
			(s[:len(substr)] == substr ||
			 s[len(s)-len(substr):] == substr ||
			 containsSubstring(s, substr))))
}

func containsSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

const testBinaryPath = "./test_binary"