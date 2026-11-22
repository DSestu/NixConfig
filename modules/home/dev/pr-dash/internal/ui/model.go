// Package ui is the Bubble Tea front end. It never calls GitHub itself: all
// I/O goes through the fetch function, run inside a tea.Cmd.
package ui

import (
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
)

const (
	refreshEvery = time.Minute
	recheckAfter = 5 * time.Second // GitHub computes mergeable lazily; ask again soon
)

const (
	focusRail = iota
	focusTable
	focusPreview
	focusCount
)

type (
	snapMsg struct {
		snap model.Snapshot
		err  error
	}
	tickMsg time.Time
)

// Options wires the UI to the outside world.
type Options struct {
	Repo         string // owner/name, for the header
	Fetch        func() (model.Snapshot, error)
	Merge        func(num int, sha string, stacked bool) (model.MergeResult, error) // nil when merging is not allowed
	MergeBlocked string                                                             // why Merge is nil
	DryRun       bool                                                               // show the plan, call nothing that writes
}

type Model struct {
	Options

	snap      model.Snapshot
	err       error
	loading   bool
	fetched   time.Time
	next      time.Time // next automatic refresh
	rechecked bool      // already did one quick re-fetch for UNKNOWN mergeable
	now       time.Time

	section model.Section
	rows    []model.PR
	cursor  int // index into rows
	selNum  int // PR number under the cursor; survives refreshes
	offset  int // first visible table row
	pscroll int // preview scroll
	focus   int
	marked  map[int]bool

	w, h int

	flash string // one-line notice in the merge bar, cleared on the next key
	merge mergeState
}

func New(o Options) Model {
	return Model{Options: o, focus: focusTable, marked: map[int]bool{}, now: time.Now(), loading: true}
}

func (m Model) Init() tea.Cmd { return tea.Batch(m.refresh(), tick()) } // loading is already set in New

func tick() tea.Cmd { return tea.Tick(time.Second, func(t time.Time) tea.Msg { return tickMsg(t) }) }

func (m *Model) refresh() tea.Cmd {
	m.loading = true
	fetch := m.Fetch
	return func() tea.Msg {
		s, err := fetch()
		return snapMsg{s, err}
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		m.clamp()
	case tickMsg:
		m.now = time.Time(msg)
		if !m.loading && !m.next.IsZero() && !m.now.Before(m.next) {
			cmd := m.refresh()
			return m, tea.Batch(cmd, tick())
		}
		return m, tick()
	case snapMsg:
		m.loading = false
		m.now = time.Now()
		m.err = msg.err
		m.next = m.now.Add(refreshEvery)
		if msg.err == nil {
			m.snap, m.fetched = msg.snap, m.now
			if !m.rechecked && anyUnknown(msg.snap.PRs) {
				m.next, m.rechecked = m.now.Add(recheckAfter), true
			} else {
				m.rechecked = false
			}
			m.recompute()
		}
	case mergedMsg:
		return m.merged(msg)
	case tea.KeyPressMsg:
		if m.merge.phase != phaseNone {
			return m.mergeKey(msg.String())
		}
		m.flash = ""
		return m.key(msg.String())
	case tea.MouseClickMsg:
		if m.merge.phase == phaseNone && msg.Button == tea.MouseLeft {
			m.click(msg.X, msg.Y)
		}
	case tea.MouseWheelMsg:
		if m.merge.phase == phaseNone {
			m.wheel(msg.X, msg.Button)
		}
	}
	return m, nil
}

func anyUnknown(prs []model.PR) bool {
	for _, p := range prs {
		if p.Mergeable == "UNKNOWN" {
			return true
		}
	}
	return false
}

func (m Model) key(k string) (tea.Model, tea.Cmd) {
	switch k {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "tab":
		m.focus = (m.focus + 1) % focusCount
	case "shift+tab":
		m.focus = (m.focus + focusCount - 1) % focusCount
	case "r":
		if !m.loading {
			cmd := m.refresh()
			return m, cmd
		}
	case "j", "down":
		m.move(1)
	case "k", "up":
		m.move(-1)
	case "pgdown", "ctrl+d":
		m.move(m.pageSize())
	case "pgup", "ctrl+u":
		m.move(-m.pageSize())
	case "space":
		if p, ok := m.selected(); ok {
			model.ToggleMark(m.snap.PRs, m.marked, p.Number)
			m.recompute()
		}
	case "a":
		m.markAll()
	case "m":
		m.openConfirm(false)
	case "M":
		m.openConfirm(true)
	}
	return m, nil
}

