package ui

import (
	"fmt"
	"strings"

	"charm.land/glamour/v2"
	"charm.land/lipgloss/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
)

// bodyCache holds rendered markdown, keyed by width and source text;
// glamour is too slow to run on every frame.
var bodyCache = map[string]string{}

func renderBody(md string, w int) string {
	key := fmt.Sprintf("%d\x00%s", w, md)
	if s, ok := bodyCache[key]; ok {
		return s
	}
	out := md
	r, err := glamour.NewTermRenderer(glamour.WithStyles(glamourStyle()), glamour.WithWordWrap(w))
	if err == nil {
		if s, err := r.Render(md); err == nil {
			out = strings.Trim(s, "\n")
		}
	}
	bodyCache[key] = out
	return out
}

func rule(title string, w int) string {
	t := sVioletDim.Bold(true).Render(title)
	return t + " " + sBorder.Render(strings.Repeat("─", max(0, w-lipgloss.Width(title)-1)))
}

func wrap(s string, w int) []string {
	return strings.Split(lipgloss.NewStyle().Width(w).Render(s), "\n")
}

// previewLines is the preview box body: the selected PR, scrolled.
func (m *Model) previewLines(w, h int) []string {
	l := m.previewAll(w)
	l = l[min(m.pscroll, max(0, len(l)-h)):]
	for i := range l {
		l[i] = " " + l[i]
	}
	return l
}

// maxScroll is the largest useful preview scroll offset.
func (m *Model) maxScroll() int {
	_, _, pw := m.layout()
	return max(0, len(m.previewAll(pw-2))-(m.boxH()-2))
}

// previewAll renders the whole preview for the selected PR, unscrolled.
func (m *Model) previewAll(w int) []string {
	p, ok := m.selected()
	if !ok {
		return nil
	}
	cw := w - 2 // one cell of padding on each side
	var l []string
	add := func(s ...string) { l = append(l, s...) }

	add(sPinkDim.Bold(true).Render(fmt.Sprintf("#%d", p.Number)) + " " + sSub.Bold(true).Render(model.Glyph(p.Title)))
	add(sDim.Italic(true).Render(fmt.Sprintf("%s opened %s ago", p.Author, ago(m.now, p.CreatedAt))), "")
	label := func(s string) string { return sDim.Render(fmt.Sprintf("%-7s", s)) }
	add(label("base") + sSub.Render(p.BaseRef+" ← "+p.HeadRef))
	if p.StackID != 0 {
		add(label("stack") + sAmber.Render(fmt.Sprintf("%d/%d", p.StackPos, p.StackSize)) + sDim.Render(fmt.Sprintf(" · stack %d", p.StackID)))
	}
	add(label("diff") + sDim.Render(fmt.Sprintf("+%d −%d", p.Additions, p.Deletions)))
	add(label("merge") + mergeLine(p))
	if p.IsDraft {
		add(label("draft") + sAmber.Render("not ready for review"))
	}

	passed := 0
	for _, c := range p.Checks {
		if c.State == model.CheckPass {
			passed++
		}
	}
	add("", rule(fmt.Sprintf("Checks %d/%d", passed, len(p.Checks)), cw))
	if len(p.Checks) == 0 {
		add(sDim.Render("no checks on the head commit"))
	}
	for _, c := range p.Checks {
		g, gs, dur := "●", sAmberDim, "running"
		switch c.State {
		case model.CheckPass:
			g, gs, dur = "✓", sMintDim, ""
		case model.CheckFail:
			g, gs, dur = "✗", sCoral, ""
		}
		if c.Duration > 0 {
			dur = c.Duration.String()
		}
		name := fit(sSub.Render(c.Name), max(cw-2-len(dur)-1, 1))
		add(gs.Bold(true).Render(g) + " " + name + " " + sDim.Render(dur))
	}

	add("", rule("Body", cw))
	if strings.TrimSpace(p.Body) == "" {
		add(sDim.Render("no description"))
	} else {
		add(strings.Split(renderBody(p.Body, cw), "\n")...)
	}

	add("", rule(fmt.Sprintf("Comments %d", len(p.Comments)), cw))
	if len(p.Comments) == 0 {
		add(sDim.Render("no comments"))
	}
	for _, c := range p.Comments {
		add(sViolet.Bold(true).Render(c.Author) + " " + sDim.Render(ago(m.now, c.CreatedAt)))
		for _, line := range wrap(c.Body, cw) {
			add(sText.Render(line))
		}
		add("")
	}

	return l
}

func mergeLine(p model.PR) string {
	switch p.Mergeable {
	case "CONFLICTING":
		return sCoral.Bold(true).Render("✗ ") + sCoral.Render("conflicts with "+p.BaseRef)
	case "UNKNOWN":
		return sDim.Render("… checking")
	}
	s := sMintDim.Bold(true).Render("✓ ") + sMintDim.Render("no conflicts")
	if p.MergeState != "CLEAN" && p.MergeState != "" {
		s += sDim.Render(" · " + strings.ToLower(p.MergeState))
	}
	return s
}
