package ui

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/charmbracelet/x/ansi"
)

func TestNarrowLayout(t *testing.T) {
	for _, size := range [][2]int{{109, 30}, {80, 24}, {110, 30}} {
		out := render(t, size[0], size[1])
		lines := strings.Split(out, "\n")
		if len(lines) != size[1] {
			t.Fatalf("%dx%d: %d lines", size[0], size[1], len(lines))
		}
		for i, l := range lines {
			if w := ansi.StringWidth(l); w != size[0] {
				t.Errorf("%dx%d line %d is %d wide: %q", size[0], size[1], i, w, ansi.Strip(l))
			}
		}
		collapsed := !strings.Contains(ansi.Strip(out), "Sections")
		if collapsed != (size[0] < narrowW) {
			t.Errorf("%d cols: rail collapsed=%v", size[0], collapsed)
		}
	}
	plain := ansi.Strip(render(t, 100, 30, "]", "]"))
	if !strings.Contains(plain, "‹ Bumps 2 ›") {
		t.Errorf("] should switch to Bumps in the table title:\n%s", plain[:300])
	}
	m := setup(Options{Repo: "o/r"})
	tm, _ := m.Update(tea.WindowSizeMsg{Width: 100, Height: 30})
	for i := 0; i < 3; i++ {
		tm, _ = tm.(Model).key("tab")
		if tm.(Model).focus == focusRail {
			t.Fatal("tab must skip the hidden rail")
		}
	}
}

func TestChangedRowsFade(t *testing.T) {
	m := New(Options{Repo: "o/r"})
	base := []model.PR{{Number: 1, Mergeable: "UNKNOWN", HeadSHA: "a"}, {Number: 2, Mergeable: "MERGEABLE", HeadSHA: "b"}}
	var tm tea.Model = m
	tm, _ = tm.Update(snapMsg{snap: model.Snapshot{PRs: base}})
	if len(tm.(Model).changed) != 0 {
		t.Fatal("first load must not flash")
	}
	next := []model.PR{
		{Number: 1, Mergeable: "MERGEABLE", HeadSHA: "a"},  // UNKNOWN settling: not a change
		{Number: 2, Mergeable: "MERGEABLE", HeadSHA: "b2"}, // new commits
		{Number: 3, Mergeable: "MERGEABLE", HeadSHA: "c"},  // new PR
	}
	tm, cmd := tm.Update(snapMsg{snap: model.Snapshot{PRs: next}})
	ch := tm.(Model).changed
	if _, ok := ch[1]; ok || len(ch) != 2 {
		t.Fatalf("changed %v, want 2 and 3", ch)
	}
	if cmd == nil || !tm.(Model).animating {
		t.Fatal("a fading row should start the frame ticker")
	}
	for i := 0; i < fadeFrames; i++ {
		tm, _ = tm.Update(animMsg{})
	}
	if len(tm.(Model).changed) != 0 || tm.(Model).animating {
		t.Fatalf("fade should end and the ticker stop: changed %v animating %v", tm.(Model).changed, tm.(Model).animating)
	}
}
