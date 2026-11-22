package ui

import (
	"fmt"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/charmbracelet/x/ansi"
)

type phase int

const (
	phaseNone    phase = iota
	phaseConfirm       // dialog open, waiting for y/n
	phaseRunning       // steps merging one after another
	phaseDone          // summary shown
)

type mergeState struct {
	phase   phase
	batch   bool // from M (the marked PRs) rather than m (the PR under the cursor)
	plan    model.Plan
	results []model.MergeResult // one per finished step
	errs    []error
}

type mergedMsg struct {
	res model.MergeResult
	err error
}

// openConfirm opens the dialog for the marked PRs (batch) or the PR under
// the cursor plus, in a stack, the PRs below it.
func (m *Model) openConfirm(batch bool) {
	set := m.marked
	if !batch {
		set = map[int]bool{}
		if p, ok := m.selected(); ok {
			model.ToggleMark(m.snap.PRs, set, p.Number)
		}
	}
	switch {
	case m.Merge == nil && !m.DryRun:
		m.flash = m.MergeBlocked
	case len(set) == 0 && batch:
		m.flash = "nothing marked: space marks the PR under the cursor, a marks every PR shown"
	case len(set) == 0:
		m.flash = "no PR under the cursor"
	default:
		m.merge = mergeState{phase: phaseConfirm, batch: batch, plan: model.BuildPlan(m.snap.PRs, set)}
	}
}

func (m Model) mergeKey(k string) (tea.Model, tea.Cmd) {
	switch m.merge.phase {
	case phaseConfirm:
		switch k {
		case "y", "Y":
			if len(m.merge.plan.Steps) == 0 || m.DryRun {
				m.merge.phase = phaseDone
				return m, nil
			}
			m.merge.phase = phaseRunning
			return m, m.mergeNext()
		case "n", "N", "esc", "q":
			m.merge = mergeState{}
		}
	case phaseDone:
		if k == "enter" || k == "esc" || k == "q" {
			ran, batch := len(m.merge.results) > 0, m.merge.batch
			m.merge = mergeState{}
			if ran {
				if batch {
					m.marked = map[int]bool{}
				}
				cmd := m.refresh()
				return m, cmd
			}
		}
	case phaseRunning:
		if k == "ctrl+c" { // the request already sent keeps running on GitHub
			return m, tea.Quit
		}
	}
	return m, nil
}

// mergeNext runs the next step; steps go one at a time, in plan order.
func (m *Model) mergeNext() tea.Cmd {
	step := m.merge.plan.Steps[len(m.merge.results)]
	merge := m.Merge
	return func() tea.Msg {
		res, err := merge(step.Target.Number, step.Target.HeadSHA, step.Target.StackID != 0)
		return mergedMsg{res, err}
	}
}

func (m Model) merged(msg mergedMsg) (tea.Model, tea.Cmd) {
	if msg.err != nil {
		msg.res = model.MergeResult{Status: "failed", Message: msg.err.Error()}
	}
	m.merge.results = append(m.merge.results, msg.res)
	if len(m.merge.results) < len(m.merge.plan.Steps) {
		return m, m.mergeNext()
	}
	m.merge.phase = phaseDone
	return m, nil
}

func (m *Model) title(num int) string {
	for _, p := range m.snap.PRs {
		if p.Number == num {
			return model.Glyph(p.Title)
		}
	}
	return ""
}

func numList(nums []int) string {
	s := make([]string, len(nums))
	for i, n := range nums {
		s[i] = fmt.Sprintf("#%d", n)
	}
	return strings.Join(s, " ")
}

