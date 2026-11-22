package ui

import (
	"fmt"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/charmbracelet/x/ansi"
)

const (
	railW   = 20
	narrowW = 110       // below this the rail collapses into the table title
	sepLine = "\x00sep" // body line drawn as ├──┤ across the box
)

// layout returns the three column widths, borders included.
// Below narrowW the rail is hidden (width 0) and [ ] switch sections.
func (m *Model) layout() (rail, table, preview int) {
	if m.w < narrowW {
		preview = m.w * 45 / 100
		return 0, m.w - preview, preview
	}
	rest := m.w - railW
	preview = rest * 58 / 130
	return railW, rest - preview, preview
}

func (m *Model) boxH() int { return max(m.h-3, 5) } // minus header, merge bar, footer

func (m *Model) pageSize() int { return max(m.boxH()-4, 1) } // minus borders, column header, footer line

func (m Model) View() tea.View {
	v := tea.NewView("")
	v.AltScreen = true
	v.MouseMode = tea.MouseModeCellMotion
	v.BackgroundColor = cBg
	v.WindowTitle = "pr-dash " + m.Repo
	if m.w == 0 {
		return v
	}
	rw, tw, pw := m.layout()
	h := m.boxH()
	rail := make([]string, h)
	tableTitle := "Pull requests"
	if rw > 0 {
		rail = box("Sections", m.focus == focusRail, rw, h, m.railLines())
	} else {
		c := model.Counts(m.snap.PRs, m.snap.Viewer, m.marked)
		tableTitle = fmt.Sprintf("‹ %s %d ›", model.SectionNames[m.section], c[m.section])
	}
	table := box(tableTitle, m.focus == focusTable, tw, h, m.tableLines(tw-2, h-2))
	prev := box("Preview", m.focus == focusPreview, pw, h, m.previewLines(pw-2, h-2))
	var b strings.Builder
	b.WriteString(fit(m.header(), m.w) + "\n")
	for i := range rail {
		b.WriteString(rail[i] + table[i] + prev[i] + "\n")
	}
	b.WriteString(m.mergeBar() + "\n")
	b.WriteString(fit(m.footer(), m.w))
	v.Content = b.String()
	if m.merge.phase != phaseNone {
		d := m.dialog()
		v.Content = overlay(scrim(v.Content), d, (m.w-lipgloss.Width(d[0]))/2, max(1, (m.h-len(d))/2))
	}
	return v
}

// scrim flattens the screen behind a dialog to one dark colour, so the
// dialog is the only thing that reads.
func scrim(s string) string {
	lines := strings.Split(ansi.Strip(s), "\n")
	for i, l := range lines {
		lines[i] = sBorder.Render(l)
	}
	return strings.Join(lines, "\n")
}

// fit truncates or pads s (which may hold ANSI styles) to exactly w cells.
func fit(s string, w int) string {
	s = ansi.Truncate(s, w, "…")
	return s + strings.Repeat(" ", max(0, w-ansi.StringWidth(s)))
}

// box draws a rounded panel with a title tab; the focused panel is violet.
func box(title string, focused bool, w, h int, body []string) []string {
	if focused {
		return frame(title, sViolet, sTabOn, w, h, body)
	}
	return frame(title, sBorder, sSub.Bold(true), w, h, body)
}

// frame draws a rounded box with border style bc and title tab style tt.
func frame(title string, bc, tt lipgloss.Style, w, h int, body []string) []string {
	inner := w - 2
	t := " " + title + " "
	out := []string{bc.Render("╭─") + tt.Render(t) + bc.Render(strings.Repeat("─", max(0, inner-1-lipgloss.Width(t)))+"╮")}
	for i := 0; i < h-2; i++ {
		l := ""
		if i < len(body) {
			l = body[i]
		}
		if l == sepLine {
			out = append(out, bc.Render("├"+strings.Repeat("─", inner)+"┤"))
			continue
		}
		out = append(out, bc.Render("│")+fit(l, inner)+bc.Render("│"))
	}
	return append(out, bc.Render("╰"+strings.Repeat("─", inner)+"╯"))
}

