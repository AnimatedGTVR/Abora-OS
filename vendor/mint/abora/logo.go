package abora

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// Run renders the Abora OS logo without writing to stdout.
func (o LogoOptions) Run() error {
	if o.Doctor {
		return logoDoctor(o.Path)
	}
	return renderLogo(o.Path, o.Width, o.Mode, o.Quality, !o.NoFallback)
}

func renderLogo(path, width, mode, quality string, fallback bool) error {
	if _, err := os.Stat(path); err != nil {
		if fallback {
			renderLogoFallback(fmt.Sprintf("logo not found: %s", path))
			return nil
		}
		return fmt.Errorf("logo not found: %w", err)
	}

	terminal := currentTerminalInfo()
	if terminal.isLinuxTTY() {
		switch mode {
		case "", "auto", "tty", "pixels", "kitty", "iterm", "sixel":
			if mode != "" && mode != "auto" && mode != "tty" && !fallback {
				return fmt.Errorf("Linux TTY does not support inline terminal image protocols; use --mode tty or --mode chafa")
			}
			if mode != "" && mode != "auto" && mode != "tty" {
				fmt.Fprintln(os.Stderr, mutedStyle.Render("Linux TTY does not support inline terminal images; using TTY-safe logo art."))
			}
			return renderLogoWithRenderers(path, width, quality, fallback, []logoRenderer{renderChafaTTY, renderTTYBlocks, renderANSIBlocks}, "TTY logo renderer unavailable")
		}
	}
	if terminal.isAlacritty() {
		switch mode {
		case "", "auto":
			return renderLogoWithRenderers(path, width, quality, fallback, []logoRenderer{renderChafa, renderANSIBlocks}, "Alacritty terminal image fallback unavailable")
		case "pixels", "kitty", "iterm", "sixel":
			if !fallback {
				return fmt.Errorf("Alacritty does not support inline terminal image protocols; use --mode open or --mode chafa")
			}
			fmt.Fprintln(os.Stderr, mutedStyle.Render("Alacritty does not support inline terminal images; using chafa terminal art. Use --mode open for the real PNG."))
			return renderLogoWithRenderers(path, width, quality, fallback, []logoRenderer{renderChafa, renderANSIBlocks}, "Alacritty does not support inline terminal images")
		}
	}

	renderers := logoRenderers(mode)
	if len(renderers) == 0 {
		return fmt.Errorf("unsupported logo render mode %q", mode)
	}

	return renderLogoWithRenderers(path, width, quality, fallback, renderers, "terminal image renderer unavailable")
}

type logoRenderer func(string, string, string) ([]byte, error)

func renderLogoWithRenderers(path, width, quality string, fallback bool, renderers []logoRenderer, fallbackReason string) error {
	for _, renderer := range renderers {
		out, err := renderer(path, width, quality)
		if err == nil && len(out) > 0 {
			_, _ = os.Stderr.Write(out)
			fmt.Fprintln(os.Stderr)
			return nil
		}
	}

	if fallback {
		renderLogoFallback(fallbackReason)
		return nil
	}

	return fmt.Errorf("no supported terminal image renderer found")
}

func logoRenderers(mode string) []logoRenderer {
	switch mode {
	case "", "auto":
		return []logoRenderer{renderChafaKitty, renderChafaSixel, renderChafaITerm, renderChafa}
	case "pixels":
		return []logoRenderer{renderChafaKitty, renderChafaSixel, renderChafaITerm}
	case "kitty":
		return []logoRenderer{renderChafaKitty}
	case "iterm":
		return []logoRenderer{renderChafaITerm}
	case "chafa":
		return []logoRenderer{renderChafa}
	case "ansi":
		return []logoRenderer{renderANSIBlocks}
	case "sixel":
		return []logoRenderer{renderMagickSixel, renderSixel}
	case "tty":
		return []logoRenderer{renderChafaTTY, renderTTYBlocks, renderANSIBlocks}
	case "text":
		return nil
	case "open":
		return []logoRenderer{renderOpen}
	default:
		return nil
	}
}

type terminalInfo struct {
	Term              string
	TermProgram       string
	KittyWindowID     string
	WeztermExecutable string
}

func currentTerminalInfo() terminalInfo {
	return terminalInfo{
		Term:              os.Getenv("TERM"),
		TermProgram:       os.Getenv("TERM_PROGRAM"),
		KittyWindowID:     os.Getenv("KITTY_WINDOW_ID"),
		WeztermExecutable: os.Getenv("WEZTERM_EXECUTABLE"),
	}
}

