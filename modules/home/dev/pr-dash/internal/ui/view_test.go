package ui

import (
	"os"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/charmbracelet/x/ansi"
)

var now = time.Date(2026, 11, 22, 12, 0, 0, 0, time.UTC)

func sampleSnap() model.Snapshot {
	return model.Snapshot{Viewer: "DSestu", PRs: []model.PR{
		{Number: 297, Title: "❄️ flake: nix-claude-code (claude 2.1.326 → 2.1.330) with a very long tail that must be cut", Author: "github-actions", Mergeable: "MERGEABLE", CreatedAt: now.Add(-22 * time.Hour), Additions: 3, Deletions: 3, BaseRef: "main", HeadRef: "flake/x"},
		{Number: 290, Title: "❄️ flake: disko", Author: "github-actions", Mergeable: "CONFLICTING", CreatedAt: now.Add(-48 * time.Hour)},
		{Number: 275, Title: "✨ agents: add pr-dash module", Author: "DSestu", StackID: 7, StackSize: 3, StackPos: 3, CheckRollup: "PENDING", Mergeable: "MERGEABLE", MergeState: "BLOCKED",
			Body: "## Summary\n\nAdds **pr-dash**, a `bubbletea` TUI.\n\n- one\n- two\n", CreatedAt: now.Add(-2 * time.Hour),
			Checks:   []model.Check{{Name: "nix flake check", State: model.CheckPass, Duration: 134 * time.Second}, {Name: "vm-bare-test", State: model.CheckPending}},
			Comments: []model.Comment{{Author: "octocat", Body: "Looks good, but vm-bare-test is still running so ignore it until it settles.", CreatedAt: now.Add(-time.Hour)}}},
		{Number: 273, Title: "gh-dash: drop config", Author: "DSestu", StackID: 7, StackSize: 3, StackPos: 1, CheckRollup: "SUCCESS", CreatedAt: now.Add(-24 * time.Hour)},
		{Number: 274, Title: "modules: split dev/", Author: "DSestu", StackID: 7, StackSize: 3, StackPos: 2, CheckRollup: "SUCCESS", CreatedAt: now.Add(-24 * time.Hour)},
		{Number: 271, Title: "🌐 browsers: add Zen", Author: "octocat", CheckRollup: "FAILURE", IsDraft: true, CreatedAt: now.Add(-8 * 24 * time.Hour)},
	}}
}

func render(t *testing.T, w, h int, keys ...string) string {
	t.Helper()
	var m tea.Model = New(Options{Repo: "DSestu/NixConfig"})
	m, _ = m.Update(tea.WindowSizeMsg{Width: w, Height: h})
	m, _ = m.Update(snapMsg{snap: sampleSnap()})
	mm := m.(Model)
	mm.now, mm.next, mm.fetched = now, now.Add(time.Minute), now
	m = mm
	for _, k := range keys {
		m, _ = m.(Model).key(k)
	}
	return m.(Model).View().Content
}

func TestViewFitsExactly(t *testing.T) {
	out := render(t, 150, 42)
	lines := strings.Split(out, "\n")
	if len(lines) != 42 {
		t.Fatalf("%d lines, want 42", len(lines))
	}
	for i, l := range lines {
		if w := ansi.StringWidth(l); w != 150 {
			t.Errorf("line %d is %d cells wide: %q", i, w, ansi.Strip(l))
		}
	}
	plain := ansi.Strip(out)
	for _, want := range []string{"├ gh-dash: drop config", "├ modules: split dev/", "└ ✦ agents: add pr-dash", " 1/3 ", " 3/3 ", " failing ", " conflict ", "#297 * flake"} {
		if !strings.Contains(plain, want) {
			t.Errorf("missing %q", want)
		}
	}
	if os.Getenv("PRDASH_SHOW") != "" {
		t.Log("\n" + plain)
	}
}

func TestPreviewAndSections(t *testing.T) {
	// cursor to #275 (rows: 297 290 273 274 275 271), then the Stacks section
	plain := ansi.Strip(render(t, 150, 42, "j", "j", "j", "j"))
	for _, want := range []string{"Checks 1/2", "nix flake check", "2m14s", "running", "Summary", "octocat", "blocked", "3/3 · stack 7"} {
		if !strings.Contains(plain, want) {
			t.Errorf("preview missing %q", want)
		}
	}
	stacks := ansi.Strip(render(t, 150, 42, "shift+tab", "j", "j", "j"))
	if !strings.Contains(stacks, "3 PRs ·") || strings.Contains(stacks, "#297") {
		t.Errorf("Stacks section should show only the 3 stacked PRs")
	}
}
