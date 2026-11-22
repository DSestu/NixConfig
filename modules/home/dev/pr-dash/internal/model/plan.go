package model

import (
	"slices"
	"strconv"
)

// Step is one merge request. For a stack it is submitted on the highest
// marked PR and lands every PR below it too, atomically.
type Step struct {
	Target PR
	Lands  []int // PR numbers this step merges, bottom of the stack first
}

type Skip struct {
	Number int
	Reason string
}

type Plan struct {
	Steps []Step
	Skips []Skip
}

// problem is why p must not be merged, or "".
func problem(p PR) string {
	switch {
	case p.IsDraft:
		return "draft"
	case IsFailing(p):
		return "failing checks"
	case IsConflicting(p):
		return "conflicts"
	}
	return ""
}

// BuildPlan turns the marked PRs into ordered merge steps plus skips with
// reasons. Steps run oldest (lowest number) first.
func BuildPlan(prs []PR, marked map[int]bool) Plan {
	var plan Plan
	top := map[int]PR{} // stack id -> highest marked PR in it
	for _, p := range prs {
		if !marked[p.Number] {
			continue
		}
		if p.StackID == 0 {
			if why := problem(p); why != "" {
				plan.Skips = append(plan.Skips, Skip{p.Number, why})
			} else {
				plan.Steps = append(plan.Steps, Step{Target: p, Lands: []int{p.Number}})
			}
			continue
		}
		if t, ok := top[p.StackID]; !ok || p.StackPos > t.StackPos {
			top[p.StackID] = p
		}
	}
	for id, t := range top {
		var below []PR
		for _, p := range prs {
			if p.StackID == id && p.StackPos <= t.StackPos {
				below = append(below, p)
			}
		}
		slices.SortFunc(below, func(a, b PR) int { return a.StackPos - b.StackPos })
		step, blocked := Step{Target: t}, ""
		for _, p := range below {
			step.Lands = append(step.Lands, p.Number)
			if why := problem(p); why != "" && blocked == "" {
				blocked = "stack: #" + strconv.Itoa(p.Number) + " " + why
			}
		}
		if blocked == "" {
			plan.Steps = append(plan.Steps, step)
			continue
		}
		for _, p := range below {
			if marked[p.Number] {
				plan.Skips = append(plan.Skips, Skip{p.Number, blocked})
			}
		}
	}
	slices.SortFunc(plan.Steps, func(a, b Step) int { return a.Lands[0] - b.Lands[0] })
	slices.SortFunc(plan.Skips, func(a, b Skip) int { return a.Number - b.Number })
	return plan
}

// ToggleMark marks or unmarks num. Marking a stacked PR marks everything below
// it (it cannot land without them); unmarking one unmarks everything above it.
func ToggleMark(prs []PR, marked map[int]bool, num int) {
	var target PR
	for _, p := range prs {
		if p.Number == num {
			target = p
		}
	}
	on := !marked[num]
	for _, p := range prs {
		switch {
		case p.Number == num:
		case target.StackID == 0 || p.StackID != target.StackID:
			continue
		case on && p.StackPos > target.StackPos, !on && p.StackPos < target.StackPos:
			continue
		}
		if on {
			marked[p.Number] = true
		} else {
			delete(marked, p.Number)
		}
	}
}