func (m *Model) header() string {
	pill := " ◆ pr-dash "
	cols := lipgloss.Blend1D(len([]rune(pill)), pillStops...)
	var b strings.Builder
	for i, r := range []rune(pill) {
		b.WriteString(chip(cols[i]).Render(string(r)))
	}
	dot := sBorder.Render("  ·  ")
	b.WriteString(sDim.Render("  " + m.Repo))
	if m.Branch != "" {
		b.WriteString(sDim.Render("  ") + sVioletDim.Render(m.Branch))
	}
	switch {
	case m.loading:
		b.WriteString(dot + sPink.Render(m.spin()+" fetching…"))
	case !m.next.IsZero():
		b.WriteString(dot + sDim.Render("↻ "+countdown(m.next.Sub(m.now))))
	}
	if !m.fetched.IsZero() {
		b.WriteString(dot + sDim.Render("updated "+m.fetched.Format("15:04:05")))
	}
	if r := m.snap.Rate; r.Limit > 0 {
		rs := sDim
		if r.Remaining < r.Limit/10 {
			rs = sAmber
		}
		b.WriteString(dot + rs.Render(fmt.Sprintf("rate %d/%d", r.Remaining, r.Limit)))
	}
	if m.err != nil {
		b.WriteString(dot + sCoral.Bold(true).Render("✗ ") + sCoral.Render(oneLine(m.err.Error())))
	}
	return b.String()
}

func countdown(d time.Duration) string {
	if d >= time.Minute {
		return fmt.Sprintf("%dm", int(d.Round(time.Minute).Minutes()))
	}
	return fmt.Sprintf("%ds", max(0, int(d.Round(time.Second).Seconds())))
}

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }

func (m *Model) railLines() []string {
	counts := model.Counts(m.snap.PRs, m.snap.Viewer, m.marked)
	var out []string
	for s, name := range model.SectionNames {
		if model.Section(s) == model.Marked {
			out = append(out, sepLine)
		}
		cur, ns, cs := " ", sSub, sDim
		switch {
		case model.Section(s) == m.section:
			cur, ns, cs = sPink.Render("▌"), sText.Bold(true), sSub
		case model.Section(s) == model.Marked && counts[s] > 0:
			ns, cs = sAmberDim.Bold(true), sAmberDim
		case model.Section(s) == model.Failing && counts[s] > 0:
			cs = sCoralDim
		case model.Section(s) == model.Conflicts && counts[s] > 0:
			cs = sAmberDim
		}
		out = append(out, cur+" "+ns.Render(fmt.Sprintf("%-10s", name))+cs.Render(fmt.Sprintf("%5d", counts[s]))+" ")
	}
	return out
}

// Table columns: cursor(1) mark(3) sp num(5) sp | title… | sp ck(1) sp diff(9) sp age(3) sp
const leftW, rightW = 11, 17

func (m *Model) tableLines(w, h int) []string {
	hd := sViolet.Bold(true)
	titleW := w - leftW - rightW
	out := []string{" " + hd.Render("mk ") + " " + hd.Render(fmt.Sprintf("%5s", "#")) + " " +
		hd.Render(fmt.Sprintf("%-*s", max(titleW, 0), "title")) + " " + hd.Render("ck") + hd.Render(fmt.Sprintf("%9s", "±")) + " " + hd.Render("age") + " "}
	vis := h - 2
	for i := m.offset; i < len(m.rows) && i < m.offset+vis; i++ {
		last := i+1 >= len(m.rows) || m.rows[i+1].StackID != m.rows[i].StackID
		out = append(out, m.row(m.rows[i], i == m.cursor, titleW, last))
	}
	switch {
	case len(m.rows) == 0 && m.loading:
		out = append(out, sDim.Render("  loading…"))
	case len(m.rows) == 0:
		out = append(out, sDim.Render("  nothing in "+model.SectionNames[m.section]))
	}
	for len(out) < h-1 {
		out = append(out, "")
	}
	return append(out, sDim.Render(fmt.Sprintf(" %d PRs · %d marked · newest first, stacks grouped", len(m.rows), len(m.marked))))
}

