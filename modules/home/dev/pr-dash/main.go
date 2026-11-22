package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/DSestu/NixConfig/pr-dash/internal/gh"
	"github.com/DSestu/NixConfig/pr-dash/internal/model"
	"github.com/DSestu/NixConfig/pr-dash/internal/ui"
)

var version = "dev" // set by -ldflags in default.nix

func main() {
	showVersion := flag.Bool("version", false, "print version and exit")
	dump := flag.Bool("dump", false, "print the open PRs as text and exit")
	dryRun := flag.Bool("dry-run", false, "M shows the merge plan but merges nothing")
	flag.Parse()
	if *showVersion {
		fmt.Println("pr-dash", version)
		return
	}
	if *dump {
		if err := dumpPRs(); err != nil {
			fmt.Fprintln(os.Stderr, "pr-dash:", err)
			os.Exit(1)
		}
		return
	}
	repo, err := gh.CurrentRepo()
	if err != nil {
		// stay open (ws runs pr-dash in a pane, which would close) and say why
		wd, _ := os.Getwd()
		notRepo := fmt.Errorf("not a GitHub repo: %w", err)
		run(ui.Options{Repo: wd, Fetch: func() (model.Snapshot, error) { return model.Snapshot{}, notRepo }, MergeBlocked: notRepo.Error()})
		return
	}
	opts := ui.Options{
		Branch: currentBranch(),
		Open: func(num int) error {
			// Start, not Run: the browser must not block the TUI
			return exec.Command("gh", "pr", "view", strconv.Itoa(num), "--web", "-R", repo.Owner+"/"+repo.Name).Start()
		},
		Repo:   repo.Owner + "/" + repo.Name,
		Fetch:  func() (model.Snapshot, error) { return gh.Fetch(repo) },
		DryRun: *dryRun,
	}
	if !*dryRun {
		if merger, err := gh.NewMerger(repo); err != nil {
			opts.MergeBlocked = err.Error()
		} else {
			opts.Merge = merger.Merge
		}
	}
	run(opts)
}

func currentBranch() string {
	out, err := exec.Command("git", "branch", "--show-current").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func run(opts ui.Options) {
	if _, err := tea.NewProgram(ui.New(opts)).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func dumpPRs() error {
	repo, err := gh.CurrentRepo()
	if err != nil {
		return err
	}
	snap, err := gh.Fetch(repo)
	if err != nil {
		return err
	}
	fmt.Printf("%s/%s viewer=%s prs=%d\n", repo.Owner, repo.Name, snap.Viewer, len(snap.PRs))
	for _, p := range snap.PRs {
		checks := p.CheckRollup
		if checks == "" {
			checks = "none"
		}
		stack := "-"
		if p.StackID != 0 {
			stack = fmt.Sprintf("%d:%d/%d", p.StackID, p.StackPos, p.StackSize)
		}
		fmt.Printf("#%-5d %-8s %-11s %-7s %s\n", p.Number, checks, p.Mergeable, stack, p.Title)
	}
	return nil
}
