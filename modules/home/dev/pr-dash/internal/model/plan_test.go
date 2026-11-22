package model

import (
	"reflect"
	"testing"
)

var planPRs = []PR{
	{Number: 276, Author: "github-actions", Mergeable: "MERGEABLE"},
	{Number: 290, Author: "github-actions", Mergeable: "CONFLICTING"},
	{Number: 271, CheckRollup: "FAILURE"},
	{Number: 260, IsDraft: true},
	{Number: 273, StackID: 7, StackPos: 1, StackSize: 3},
	{Number: 274, StackID: 7, StackPos: 2, StackSize: 3},
	{Number: 275, StackID: 7, StackPos: 3, StackSize: 3},
	{Number: 281, StackID: 9, StackPos: 1, StackSize: 2, Mergeable: "CONFLICTING"},
	{Number: 282, StackID: 9, StackPos: 2, StackSize: 2},
}

func TestToggleMarkStack(t *testing.T) {
	m := map[int]bool{}
	ToggleMark(planPRs, m, 274)
	if !reflect.DeepEqual(m, map[int]bool{273: true, 274: true}) {
		t.Fatalf("marking 2/3 should mark 1/3 too: %v", m)
	}
	ToggleMark(planPRs, m, 275)
	ToggleMark(planPRs, m, 274) // unmark 2/3 also unmarks 3/3
	if !reflect.DeepEqual(m, map[int]bool{273: true}) {
		t.Fatalf("unmarking 2/3 should unmark 3/3: %v", m)
	}
	ToggleMark(planPRs, m, 276)
	if !m[276] || len(m) != 2 {
		t.Fatalf("plain PR toggles alone: %v", m)
	}
}

func TestBuildPlan(t *testing.T) {
	marked := map[int]bool{276: true, 290: true, 271: true, 260: true, 273: true, 274: true, 282: true, 281: true}
	got := BuildPlan(planPRs, marked)

	var steps [][]int
	for _, s := range got.Steps {
		steps = append(steps, s.Lands)
	}
	// stack 7 is submitted on 274 and lands 273+274; 275 is not marked so it stays
	if want := [][]int{{273, 274}, {276}}; !reflect.DeepEqual(steps, want) {
		t.Errorf("steps %v want %v", steps, want)
	}
	if got.Steps[0].Target.Number != 274 {
		t.Errorf("stack step should target the highest marked PR, got #%d", got.Steps[0].Target.Number)
	}
	want := []Skip{
		{260, "draft"},
		{271, "failing checks"},
		{281, "stack: #281 conflicts"},
		{282, "stack: #281 conflicts"},
		{290, "conflicts"},
	}
	if !reflect.DeepEqual(got.Skips, want) {
		t.Errorf("skips\n got %v\nwant %v", got.Skips, want)
	}
}
