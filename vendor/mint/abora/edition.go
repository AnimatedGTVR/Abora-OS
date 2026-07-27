package abora

import (
	"fmt"
	"strings"
)

// Run prints or interactively selects an Abora OS edition id.
func (o EditionOptions) Run() error {
	if o.Recommended {
		fmt.Println("cosmic")
		return nil
	}

	if o.List {
		fmt.Println(panelStyle.Width(84).Render(lipglossEditionList()))
		return nil
	}

	return editionPicker(o.Header).Run()
}

func lipglossEditionList() string {
	rows := []string{titleStyle.Render("Abora OS Editions"), ""}
	for _, edition := range editions {
		rows = append(rows, kv(edition.ID, fmt.Sprintf("%-20s", edition.Label))+"  "+mutedStyle.Render(edition.Description))
	}
	return strings.Join(rows, "\n")
}