// markAll marks every row shown, or unmarks them all if they already are.
func (m *Model) markAll() {
	all := len(m.rows) > 0
	for _, p := range m.rows {
		all = all && m.marked[p.Number]
	}
	for _, p := range m.rows {
		if all {
			delete(m.marked, p.Number)
		} else {
			m.marked[p.Number] = true
		}
	}
	m.recompute()
}

// panelAt returns which panel column x falls in.
func (m *Model) panelAt(x int) int {
	rw, tw, _ := m.layout()
	switch {
	case x < rw:
		return focusRail
	case x < rw+tw:
		return focusTable
	}
	return focusPreview
}

// click focuses the panel under the pointer and acts on the line clicked.
// Screen rows: 0 header, 1 box top, 2 first body line.
func (m *Model) click(x, y int) {
	if y < 1 || y > m.boxH() {
		return
	}
	m.focus = m.panelAt(x)
	line := y - 2
	switch m.focus {
	case focusRail:
		// body lines: sections 0..6, separator, Marked
		if s := line; s >= 0 && s <= int(model.Conflicts) {
			m.section = model.Section(s)
		} else if s == int(model.Marked)+1 {
			m.section = model.Marked
		} else {
			return
		}
		m.recompute()
	case focusTable:
		i := m.offset + line - 1 // minus the column header line
		if line < 1 || i >= len(m.rows) || line > m.pageSize() {
			return
		}
		m.cursor = i
		m.clamp()
		rw, _, _ := m.layout()
		if x-rw <= 4 { // the mark column
			model.ToggleMark(m.snap.PRs, m.marked, m.rows[i].Number)
			m.recompute()
		}
	}
}

// wheel scrolls the panel under the pointer without moving focus.
func (m *Model) wheel(x int, b tea.MouseButton) {
	d := 0
	switch b {
	case tea.MouseWheelDown:
		d = 3
	case tea.MouseWheelUp:
		d = -3
	default:
		return
	}
	focus := m.focus
	m.focus = m.panelAt(x)
	if m.focus == focusRail {
		d = sign(d) // one section per notch
	}
	m.move(d)
	m.focus = focus
}

func (m *Model) move(d int) {
	switch m.focus {
	case focusRail:
		m.section = model.Section(min(max(int(m.section)+sign(d), 0), len(model.SectionNames)-1))
		m.recompute()
	case focusTable:
		m.cursor += d
		m.clamp()
	case focusPreview:
		m.pscroll = min(max(0, m.pscroll+d), m.maxScroll())
	}
}

func sign(d int) int {
	if d < 0 {
		return -1
	}
	return 1
}

// recompute rebuilds the visible rows and keeps the cursor on the same PR.
func (m *Model) recompute() {
	open := map[int]bool{}
	for _, p := range m.snap.PRs {
		open[p.Number] = true
	}
	for n := range m.marked {
		if !open[n] { // merged or closed since it was marked
			delete(m.marked, n)
		}
	}
	m.rows = model.Rows(m.snap.PRs, m.section, m.snap.Viewer, m.marked)
	for i, p := range m.rows {
		if p.Number == m.selNum {
			m.cursor = i
		}
	}
	m.clamp()
}

func (m *Model) clamp() {
	m.cursor = min(max(m.cursor, 0), max(len(m.rows)-1, 0))
	if len(m.rows) == 0 {
		m.selNum = 0
		return
	}
	if n := m.rows[m.cursor].Number; n != m.selNum {
		m.selNum, m.pscroll = n, 0
	}
	vis := m.pageSize()
	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.cursor >= m.offset+vis {
		m.offset = m.cursor - vis + 1
	}
	m.offset = max(0, min(m.offset, len(m.rows)-vis))
}

func (m *Model) selected() (model.PR, bool) {
	if len(m.rows) == 0 {
		return model.PR{}, false
	}
	return m.rows[m.cursor], true
}