func (t terminalInfo) isAlacritty() bool {
	return strings.Contains(strings.ToLower(t.Term), "alacritty") ||
		strings.Contains(strings.ToLower(t.TermProgram), "alacritty")
}

func (t terminalInfo) isLinuxTTY() bool {
	return t.Term == "linux" || strings.HasPrefix(t.Term, "con") || strings.HasPrefix(t.Term, "vt")
}

func (t terminalInfo) imageSupportSummary() string {
	switch {
	case t.isLinuxTTY():
		return "no (Linux TTY supports ANSI text art, not inline graphics)"
	case t.isAlacritty():
		return "no (Alacritty ignores Kitty/sixel/iTerm inline graphics)"
	case t.KittyWindowID != "" || strings.Contains(strings.ToLower(t.Term), "xterm-kitty"):
		return "yes (Kitty graphics)"
	case t.WeztermExecutable != "":
		return "maybe (WezTerm; try --mode kitty or --mode sixel)"
	case strings.Contains(strings.ToLower(t.TermProgram), "iterm"):
		return "yes (iTerm graphics)"
	default:
		return "unknown"
	}
}

var magickPixel = regexp.MustCompile(`^\d+,\d+: \((\d+),(\d+),(\d+),([0-9.]+)`)
var magickPixelWithXY = regexp.MustCompile(`^(\d+),(\d+): \(([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)`)
var magickHeader = regexp.MustCompile(`^# ImageMagick pixel enumeration: (\d+),(\d+),`)

func renderTTYBlocks(path, width, quality string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	img, _, err := image.Decode(file)
	if err != nil {
		return nil, err
	}

	bounds := img.Bounds()
	srcWidth := bounds.Dx()
	srcHeight := bounds.Dy()
	if srcWidth <= 0 || srcHeight <= 0 {
		return nil, fmt.Errorf("empty image")
	}

	columns := ttyColumns(width)
	rows := max(1, int(float64(columns)*float64(srcHeight)/float64(srcWidth)/2.0))

	var buf bytes.Buffer
	for y := 0; y < rows; y++ {
		for x := 0; x < columns; x++ {
			sx := bounds.Min.X + x*srcWidth/columns
			sy := bounds.Min.Y + y*2*srcHeight/(rows*2)
			r, g, b, a := img.At(sx, sy).RGBA()
			if a < 0x2000 {
				buf.WriteByte(' ')
				continue
			}
			fmt.Fprintf(&buf, "\x1b[%dm ", ansi16Background(color.RGBA{
				R: uint8(r >> 8),
				G: uint8(g >> 8),
				B: uint8(b >> 8),
				A: uint8(a >> 8),
			}))
		}
		buf.WriteString("\x1b[0m\n")
	}
	return bytes.TrimRight(buf.Bytes(), "\n"), nil
}

func ttyColumns(width string) int {
	width = strings.TrimSpace(strings.TrimSuffix(width, "px"))
	if width == "" || width == "auto" {
		return 72
	}
	if strings.Contains(width, "x") {
		width, _, _ = strings.Cut(width, "x")
	}
	columns, err := strconv.Atoi(width)
	if err != nil || columns <= 0 {
		return 72
	}
	if columns > 120 {
		return 120
	}
	return columns
}

func logoColumns(width string) int {
	columns := ttyColumns(width)
	if columns > 96 {
		return 96
	}
	return columns
}

func ansi16Background(c color.RGBA) int {
	palette := []color.RGBA{
		{0, 0, 0, 255}, {170, 0, 0, 255}, {0, 170, 0, 255}, {170, 85, 0, 255},
		{0, 0, 170, 255}, {170, 0, 170, 255}, {0, 170, 170, 255}, {170, 170, 170, 255},
		{85, 85, 85, 255}, {255, 85, 85, 255}, {85, 255, 85, 255}, {255, 255, 85, 255},
		{85, 85, 255, 255}, {255, 85, 255, 255}, {85, 255, 255, 255}, {255, 255, 255, 255},
	}
	bestIndex := 0
	bestDistance := int(^uint(0) >> 1)
	for i, p := range palette {
		dr := int(c.R) - int(p.R)
		dg := int(c.G) - int(p.G)
		db := int(c.B) - int(p.B)
		distance := dr*dr + dg*dg + db*db
		if distance < bestDistance {
			bestIndex = i
			bestDistance = distance
		}
	}
	if bestIndex < 8 {
		return 40 + bestIndex
	}
	return 100 + bestIndex - 8
}

