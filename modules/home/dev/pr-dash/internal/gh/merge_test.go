package gh

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/cli/go-gh/v2/pkg/repository"
)

func testMerger(t *testing.T, h http.HandlerFunc) *Merger {
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return &Merger{HTTP: srv.Client(), Base: srv.URL + "/", Owner: "DSestu", Name: "NixConfig", Poll: time.Millisecond, Timeout: time.Second}
}

func TestMergePendingThenMerged(t *testing.T) {
	polls := 0
	m := testMerger(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == "PUT" && r.URL.Path == "/repos/DSestu/NixConfig/pulls/275/merge-async":
			var body map[string]string
			b, _ := io.ReadAll(r.Body)
			_ = json.Unmarshal(b, &body)
			if body["merge_method"] != "squash" || body["sha"] != "abc" {
				t.Errorf("body %v", body)
			}
			w.WriteHeader(http.StatusAccepted)
			io.WriteString(w, `{"status":"pending","details":{"uuid":"u1"}}`)
		case r.Method == "GET" && r.URL.Path == "/repos/DSestu/NixConfig/pulls/275/merge-async/u1":
			polls++
			if polls < 3 {
				io.WriteString(w, `{"status":"pending","details":{"uuid":"u1"}}`)
				return
			}
			io.WriteString(w, `{"status":"merged","details":{"message":"Pull request was merged."}}`)
		default:
			t.Errorf("unexpected %s %s", r.Method, r.URL.Path)
		}
	})
	res, err := m.Merge(275, "abc", true)
	if err != nil || res.Status != "merged" || polls != 3 {
		t.Fatalf("res %+v err %v polls %d", res, err, polls)
	}
}

func TestMergeFailedWhilePolling(t *testing.T) {
	m := testMerger(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "PUT" {
			w.WriteHeader(http.StatusAccepted)
			io.WriteString(w, `{"status":"pending","details":{"uuid":"u2"}}`)
			return
		}
		io.WriteString(w, `{"status":"failed","details":{"message":"Merge conflict: the pull request could not be merged."}}`)
	})
	res, err := m.Merge(290, "", false)
	if err != nil || res.Status != "failed" || res.Message == "" {
		t.Fatalf("res %+v err %v", res, err)
	}
}

func TestMergeFallsBackToClassicForUnstacked(t *testing.T) {
	m := testMerger(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/repos/DSestu/NixConfig/pulls/276/merge-async":
			w.WriteHeader(http.StatusNotFound)
		case "/repos/DSestu/NixConfig/pulls/276/merge":
			io.WriteString(w, `{"merged":true,"message":"Pull Request successfully merged"}`)
		}
	})
	if res, err := m.Merge(276, "", false); err != nil || res.Status != "merged" {
		t.Fatalf("res %+v err %v", res, err)
	}
	if _, err := m.Merge(276, "", true); err == nil {
		t.Fatal("a stacked PR must not fall back to the classic endpoint")
	}
}

func TestMergeAllowed(t *testing.T) {
	if MergeAllowed(repository.Repository{Host: "github.com", Owner: "DSestu", Name: "x"}) != nil {
		t.Error("DSestu should be allowed")
	}
	if MergeAllowed(repository.Repository{Host: "github.com", Owner: "sencrop", Name: "x"}) == nil {
		t.Error("sencrop must be refused")
	}
}
