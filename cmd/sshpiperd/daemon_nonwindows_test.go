//go:build !windows

package main

import (
	"os"
	"testing"
)

func makeTestFileUnreadable(t *testing.T, path string) {
	t.Helper()
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.Chmod(path, 0o600); err != nil {
			t.Error(err)
		}
	})
	if _, err := os.ReadFile(path); err == nil {
		t.Skip("current user can read files despite mode 000 (for example, root)")
	}
}