func renderANSIBlocks(path, width, quality string) ([]byte, error) {
	if _, err := exec.LookPath("magick"); err != nil {
		return nil, err
	}

	out, err := exec.Command("magick", path, "-trim", "+repage", "-background", "none", "-resize", ansiWidth(width), "txt:-").Output()
	if err != nil {
		return nil, err
	}

	if rendered := renderHalfBlocks(string(out)); len(rendered) > 0 {
		return rendered, nil
	}

	var buf bytes.Buffer
	lastY := 0
	seenPixel := false
	for _, line := range strings.Split(string(out), "\n") {
		match := magickPixel.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		xy, _, _ := strings.Cut(line, ":")
		_, yText, _ := strings.Cut(xy, ",")
		y, _ := strconv.Atoi(yText)
		for seenPixel && y > lastY {
			buf.WriteString("\x1b[0m\n")
			lastY++
		}
		seenPixel = true
		lastY = y

		r, _ := strconv.Atoi(match[1])
		g, _ := strconv.Atoi(match[2])
		b, _ := strconv.Atoi(match[3])
		alpha, _ := strconv.ParseFloat(match[4], 64)
		if alpha <= 0 {
			buf.WriteByte(' ')
			continue
		}
		fmt.Fprintf(&buf, "\x1b[48;2;%d;%d;%dm ", r, g, b)
	}
	if seenPixel {
		buf.WriteString("\x1b[0m")
	}
	return buf.Bytes(), nil
}

type ansiPixel struct {
	r, g, b int
	opaque  bool
}

func renderHalfBlocks(txt string) []byte {
	lines := strings.Split(txt, "\n")
	if len(lines) == 0 {
		return nil
	}

	header := magickHeader.FindStringSubmatch(lines[0])
	if header == nil {
		return nil
	}
	width, _ := strconv.Atoi(header[1])
	height, _ := strconv.Atoi(header[2])
	if width <= 0 || height <= 0 {
		return nil
	}

	pixels := make([]ansiPixel, width*height)
	for _, line := range lines[1:] {
		match := magickPixelWithXY.FindStringSubmatch(line)
		if match == nil {
			continue
		}
		x, _ := strconv.Atoi(match[1])
		y, _ := strconv.Atoi(match[2])
		if x < 0 || x >= width || y < 0 || y >= height {
			continue
		}
		alpha := parseChannel(match[6])
		if alpha < 48 {
			continue
		}
		pixels[y*width+x] = ansiPixel{
			r:      parseChannel(match[3]),
			g:      parseChannel(match[4]),
			b:      parseChannel(match[5]),
			opaque: true,
		}
	}

	var buf bytes.Buffer
	for y := 0; y < height; y += 2 {
		for x := 0; x < width; x++ {
			top := pixels[y*width+x]
			bottom := ansiPixel{}
			if y+1 < height {
				bottom = pixels[(y+1)*width+x]
			}
			switch {
			case top.opaque && bottom.opaque:
				fmt.Fprintf(&buf, "\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm▀", top.r, top.g, top.b, bottom.r, bottom.g, bottom.b)
			case top.opaque:
				fmt.Fprintf(&buf, "\x1b[38;2;%d;%d;%dm▀", top.r, top.g, top.b)
			case bottom.opaque:
				fmt.Fprintf(&buf, "\x1b[38;2;%d;%d;%dm▄", bottom.r, bottom.g, bottom.b)
			default:
				buf.WriteByte(' ')
			}
		}
		buf.WriteString("\x1b[0m\n")
	}
	return bytes.TrimRight(buf.Bytes(), "\n")
}

func parseChannel(value string) int {
	f, _ := strconv.ParseFloat(value, 64)
	switch {
	case f < 0:
		return 0
	case f > 255:
		return 255
	default:
		return int(f + 0.5)
	}
}

func renderSixel(path, width, quality string) ([]byte, error) {
	if _, err := exec.LookPath("img2sixel"); err != nil {
		return nil, err
	}
	return exec.Command("img2sixel", "--width", width, path).Output()
}

func ansiWidth(width string) string {
	width = strings.TrimSpace(strings.TrimSuffix(width, "px"))
	if width == "" || width == "auto" {
		return "80x"
	}
	if strings.Contains(width, "x") || strings.HasSuffix(width, "%") {
		return width
	}
	return width + "x"
}

func renderMagickSixel(path, width, quality string) ([]byte, error) {
	if _, err := exec.LookPath("magick"); err != nil {
		return nil, err
	}
	return exec.Command("magick", path, "-background", "none", "-resize", magickWidth(width), "sixel:-").Output()
}

func renderChafa(path, width, quality string) ([]byte, error) {
	return renderChafaSymbols(path, width, quality, "full")
}

func renderChafaTTY(path, width, quality string) ([]byte, error) {
	return renderChafaSymbols(path, width, quality, "16")
}

