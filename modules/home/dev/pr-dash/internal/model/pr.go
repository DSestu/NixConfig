// Package model holds pr-dash's pure types and logic; no I/O.
package model

import "time"

// Check states, normalised from CheckRun and StatusContext.
const (
	CheckPass    = "pass"
	CheckFail    = "fail"
	CheckPending = "pending"
)

type Check struct {
	Name     string
	State    string        // CheckPass, CheckFail or CheckPending
	Duration time.Duration // 0 when unknown or still running
}

type Comment struct {
	Author    string
	Body      string
	CreatedAt time.Time
}

type PR struct {
	Number             int
	Title, Body        string
	Author             string
	HeadRef, BaseRef   string
	HeadSHA            string // merges pass it so GitHub refuses if the branch moved since we looked
	CreatedAt          time.Time
	Additions          int
	Deletions          int
	IsDraft            bool
	Mergeable          string // MERGEABLE, CONFLICTING or UNKNOWN (GitHub computes it lazily)
	MergeState         string // mergeStateStatus: CLEAN, DIRTY, BLOCKED, ...
	ReviewDecision     string
	ReviewRequested    []string // logins asked to review
	CheckRollup        string   // SUCCESS, FAILURE, PENDING, ERROR, EXPECTED; "" when the PR has no checks
	Checks             []Check
	Comments           []Comment
	StackID, StackSize int // 0 when not stacked
	StackPos           int // 1-based position in the stack; 0 when not stacked
}

// Snapshot is one refresh's worth of data.
type Snapshot struct {
	Viewer string
	Rate   struct{ Remaining, Limit int } // GraphQL points left this hour
	PRs    []PR
}

// MergeResult is the outcome of one merge request.
type MergeResult struct {
	Status  string // merged, enqueued or failed
	Message string
}
