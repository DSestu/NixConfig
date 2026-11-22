package ui

import (
	"fmt"
	"net/url"
	"regexp"
	"strings"

	"charm.land/glamour/v2"
	"github.com/charmbracelet/x/ansi"
	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/text"
)

// mdCache holds rendered markdown, keyed by width and source text;
// glamour is too slow to run on every frame.
var mdCache = map[string]string{}

// renderMarkdown renders md for the preview. Links show only their text, as a
// clickable OSC 8 hyperlink: bump PR bodies are lists of commit links, and
// printing every URL turned each line into three.
// dim renders body text in the sub colour, for an unfocused preview.
func renderMarkdown(md string, w int, dim bool) string {
	key := fmt.Sprintf("%d\x00%v\x00%s", w, dim, md)
	if s, ok := mdCache[key]; ok {
		return s
	}
	out := md
	r, err := glamour.NewTermRenderer(
		glamour.WithStyles(glamourStyle(dim)),
		glamour.WithWordWrap(w),
		glamour.WithEmoji(),
		glamour.WithInlineTableLinks(true), // footnotes would list hidden URLs as "[1]: text"
		glamour.WithChromaFormatter("terminal16m"),
	)
	if err == nil {
		if s, err := r.Render(labelBareURLs(md)); err == nil {
			out = trimBlank(linkGap.ReplaceAllString(s, "$1$2\x1b[m"))
		}
	}
	mdCache[key] = out
	return out
}

// linkGap is the space glamour always writes between a link's text and its
// (here hidden) URL: hyperlink close, SGR codes, one space, a reset.
var linkGap = regexp.MustCompile("(\x1b\\]8;;\x07)((?:\x1b\\[[0-9;]*m)*) \x1b\\[m")

// trimBlank drops leading and trailing lines that are only (styled) spaces.
func trimBlank(s string) string {
	l := strings.Split(s, "\n")
	blank := func(x string) bool { return strings.TrimSpace(ansi.Strip(x)) == "" }
	for len(l) > 0 && blank(l[0]) {
		l = l[1:]
	}
	for len(l) > 0 && blank(l[len(l)-1]) {
		l = l[:len(l)-1]
	}
	return strings.Join(l, "\n")
}

// labelBareURLs rewrites bare and <angle> URLs as [short label](url), so they
// keep a visible label once link URLs are hidden.
func labelBareURLs(md string) string {
	src := []byte(md)
	doc := goldmark.New(goldmark.WithExtensions(extension.Linkify)).Parser().Parse(text.NewReader(src))
	var b strings.Builder
	at := 0
	_ = ast.Walk(doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		al, ok := n.(*ast.AutoLink)
		if !entering || !ok || al.AutoLinkType != ast.AutoLinkURL {
			return ast.WalkContinue, nil
		}
		label := string(al.Label(src))
		// shortcut: finds the next textual match, so the same URL inside an
		// earlier code span would be rewritten instead; fine for PR bodies.
		i := strings.Index(md[at:], label)
		if i < 0 {
			return ast.WalkContinue, nil
		}
		start, end := at+i, at+i+len(label)
		if start > 0 && md[start-1] == '<' && end < len(md) && md[end] == '>' {
			start, end = start-1, end+1
		}
		b.WriteString(md[at:start])
		fmt.Fprintf(&b, "[%s](%s)", shortURL(string(al.URL(src))), string(al.URL(src)))
		at = end
		return ast.WalkContinue, nil
	})
	b.WriteString(md[at:])
	return b.String()
}

// shortURL is a compact label for a URL: owner/repo#12, owner/repo@abc1234, …
func shortURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return raw
	}
	p := strings.Split(strings.Trim(u.Path, "/"), "/")
	if u.Host == "github.com" && len(p) >= 2 {
		repo := p[0] + "/" + p[1]
		switch {
		case len(p) == 2:
			return repo
		case len(p) >= 4 && (p[2] == "pull" || p[2] == "issues"):
			return repo + "#" + p[3]
		case len(p) >= 4 && p[2] == "commit":
			return repo + "@" + p[3][:min(7, len(p[3]))]
		case len(p) >= 4 && p[2] == "compare":
			a, b, _ := strings.Cut(p[3], "...")
			return repo + " " + a[:min(7, len(a))] + "…" + b[:min(7, len(b))]
		case len(p) >= 5 && p[2] == "releases" && p[3] == "tag":
			return repo + " " + p[4]
		}
		return elide(repo + "/" + strings.Join(p[2:], "/"))
	}
	return elide(u.Host + u.Path)
}

// elide shortens s to 40 cells by cutting its middle, keeping both ends readable.
func elide(s string) string {
	r := []rune(strings.TrimSuffix(s, "/"))
	if len(r) <= 40 {
		return string(r)
	}
	return string(r[:24]) + "…" + string(r[len(r)-15:])
}