func renderChafaSymbols(path, width, quality, colors string) ([]byte, error) {
	if _, err := exec.LookPath("chafa"); err != nil {
		return nil, err
	}
	symbols := "half"
	threshold := "0.25"
	work := "5"
	if quality == "2k" {
		threshold = "0.12"
		work = "9"
	}
	return exec.Command(
		"chafa",
		"--format", "symbols",
		"--symbols", symbols,
		"--colors", colors,
		"--dither", "none",
		"--work", work,
		"--threshold", threshold,
		"--size", chafaSize(width),
		path,
	).Output()
}

func renderChafaKitty(path, width, quality string) ([]byte, error) {
	return renderChafaGraphics("kitty", path, width)
}

func renderChafaITerm(path, width, quality string) ([]byte, error) {
	return renderChafaGraphics("iterm", path, width)
}

func renderChafaSixel(path, width, quality string) ([]byte, error) {
	return renderChafaGraphics("sixels", path, width)
}

func renderChafaGraphics(format, path, width string) ([]byte, error) {
	if _, err := exec.LookPath("chafa"); err != nil {
		return nil, err
	}
	return exec.Command(
		"chafa",
		"--format", format,
		"--passthrough", "auto",
		"--polite", "on",
		"--size", chafaSize(width),
		path,
	).Output()
}

func chafaSize(width string) string {
	width = strings.TrimSpace(strings.TrimSuffix(width, "px"))
	if width == "" || width == "auto" {
		return "72x"
	}
	if strings.Contains(width, "x") {
		columns, rows, _ := strings.Cut(width, "x")
		columns = strconv.Itoa(logoColumns(columns))
		if rows == "" {
			return columns + "x"
		}
		return columns + "x" + rows
	}
	return strconv.Itoa(logoColumns(width)) + "x"
}

func magickWidth(width string) string {
	width = strings.TrimSpace(strings.TrimSuffix(width, "px"))
	if width == "" || width == "auto" {
		return "520x"
	}
	if strings.Contains(width, "x") || strings.HasSuffix(width, "%") {
		return width
	}
	return width + "x"
}

func renderViu(path, width, quality string) ([]byte, error) {
	if _, err := exec.LookPath("viu"); err != nil {
		return nil, err
	}
	return exec.Command("viu", "-w", "72", path).Output()
}

func renderOpen(path, width, quality string) ([]byte, error) {
	for _, opener := range []string{"xdg-open", "gio"} {
		if _, err := exec.LookPath(opener); err != nil {
			continue
		}
		var cmd *exec.Cmd
		if opener == "gio" {
			cmd = exec.Command(opener, "open", path)
		} else {
			cmd = exec.Command(opener, path)
		}
		if err := cmd.Start(); err != nil {
			return nil, err
		}
		return []byte(mutedStyle.Render("Opened logo in external image viewer.")), nil
	}
	return nil, fmt.Errorf("no external image opener found")
}

func logoDoctor(path string) error {
	terminal := currentTerminalInfo()
	rows := []string{
		titleStyle.Render("MINT Logo Renderer Doctor"),
		"",
		kv("Logo", path),
		kv("TERM", terminal.Term),
		kv("TERM_PROGRAM", terminal.TermProgram),
		kv("Inline images", terminal.imageSupportSummary()),
		kv("KITTY", present(terminal.KittyWindowID != "")),
		kv("WEZTERM", present(terminal.WeztermExecutable != "")),
		kv("Tools", toolList()),
		"",
		mutedStyle.Render("Real terminal images require Kitty, iTerm2, or sixel support."),
		mutedStyle.Render("Alacritty users should use --mode open for the real PNG."),
		mutedStyle.Render("Use --mode open for a real image viewer, or --mode chafa for terminal art."),
	}
	fmt.Fprintln(os.Stderr, panelStyle.Width(76).Render(strings.Join(rows, "\n")))
	return nil
}

func toolList() string {
	var found []string
	for _, tool := range []string{"chafa", "img2sixel", "magick", "xdg-open", "gio", "viu"} {
		if _, err := exec.LookPath(tool); err == nil {
			found = append(found, tool)
		}
	}
	if len(found) == 0 {
		return "none"
	}
	return strings.Join(found, ", ")
}

func present(ok bool) string {
	if ok {
		return "yes"
	}
	return "no"
}

func renderLogoFallback(reason string) {
	fmt.Fprintln(os.Stderr, panelStyle.Width(58).Render(
		titleStyle.Render("ABORA OS")+"\n\n"+
			mutedStyle.Render(reason),
	))
}
