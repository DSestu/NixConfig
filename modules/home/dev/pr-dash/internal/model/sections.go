package model

import (
	"slices"
	"strings"
)

type Section int

const (
	All Section = iota
	Mine
	Bumps
	Stacks
	Review
	Failing
	Conflicts
	Marked
)

var SectionNames = [...]string{"All", "Mine", "Bumps", "Stacks", "Review", "Failing", "Conflicts", "Marked"}

// IsBump: dependency bumps opened by .github/workflows/update-deps.yml.
func IsBump(p PR) bool { return p.Author == "github-actions" }

func IsFailing(p PR) bool { return p.CheckRollup == "FAILURE" || p.CheckRollup == "ERROR" }

func IsConflicting(p PR) bool { return p.Mergeable == "CONFLICTING" }

// Match reports whether p belongs in section s.
func Match(s Section, p PR, viewer string, marked map[int]bool) bool {
	switch s {
	case Mine:
		return p.Author == viewer
	case Bumps:
		return IsBump(p)
	case Stacks:
		return p.StackID != 0
	case Review:
		return slices.Contains(p.ReviewRequested, viewer)
	case Failing:
		return IsFailing(p)
	case Conflicts:
		return IsConflicting(p)
	case Marked:
		return marked[p.Number]
	}
	return true
}

// Rows filters prs to section s and orders them for the table: newest first,
// with each stack kept together in position order, placed by its newest member.
func Rows(prs []PR, s Section, viewer string, marked map[int]bool) []PR {
	var out []PR
	for _, p := range prs {
		if Match(s, p, viewer, marked) {
			out = append(out, p)
		}
	}
	key := map[int]int{} // stack id -> highest PR number in it
	for _, p := range out {
		if p.StackID != 0 {
			key[p.StackID] = max(key[p.StackID], p.Number)
		}
	}
	groupKey := func(p PR) int {
		if p.StackID != 0 {
			return key[p.StackID]
		}
		return p.Number
	}
	slices.SortStableFunc(out, func(a, b PR) int {
		if ka, kb := groupKey(a), groupKey(b); ka != kb {
			return kb - ka
		}
		if a.StackID != b.StackID { // a stack and a plain PR sharing a number cannot happen
			return a.StackID - b.StackID
		}
		return a.StackPos - b.StackPos
	})
	return out
}

// Counts returns the number of PRs in each section.
func Counts(prs []PR, viewer string, marked map[int]bool) [len(SectionNames)]int {
	var c [len(SectionNames)]int
	for _, p := range prs {
		for s := range SectionNames {
			if Match(Section(s), p, viewer, marked) {
				c[s]++
			}
		}
	}
	return c
}

// Glyph replaces a title's leading emoji with the 1-cell glyph from the spec,
// because 2-cell emoji break column alignment in some terminals.
func Glyph(title string) string {
	for _, r := range [...][2]string{
		{"❄️", "*"}, {"❄", "*"}, {"🤖", "◆"}, {"📌", "▲"}, {"✨", "✦"}, {"🌐", "◎"},
	} {
		if rest, ok := strings.CutPrefix(title, r[0]); ok {
			return r[1] + strings.TrimPrefix(rest, "️")
		}
	}
	return title
}