// dialog renders the confirm / progress / summary box.
func (m *Model) dialog() []string {
	ms := m.merge
	w := min(84, m.w-4)
	cw := w - 4
	var l []string
	add := func(s ...string) { l = append(l, s...) }

	n := 0
	for _, s := range ms.plan.Steps {
		n += len(s.Lands)
	}
	title := fmt.Sprintf("Squash-merge %d PR%s into %s", n, map[bool]string{true: "", false: "s"}[n == 1], m.Repo)
	if m.DryRun {
		title = "Dry run: " + title
	}

	add("")
	if len(ms.plan.Steps) == 0 {
		add(sCoral.Render("Nothing can merge: every marked PR is skipped."))
	} else {
		add(sSub.Render("Lands, in this order:"))
	}
	merged, failed := 0, 0
	for i, s := range ms.plan.Steps {
		g := sDim.Render(fmt.Sprintf("%2d.", i+1)) // every status cell is 3 wide
		note, noteS := "", sDim
		switch {
		case i < len(ms.results):
			r := ms.results[i]
			switch r.Status {
			case "merged":
				g, merged = sMint.Bold(true).Render(" ✓ "), merged+1
			case "enqueued":
				g, merged, note = sMint.Bold(true).Render(" ⇢ "), merged+1, "added to the merge queue"
			default:
				g, failed, note, noteS = sCoral.Bold(true).Render(" ✗ "), failed+1, r.Message, sCoral
			}
		case ms.phase == phaseRunning && i == len(ms.results):
			g = sAmber.Bold(true).Render(" ● ")
			note = "merging…"
		}
		add(" " + g + " " + sPinkDim.Bold(true).Render(fmt.Sprintf("#%d", s.Target.Number)) + " " + sText.Render(m.title(s.Target.Number)))
		if len(s.Lands) > 1 {
			add("      " + sAmberDim.Render("stack: lands "+numList(s.Lands)+" together"))
		}
		if note != "" {
			for _, line := range wrap(note, cw-5) {
				add("      " + noteS.Render(line))
			}
		}
	}
	if len(ms.plan.Skips) > 0 {
		add("", sSub.Render("Skipped:"))
		for _, s := range ms.plan.Skips {
			add(" " + sCoral.Bold(true).Render(" ✗ ") + " " + sPinkDim.Bold(true).Render(fmt.Sprintf("#%d", s.Number)) + " " + sAmber.Render(s.Reason) + sDim.Render(" · "+m.title(s.Number)))
		}
	}
	add("")
	key := func(k, d string) string { return sPink.Bold(true).Render(k) + sDim.Render(" "+d) }
	sep := sBorder.Render(" · ")
	switch ms.phase {
	case phaseConfirm:
		if len(ms.plan.Steps) == 0 {
			add(key("n", "close"))
		} else if m.DryRun {
			add(key("y", "finish dry run")+sep+key("n", "cancel"), sDim.Render("dry run: nothing will be merged"))
		} else {
			add(key("y", "squash-merge") + sep + key("n", "cancel"))
		}
	case phaseRunning:
		add(sAmber.Render(fmt.Sprintf("merging %d/%d…", len(ms.results)+1, len(ms.plan.Steps))) + sDim.Render("  ctrl+c quits; a request already sent still runs on GitHub"))
	case phaseDone:
		if m.DryRun {
			add(sDim.Render("dry run: nothing was merged") + sep + key("enter", "close"))
		} else {
			sum := sMint.Render(fmt.Sprintf("%d merged", merged))
			if failed > 0 {
				sum += sep + sCoral.Render(fmt.Sprintf("%d failed", failed))
			}
			add(sum + sep + key("enter", "close and refresh"))
		}
	}

	maxBody := max(m.h-4, 3)
	if len(l) > maxBody {
		l = append(l[:maxBody-1], sDim.Render("…")) // shortcut: clips very long batches; add scrolling if it ever matters
	}
	for i := range l {
		l[i] = " " + l[i]
	}
	return box(title, true, w, len(l)+2, l)
}

// overlay draws fg over bg with its top-left corner at x, y.
func overlay(bg string, fg []string, x, y int) string {
	lines := strings.Split(bg, "\n")
	for i, f := range fg {
		r := y + i
		if r < 0 || r >= len(lines) {
			continue
		}
		fw := lipgloss.Width(f)
		lines[r] = ansi.Truncate(lines[r], x, "") + "\x1b[m" + f + "\x1b[m" + ansi.TruncateLeft(lines[r], x+fw, "")
	}
	return strings.Join(lines, "\n")
}
