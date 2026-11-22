package ui

import (
	"reflect"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/charmbracelet/x/ansi"
)

func setup(o Options) Model {
	var m tea.Model = New(o)
	m, _ = m.Update(tea.WindowSizeMsg{Width: 150, Height: 42})
	m, _ = m.Update(snapMsg{snap: sampleSnap()})
	return m.(Model)
}

func k(m Model, keys ...string) Model {
	for _, key := range keys {
		tm, _ := m.key(key)
		m = tm.(Model)
	}
	return m
}

func TestMergeFlow(t *testing.T) {
	var calls []int
	m := setup(Options{Repo: "DSestu/NixConfig", Merge: func(num int, sha string, stacked bool) (model.MergeResult, error) {
		calls = append(calls, num)
		if num == 297 {
			return model.MergeResult{Status: "failed", Message: "Merge conflict"}, nil
		}
		return model.MergeResult{Status: "merged"}, nil
	}})
	// rows: 297 290 273 274 275 271; mark 297, then 274 (implies 273), and 290 (conflicting)
	m = k(m, "space", "j", "space", "j", "j", "space")
	if !reflect.DeepEqual(m.marked, map[int]bool{297: true, 290: true, 273: true, 274: true}) {
		t.Fatalf("marked %v", m.marked)
	}
	bar := ansi.Strip(m.mergeBar())
	if !strings.Contains(bar, "4 marked") || !strings.Contains(bar, "#290 conflicts") {
		t.Errorf("merge bar %q", bar)
	}

	m = k(m, "M")
	out := m.View().Content
	plain := ansi.Strip(out)
	for _, want := range []string{"Squash-merge 3 PRs into DSestu/NixConfig", "#274", "stack: lands #273 #274 together", "#297", "Skipped:", "#290 conflicts", "y  squash-merge 3 PRs", "no checks · → main"} {
		if !strings.Contains(plain, want) {
			t.Errorf("dialog missing %q", want)
		}
	}
	for i, l := range strings.Split(out, "\n") {
		if w := ansi.StringWidth(l); w != 150 {
			t.Errorf("dialog line %d is %d wide", i, w)
		}
	}

	var tm tea.Model = m
	tm, cmd := tm.Update(tea.KeyPressMsg(tea.Key{Text: "y", Code: 'y'}))
	for cmd != nil { // run each merge step to completion
		tm, cmd = tm.Update(cmd())
	}
	m = tm.(Model)
	if !reflect.DeepEqual(calls, []int{274, 297}) {
		t.Fatalf("merge calls %v, want stack (on 274) then 297", calls)
	}
	plain = ansi.Strip(m.View().Content)
	if !strings.Contains(plain, "1 merged") || !strings.Contains(plain, "1 failed") || !strings.Contains(plain, "Merge conflict") {
		t.Errorf("summary missing: %s", plain)
	}
	tm, cmd = m.Update(tea.KeyPressMsg(tea.Key{Code: tea.KeyEnter}))
	if m = tm.(Model); m.merge.phase != phaseNone || len(m.marked) != 0 || cmd == nil || !m.loading {
		t.Errorf("enter should close, clear marks and refresh")
	}
}

func TestMergeBlockedOutsideDSestu(t *testing.T) {
	m := setup(Options{Repo: "sencrop/x", MergeBlocked: "merging is disabled outside DSestu repos (this is sencrop/x)"})
	m = k(m, "space", "M")
	if m.merge.phase != phaseNone || !strings.Contains(ansi.Strip(m.mergeBar()), "disabled outside DSestu") {
		t.Errorf("M must refuse: phase %v bar %q", m.merge.phase, ansi.Strip(m.mergeBar()))
	}
}

func TestDryRunMergesNothing(t *testing.T) {
	m := setup(Options{Repo: "DSestu/NixConfig", DryRun: true})
	var tm tea.Model = k(m, "a", "M")
	tm, cmd := tm.Update(tea.KeyPressMsg(tea.Key{Text: "y", Code: 'y'}))
	if cmd != nil || tm.(Model).merge.phase != phaseDone {
		t.Fatal("dry run must not start merging")
	}
	if !strings.Contains(ansi.Strip(tm.(Model).View().Content), "dry run: nothing was merged") {
		t.Error("dry run summary missing")
	}
}

func TestMouse(t *testing.T) {
	m := setup(Options{Repo: "o/r"})
	// table body: y=2 is the column header, y=3 the first row (#297), y=4 #290
	var tm tea.Model = m
	tm, _ = tm.Update(tea.MouseClickMsg{X: 22, Y: 4, Button: tea.MouseLeft})
	if m = tm.(Model); m.selNum != 290 || len(m.marked) != 1 || !m.marked[290] {
		t.Fatalf("click on mark column: sel #%d marked %v", m.selNum, m.marked)
	}
	tm, _ = tm.Update(tea.MouseClickMsg{X: 60, Y: 5, Button: tea.MouseLeft})
	if m = tm.(Model); m.selNum != 273 || len(m.marked) != 1 {
		t.Fatalf("click on title selects only: sel #%d marked %v", m.selNum, m.marked)
	}
	tm, _ = tm.Update(tea.MouseClickMsg{X: 5, Y: 2 + int(model.Bumps), Button: tea.MouseLeft})
	if m = tm.(Model); m.section != model.Bumps || len(m.rows) != 2 || m.focus != focusRail {
		t.Fatalf("rail click: section %v rows %d", m.section, len(m.rows))
	}
	tm, _ = tm.Update(tea.MouseClickMsg{X: 5, Y: 2 + int(model.Marked) + 1, Button: tea.MouseLeft})
	if tm.(Model).section != model.Marked {
		t.Fatal("click below the separator should pick Marked")
	}
	tm, _ = tm.Update(tea.MouseWheelMsg{X: 60, Y: 10, Button: tea.MouseWheelDown})
	if tm.(Model).focus != focusRail {
		t.Fatal("wheel must not move focus")
	}
}

func TestMergeOne(t *testing.T) {
	var calls []int
	m := setup(Options{Repo: "DSestu/NixConfig", Merge: func(num int, sha string, stacked bool) (model.MergeResult, error) {
		calls = append(calls, num)
		return model.MergeResult{Status: "merged"}, nil
	}})
	// mark #297, then put the cursor on #274 (rows: 297 290 273 274 …) and press m
	m = k(m, "space", "j", "j", "j", "m")
	plain := ansi.Strip(m.View().Content)
	if !strings.Contains(plain, "Squash-merge 2 PRs") || !strings.Contains(plain, "stack: lands #273 #274 together") {
		t.Errorf("m should plan only the cursor PR and the stack below it:\n%s", plain)
	}
	var tm tea.Model = m
	tm, cmd := tm.Update(tea.KeyPressMsg(tea.Key{Text: "y", Code: 'y'}))
	for cmd != nil {
		tm, cmd = tm.Update(cmd())
	}
	if !reflect.DeepEqual(calls, []int{274}) {
		t.Fatalf("calls %v, want [274]", calls)
	}
	tm, _ = tm.Update(tea.KeyPressMsg(tea.Key{Code: tea.KeyEnter}))
	if !tm.(Model).marked[297] {
		t.Error("m must not clear the marks of other PRs")
	}
}
