package gh

import (
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/DSestu/NixConfig/pr-dash/internal/model"
)

// testdata/prs.json: a real NixConfig response (297, 296, 295) plus hand-made
// PRs 901-903, because no NixConfig PR has had a stack or a check yet.
func load(t *testing.T) model.Snapshot {
	t.Helper()
	raw, err := os.ReadFile("testdata/prs.json")
	if err != nil {
		t.Fatal(err)
	}
	var env struct{ Data response }
	if err := json.Unmarshal(raw, &env); err != nil {
		t.Fatal(err)
	}
	return convert(env.Data)
}

func TestConvert(t *testing.T) {
	snap := load(t)
	if snap.Viewer != "DSestu" || len(snap.PRs) != 6 {
		t.Fatalf("viewer %q, %d PRs", snap.Viewer, len(snap.PRs))
	}
	byNum := map[int]model.PR{}
	for _, p := range snap.PRs {
		byNum[p.Number] = p
	}

	bump := byNum[297]
	if bump.Author != "github-actions" {
		t.Errorf("297 author %q", bump.Author)
	}
	if bump.StackID != 0 || bump.CheckRollup != "" || len(bump.Checks) != 0 {
		t.Errorf("297 should be unstacked with no checks: %+v", bump)
	}

	base := byNum[901]
	if base.StackID != 7 || base.StackSize != 2 || base.StackPos != 1 {
		t.Errorf("901 stack %d %d/%d", base.StackID, base.StackPos, base.StackSize)
	}
	if len(base.Checks) != 2 || base.Checks[0].State != model.CheckPass || base.Checks[0].Duration != 150*time.Second {
		t.Errorf("901 checks %+v", base.Checks)
	}
	if base.Checks[1].Name != "ci/legacy" || base.Checks[1].State != model.CheckPass {
		t.Errorf("901 status context %+v", base.Checks[1])
	}
	if len(base.Comments) != 1 || base.Comments[0].Author != "octocat" {
		t.Errorf("901 comments %+v", base.Comments)
	}

	top := byNum[902]
	if top.Mergeable != "CONFLICTING" || top.StackPos != 2 {
		t.Errorf("902 %s pos %d", top.Mergeable, top.StackPos)
	}
	if top.Checks[0].State != model.CheckFail || top.Checks[1].State != model.CheckPending || top.Checks[1].Duration != 0 {
		t.Errorf("902 checks %+v", top.Checks)
	}
	if len(top.ReviewRequested) != 1 || top.ReviewRequested[0] != "DSestu" {
		t.Errorf("902 review requests %v", top.ReviewRequested)
	}

	if !byNum[903].IsDraft || byNum[903].Mergeable != "UNKNOWN" {
		t.Errorf("903 %+v", byNum[903])
	}
}
