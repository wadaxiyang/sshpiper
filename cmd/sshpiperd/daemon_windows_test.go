//go:build windows

package main

import (
	"testing"

	"golang.org/x/sys/windows"
)

func makeTestFileUnreadable(t *testing.T, path string) {
	t.Helper()
	name, err := windows.UTF16PtrFromString(path)
	if err != nil {
		t.Fatal(err)
	}
	// Windows ignores Unix read permission bits. Deny sharing instead, so
	// loadHostKeys exercises a real file-open error without changing any ACLs.
	handle, err := windows.CreateFile(name, windows.GENERIC_READ, 0, nil, windows.OPEN_EXISTING, windows.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := windows.CloseHandle(handle); err != nil {
			t.Error(err)
		}
	})
}
