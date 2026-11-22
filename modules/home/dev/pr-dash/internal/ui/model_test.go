package ui

import (
	"errors"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
)

func TestRefreshSchedule(t *testing.T) {
	var m tea.Model = New(Options{Repo: "o/r"})
	unknown := model.Snapshot{PRs: []model.PR{{Number: 1, Mergeable: "UNKNOWN"}, {Number: 2, Mergeable: "MERGEABLE"}}}

	m, _ = m.Update(snapMsg{snap: unknown})
	if d := m.(Model).next.Sub(m.(Model).now); d != recheckAfter {
		t.Fatalf("UNKNOWN mergeable: next refresh in %v, want %v", d, recheckAfter)
	}
	m, _ = m.Update(snapMsg{snap: unknown}) // still UNKNOWN: no second quick retry
	if d := m.(Model).next.Sub(m.(Model).now); d != refreshEvery {
		t.Fatalf("second fetch: next refresh in %v, want %v", d, refreshEvery)
	}

	// cursor on #2 survives a refresh that reorders rows
	m, _ = m.Update(tea.WindowSizeMsg{Width: 150, Height: 42})
	m, _ = m.(Model).key("j")
	if m.(Model).selNum != 1 {
		t.Fatalf("rows ordered newest first; after j expected #1, got #%d", m.(Model).selNum)
	}
	m, _ = m.Update(snapMsg{snap: model.Snapshot{PRs: []model.PR{{Number: 3}, {Number: 2}, {Number: 1}}}})
	if m.(Model).selNum != 1 || m.(Model).cursor != 2 {
		t.Fatalf("cursor did not follow #1: sel #%d at %d", m.(Model).selNum, m.(Model).cursor)
	}

	// a failed fetch keeps the old data and shows the error
	m, _ = m.Update(snapMsg{err: errors.New("network down")})
	if len(m.(Model).snap.PRs) != 3 || m.(Model).err == nil || m.(Model).loading {
		t.Fatalf("error should keep data: %d PRs, err %v", len(m.(Model).snap.PRs), m.(Model).err)
	}

	// tick past the deadline starts a fetch
	mm := m.(Model)
	m, cmd := mm.Update(tickMsg(mm.next.Add(time.Second)))
	if !m.(Model).loading || cmd == nil {
		t.Fatal("tick past next should start a refresh")
	}
}
