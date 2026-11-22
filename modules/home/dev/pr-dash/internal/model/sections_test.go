package model

import (
	"reflect"
	"testing"
)

func nums(prs []PR) []int {
	var n []int
	for _, p := range prs {
		n = append(n, p.Number)
	}
	return n
}

var sample = []PR{
	{Number: 290, Author: "github-actions", Mergeable: "CONFLICTING"},
	{Number: 275, Author: "DSestu", StackID: 7, StackPos: 3, CheckRollup: "PENDING"},
	{Number: 273, Author: "DSestu", StackID: 7, StackPos: 1},
	{Number: 274, Author: "DSestu", StackID: 7, StackPos: 2, ReviewRequested: []string{"DSestu"}},
	{Number: 271, Author: "octocat", CheckRollup: "FAILURE"},
	{Number: 280, Author: "github-actions"},
}

func TestRowsGroupsStacks(t *testing.T) {
	got := nums(Rows(sample, All, "DSestu", nil))
	want := []int{290, 280, 273, 274, 275, 271}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}

func TestSections(t *testing.T) {
	marked := map[int]bool{280: true}
	for s, want := range map[Section][]int{
		Mine:      {273, 274, 275},
		Bumps:     {290, 280},
		Stacks:    {273, 274, 275},
		Review:    {274},
		Failing:   {271},
		Conflicts: {290},
		Marked:    {280},
	} {
		if got := nums(Rows(sample, s, "DSestu", marked)); !reflect.DeepEqual(got, want) {
			t.Errorf("%s: got %v want %v", SectionNames[s], got, want)
		}
	}
	c := Counts(sample, "DSestu", marked)
	if c[All] != 6 || c[Bumps] != 2 || c[Marked] != 1 {
		t.Errorf("counts %v", c)
	}
}

func TestGlyph(t *testing.T) {
	for in, want := range map[string]string{
		"❄️ flake: nixpkgs": "* flake: nixpkgs",
		"🤖 agents: x":       "◆ agents: x",
		"📌 pins: quarto":    "▲ pins: quarto",
		"feat: plain title": "feat: plain title",
	} {
		if got := Glyph(in); got != want {
			t.Errorf("Glyph(%q) = %q want %q", in, got, want)
		}
	}
}
