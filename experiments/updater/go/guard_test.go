package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// readCases loads a shared tab-separated vector file from ../shared.
func readCases(t *testing.T, name string, fields int) [][]string {
	t.Helper()
	path := filepath.Join("..", "shared", name)
	file, err := os.Open(path)
	if err != nil {
		t.Fatalf("open shared cases: %v", err)
	}
	defer file.Close()

	var cases [][]string
	scanner := bufio.NewScanner(file)
	for line := 1; scanner.Scan(); line++ {
		text := scanner.Text()
		if strings.TrimSpace(text) == "" || strings.HasPrefix(text, "#") {
			continue
		}
		row := strings.Split(text, "\t")
		if len(row) != fields {
			t.Fatalf("%s:%d: expected %d tab-separated fields, got %d", path, line, fields, len(row))
		}
		cases = append(cases, row)
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	if len(cases) == 0 {
		t.Fatalf("%s has no cases", path)
	}
	return cases
}

func TestTagBaseVersion(t *testing.T) {
	for _, row := range readCases(t, "tag-base-cases.tsv", 2) {
		tag, want := row[0], row[1]
		t.Run(fmt.Sprintf("%q", tag), func(t *testing.T) {
			if got := TagBaseVersion(tag); got != want {
				t.Errorf("TagBaseVersion(%q) = %q, want %q", tag, got, want)
			}
		})
	}
}

func TestAllows(t *testing.T) {
	for _, row := range readCases(t, "downgrade-cases.tsv", 4) {
		current, ref, allowDowngrade, want := row[0], row[1], row[2] == "yes", row[3] == "allow"
		t.Run(fmt.Sprintf("%s->%s/allow=%v", current, ref, allowDowngrade), func(t *testing.T) {
			if got := Allows(current, ref, allowDowngrade); got != want {
				t.Errorf("Allows(%q, %q, %v) = %v, want %v", current, ref, allowDowngrade, got, want)
			}
		})
	}
}
