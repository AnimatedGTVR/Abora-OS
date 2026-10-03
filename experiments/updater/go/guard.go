package main

import (
	"math"
	"regexp"
	"strconv"
	"strings"
)

// Spec: experiments/updater/shared/README.md

var leadingNumeric = regexp.MustCompile(`^([0-9]+(?:\.[0-9]+)*)`)

// TagBaseVersion strips one leading "v" and any non-numeric suffix ("v4.1-DEMO2" -> "4.1").
func TagBaseVersion(tag string) string {
	stripped := strings.TrimPrefix(tag, "v")
	if match := leadingNumeric.FindStringSubmatch(stripped); match != nil {
		return match[1]
	}
	return stripped
}

// numericParts returns the parsed parts, or ok=false if any part is not a 32-bit decimal integer.
func numericParts(version string) (parts []int, ok bool) {
	if version == "" {
		return nil, false
	}
	for _, field := range strings.Split(version, ".") {
		if field == "" || strings.Trim(field, "0123456789") != "" {
			return nil, false
		}
		value, err := strconv.ParseInt(field, 10, 64)
		if err != nil || value > math.MaxInt32 {
			return nil, false
		}
		parts = append(parts, int(value))
	}
	return parts, true
}

// CompareDottedVersions orders numeric versions before non-numeric refs.
func CompareDottedVersions(a, b string) int {
	aParts, aNumeric := numericParts(a)
	bParts, bNumeric := numericParts(b)
	switch {
	case aNumeric != bNumeric:
		if aNumeric {
			return -1
		}
		return 1
	case !aNumeric:
		return strings.Compare(a, b)
	}
	for i := 0; i < max(len(aParts), len(bParts)); i++ {
		av, bv := partAt(aParts, i), partAt(bParts, i)
		if av != bv {
			if av < bv {
				return -1
			}
			return 1
		}
	}
	return 0
}

func partAt(parts []int, i int) int {
	if i < len(parts) {
		return parts[i]
	}
	return 0
}

func VersionLessThan(a, b string) bool {
	return a != b && CompareDottedVersions(a, b) < 0
}

// Allows reports whether updating from current to selectedRef may proceed.
func Allows(current, selectedRef string, allowDowngrade bool) bool {
	if selectedRef == "edge" || allowDowngrade {
		return true
	}
	return !VersionLessThan(TagBaseVersion(selectedRef), current)
}