func (m *Model) row(p model.PR, sel bool, titleW int, lastInStack bool) string {
	start, fading := m.changed[p.Number]
	bg := func(s lipgloss.Style) lipgloss.Style {
		switch {
		case sel:
			return s.Background(cSel)
		case fading && m.frame-start < fadeFrames:
			return s.Background(fadeCols[m.frame-start])
		}
		return s
	}
	sp := bg(lipgloss.NewStyle()).Render(" ")

	cur := sp
	if sel {
		cur = bg(sPink).Render("▌")
	}
	mk := bg(sDim).Render(" ○ ")
	if m.marked[p.Number] {
		mk = bg(sAmber).Render(" ● ")
	}
	numS, titleS := sSub, sText
	if sel {
		numS, titleS = sPink.Bold(true), sText.Bold(true)
	}
	num := bg(numS).Render(fmt.Sprintf("%5s", fmt.Sprintf("#%d", p.Number)))

	title := model.Glyph(p.Title)
	if p.StackID != 0 {
		title = map[bool]string{true: "└ ", false: "├ "}[lastInStack] + title
	}
	label, chipS := "", lipgloss.Style{}
	switch {
	case model.IsFailing(p):
		label, chipS = " failing ", sChipFail
	case model.IsConflicting(p):
		label, chipS = " conflict ", sChipWarn
	case p.StackID != 0:
		label, chipS = fmt.Sprintf(" %d/%d ", p.StackPos, p.StackSize), sChipWarn
	case p.IsDraft:
		label, chipS = " draft ", bg(sDim)
	}
	tw := titleW
	if label != "" {
		tw -= ansi.StringWidth(label) + 1
	}
	t := ansi.Truncate(title, max(tw, 1), "…")
	t += strings.Repeat(" ", max(0, tw-ansi.StringWidth(t)))
	titleCell := bg(titleS).Render(t)
	if label != "" {
		titleCell += sp + chipS.Render(label)
	}

	ck, ckS := checkGlyph(p.CheckRollup)
	diff := bg(sDim).Render(fmt.Sprintf("%9s", fmt.Sprintf("+%d −%d", p.Additions, p.Deletions)))
	ageS := sDim
	if model.IsFailing(p) {
		ageS = sCoral
	}
	age := bg(ageS).Render(fmt.Sprintf("%3s", ago(m.now, p.CreatedAt)))
	return cur + mk + sp + num + sp + titleCell + sp + bg(ckS.Bold(true)).Render(ck) + sp + diff + sp + age + sp
}

// checkGlyph maps a statusCheckRollup state to a 1-cell glyph and its colour.
func checkGlyph(rollup string) (string, lipgloss.Style) {
	switch rollup {
	case "SUCCESS":
		return "✓", sMint
	case "FAILURE", "ERROR":
		return "✗", sCoral
	case "PENDING", "EXPECTED":
		return "●", sAmber
	}
	return "·", sDim // no checks
}

func ago(now, t time.Time) string {
	d := now.Sub(t)
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	}
	return fmt.Sprintf("%dd", int(d.Hours()/24))
}

func (m *Model) mergeBar() string {
	b := sBar.Foreground(cDim)
	if m.flash != "" {
		return bar(sBar.Foreground(cAmber).Render(" "+m.flash), m.w)
	}
	if len(m.marked) == 0 {
		return bar(b.Render(" nothing marked · ")+m.health(), m.w)
	}
	plan := model.BuildPlan(m.snap.PRs, m.marked)
	n := 0
	for _, s := range plan.Steps {
		n += len(s.Lands)
	}
	out := b.Render(" ") + sChipWarn.Render(fmt.Sprintf(" %d marked ", len(m.marked))) + b.Render(" → ") +
		sBar.Foreground(cPink).Bold(true).Render("M") + b.Render(fmt.Sprintf(" squash-merge %d in order", n))
	if len(plan.Skips) > 0 {
		out += b.Render(" · skips ")
		for _, s := range plan.Skips {
			c := sChipWarn
			if s.Reason == "failing checks" {
				c = sChipFail
			}
			out += c.Render(fmt.Sprintf(" #%d %s ", s.Number, s.Reason)) + b.Render(" ")
		}
	}
	return bar(out, m.w)
}

// health counts the open PRs by merge readiness, for the idle merge bar.
func (m *Model) health() string {
	var clean, failing, conflicting int
	for _, p := range m.snap.PRs {
		switch {
		case model.IsFailing(p):
			failing++
		case model.IsConflicting(p):
			conflicting++
		case !p.IsDraft:
			clean++
		}
	}
	dot := sBar.Foreground(cBorder).Render(" · ")
	out := sBar.Foreground(cMintDim).Render(fmt.Sprintf("%d ready", clean))
	if failing > 0 {
		out += dot + sBar.Foreground(cCoral).Render(fmt.Sprintf("%d failing", failing))
	}
	if conflicting > 0 {
		out += dot + sBar.Foreground(cAmber).Render(fmt.Sprintf("%d conflicting", conflicting))
	}
	return out
}

// bar pads already-styled s to w cells with the merge-bar background.
func bar(s string, w int) string {
	s = ansi.Truncate(s, w, "…")
	return s + sBar.Render(strings.Repeat(" ", max(0, w-ansi.StringWidth(s))))
}

func (m *Model) footer() string {
	keys := [][2]string{{"tab", "panel"}, {"[ ]", "section"}, {"j/k", "move"}, {"space", "mark"}, {"a", "mark all"}, {"m", "merge"}, {"M", "merge marked"}, {"enter", "open"}, {"r", "refresh"}, {"q", "quit"}}
	parts := make([]string, len(keys))
	for i, k := range keys {
		parts[i] = sPink.Bold(true).Render(k[0]) + sDim.Render(" "+k[1])
	}
	return " " + strings.Join(parts, sBorder.Render(" · "))
}
