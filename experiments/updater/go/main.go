package main

import (
	"fmt"
	"os"
)

const usage = "usage: downgrade-guard [--allow-downgrade] <current-version> <selected-ref>"

func main() {
	args := os.Args[1:]
	allowDowngrade := false
	if len(args) > 0 && args[0] == "--allow-downgrade" {
		allowDowngrade = true
		args = args[1:]
	}
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	if Allows(args[0], args[1], allowDowngrade) {
		fmt.Println("allow")
		return
	}
	fmt.Println("block")
	os.Exit(1)
}
