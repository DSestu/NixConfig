package gh

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/cli/go-gh/v2/pkg/api"
	"github.com/cli/go-gh/v2/pkg/repository"
)

// MergeAllowed refuses hosts other than github.com: Merger talks to api.github.com only.
func MergeAllowed(repo repository.Repository) error {
	if repo.Host != "github.com" {
		return fmt.Errorf("merging is disabled outside github.com (this is %s)", repo.Host)
	}
	return nil
}

// Merger squash-merges PRs. Never uses admin merge: neither endpoint below can bypass rules.
type Merger struct {
	HTTP    *http.Client
	Base    string // API root, ending in "/"
	Owner   string
	Name    string
	Poll    time.Duration
	Timeout time.Duration
}

func NewMerger(repo repository.Repository) (*Merger, error) {
	if err := MergeAllowed(repo); err != nil {
		return nil, err
	}
	c, err := api.DefaultHTTPClient()
	if err != nil {
		return nil, err
	}
	return &Merger{HTTP: c, Base: "https://api.github.com/", Owner: repo.Owner, Name: repo.Name,
		Poll: time.Second, Timeout: 5 * time.Minute}, nil
}

type asyncResult struct {
	Status  string
	Message string // error bodies
	Details struct{ Message, UUID string }
}

// Merge squash-merges PR num (and, for a stacked PR, everything below it).
// sha pins the expected head commit.
func (m *Merger) Merge(num int, sha string, stacked bool) (model.MergeResult, error) {
	path := fmt.Sprintf("repos/%s/%s/pulls/%d/merge-async", m.Owner, m.Name, num)
	body := map[string]string{"merge_method": "squash", "merge_action": "default"}
	if sha != "" {
		body["sha"] = sha
	}
	var res asyncResult
	code, err := m.do("PUT", path, body, &res)
	if err != nil {
		return model.MergeResult{}, err
	}
	switch {
	case code == http.StatusNotFound && !stacked:
		return m.classic(num, sha) // async merge not enabled for this repo
	case code == http.StatusNotFound || code == http.StatusUnprocessableEntity:
		return model.MergeResult{}, fmt.Errorf("merge-async: HTTP %d: %s", code, res.Message)
	}
	deadline := time.Now().Add(m.Timeout)
	for res.Status == "pending" {
		if time.Now().After(deadline) {
			return model.MergeResult{}, fmt.Errorf("still pending after %v; check the PR on GitHub", m.Timeout)
		}
		uuid := res.Details.UUID
		time.Sleep(m.Poll)
		res = asyncResult{}
		if code, err = m.do("GET", path+"/"+uuid, nil, &res); err != nil {
			return model.MergeResult{}, err
		}
		if code != http.StatusOK {
			return model.MergeResult{}, fmt.Errorf("polling merge: HTTP %d", code)
		}
	}
	msg := res.Details.Message
	if msg == "" {
		msg = res.Message
	}
	return model.MergeResult{Status: res.Status, Message: msg}, nil
}

// classic is the synchronous squash-merge endpoint, for unstacked PRs only.
func (m *Merger) classic(num int, sha string) (model.MergeResult, error) {
	body := map[string]string{"merge_method": "squash"}
	if sha != "" {
		body["sha"] = sha
	}
	var res struct {
		Merged  bool
		Message string
	}
	code, err := m.do("PUT", fmt.Sprintf("repos/%s/%s/pulls/%d/merge", m.Owner, m.Name, num), body, &res)
	if err != nil {
		return model.MergeResult{}, err
	}
	if code == http.StatusOK && res.Merged {
		return model.MergeResult{Status: "merged", Message: res.Message}, nil
	}
	return model.MergeResult{Status: "failed", Message: res.Message}, nil
}

// do sends a JSON request and decodes any JSON reply into out, whatever the status code.
func (m *Merger) do(method, path string, body any, out any) (int, error) {
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			return 0, err
		}
	}
	req, err := http.NewRequest(method, m.Base+path, &buf)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Content-Type", "application/json")
	resp, err := m.HTTP.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	_ = json.NewDecoder(resp.Body).Decode(out) // error replies may have no JSON body
	return resp.StatusCode, nil
}
