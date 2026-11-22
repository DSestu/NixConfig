// Package gh talks to GitHub. Everything here does I/O except convert.
package gh

import (
	_ "embed"
	"time"

	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/cli/go-gh/v2/pkg/api"
	"github.com/cli/go-gh/v2/pkg/repository"
)

//go:embed query.graphql
var query string

// CurrentRepo resolves owner/name from GH_REPO or the cwd's git remotes, like gh.
func CurrentRepo() (repository.Repository, error) { return repository.Current() }

// Fetch runs the single read query for the repo's open PRs.
// shortcut: first 100 open PRs only, add pagination if a repo ever has more.
func Fetch(repo repository.Repository) (model.Snapshot, error) {
	client, err := api.NewGraphQLClient(api.ClientOptions{Host: repo.Host})
	if err != nil {
		return model.Snapshot{}, err
	}
	var resp response
	err = client.Do(query, map[string]interface{}{"owner": repo.Owner, "name": repo.Name}, &resp)
	if err != nil {
		return model.Snapshot{}, err
	}
	return convert(resp), nil
}

type login struct{ Login string }

type response struct {
	Viewer     login
	Repository struct {
		PullRequests struct {
			Nodes []struct {
				Number                                      int
				Title, Body                                 string
				IsDraft                                     bool
				CreatedAt                                   time.Time
				Additions, Deletions                        int
				HeadRefName, HeadRefOid, BaseRefName        string
				Mergeable, MergeStateStatus, ReviewDecision string
				Author                                      *login
				ReviewRequests                              struct {
					Nodes []struct{ RequestedReviewer *login }
				}
				Stack      *struct{ Number, Size int }
				StackEntry *struct{ Position int }
				Comments   struct {
					Nodes []struct {
						Author    *login
						Body      string
						CreatedAt time.Time
					}
				}
				Commits struct {
					Nodes []struct {
						Commit struct {
							StatusCheckRollup *struct {
								State    string
								Contexts struct{ Nodes []checkNode }
							}
						}
					}
				}
			}
		}
	}
}

// checkNode is the union of CheckRun and StatusContext fields.
type checkNode struct {
	Typename                 string     `json:"__typename"`
	Name, Status, Conclusion string     // CheckRun
	StartedAt, CompletedAt   *time.Time // CheckRun
	Context, State           string     // StatusContext
}

func (c checkNode) toCheck() model.Check {
	if c.Typename == "StatusContext" {
		return model.Check{Name: c.Context, State: statusState(c.State)}
	}
	ch := model.Check{Name: c.Name, State: model.CheckPending}
	if c.Status == "COMPLETED" {
		ch.State = model.CheckFail
		switch c.Conclusion {
		case "SUCCESS", "NEUTRAL", "SKIPPED":
			ch.State = model.CheckPass
		}
		if c.StartedAt != nil && c.CompletedAt != nil {
			ch.Duration = c.CompletedAt.Sub(*c.StartedAt)
		}
	}
	return ch
}

func statusState(s string) string {
	switch s {
	case "SUCCESS":
		return model.CheckPass
	case "PENDING", "EXPECTED":
		return model.CheckPending
	}
	return model.CheckFail
}

func name(l *login) string {
	if l == nil {
		return "ghost" // deleted account, as GitHub shows it
	}
	return l.Login
}

func convert(r response) model.Snapshot {
	snap := model.Snapshot{Viewer: r.Viewer.Login}
	for _, n := range r.Repository.PullRequests.Nodes {
		pr := model.PR{
			Number: n.Number, Title: n.Title, Body: n.Body, Author: name(n.Author),
			HeadRef: n.HeadRefName, HeadSHA: n.HeadRefOid, BaseRef: n.BaseRefName, CreatedAt: n.CreatedAt,
			Additions: n.Additions, Deletions: n.Deletions, IsDraft: n.IsDraft,
			Mergeable: n.Mergeable, MergeState: n.MergeStateStatus, ReviewDecision: n.ReviewDecision,
		}
		for _, rr := range n.ReviewRequests.Nodes {
			if rr.RequestedReviewer != nil { // nil for team reviewers
				pr.ReviewRequested = append(pr.ReviewRequested, rr.RequestedReviewer.Login)
			}
		}
		if n.Stack != nil && n.StackEntry != nil {
			pr.StackID, pr.StackSize, pr.StackPos = n.Stack.Number, n.Stack.Size, n.StackEntry.Position
		}
		for _, c := range n.Comments.Nodes {
			pr.Comments = append(pr.Comments, model.Comment{Author: name(c.Author), Body: c.Body, CreatedAt: c.CreatedAt})
		}
		if len(n.Commits.Nodes) > 0 {
			if roll := n.Commits.Nodes[0].Commit.StatusCheckRollup; roll != nil {
				pr.CheckRollup = roll.State
				for _, c := range roll.Contexts.Nodes {
					pr.Checks = append(pr.Checks, c.toCheck())
				}
			}
		}
		snap.PRs = append(snap.PRs, pr)
	}
	return snap
}
