package ui

import (
	"strings"
	"testing"

	"github.com/charmbracelet/x/ansi"
)

func TestShortURL(t *testing.T) {
	for in, want := range map[string]string{
		"https://github.com/o/r/pull/12":                         "o/r#12",
		"https://github.com/o/r/commit/f1bb834527637231e23575e":  "o/r@f1bb834",
		"https://github.com/o/r/compare/3d1aa47ec64...f1bb83452": "o/r 3d1aa47…f1bb834",
		"https://github.com/o/r":                                 "o/r",
		"https://example.com/a":                                  "example.com/a",
	} {
		if got := shortURL(in); got != want {
			t.Errorf("shortURL(%q) = %q want %q", in, got, want)
		}
	}
}

func TestRenderMarkdown(t *testing.T) {
	md := "| a | b |\n|---|---|\n| x | [5d6bdbd](https://github.com/o/r/tree/5d6bdbd) |\n\n## Inputs\n\nMoves [claude-mem](https://github.com/o/r) to latest, see https://github.com/o/r/pull/12 and <https://github.com/o/r/commit/abcdef123456>.\n\n- [`f1bb834`](https://github.com/o/r/commit/f1bb834527637231e235) fix: thing\n\n```go\nfunc main() {}\n```\n"
	out := renderMarkdown(md, 54, false)
	plain := ansi.Strip(out)
	for _, want := range []string{"Inputs", "Moves claude-mem to latest, see o/r#12 and", "o/r@abcdef1.", "\u00a0f1bb834\u00a0 fix: thing", "func main() {}"} {
		if !strings.Contains(plain, want) {
			t.Errorf("missing %q in:\n%s", want, plain)
		}
	}
	if strings.Contains(plain, "## ") || strings.Contains(plain, "https://") || strings.Contains(plain, "[1]") {
		t.Errorf("heading markers or raw URLs leaked:\n%s", plain)
	}
	if !strings.Contains(out, "\x1b]8;") {
		t.Error("links should be OSC 8 hyperlinks")
	}
	if !strings.Contains(out, "38;2;255;95;210") { // pink: chroma keyword colour for `func`
		t.Error("code block not highlighted in Charm Glow")
	}
	if first, _, _ := strings.Cut(plain, "\n"); strings.TrimSpace(first) == "" {
		t.Error("leading blank line not trimmed")
	}
	for _, l := range strings.Split(out, "\n") {
		if ansi.StringWidth(l) > 54 {
			t.Errorf("line wider than 54: %q", ansi.Strip(l))
		}
	}
}
