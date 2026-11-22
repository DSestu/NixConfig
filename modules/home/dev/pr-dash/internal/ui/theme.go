package ui

// Charm Glow, the approved look (.impeccable/mocks/decision/theme/charm-glow.html).
// Every colour in pr-dash is defined here and nowhere else.

import (
	"image/color"

	"charm.land/glamour/v2/ansi"
	"charm.land/glamour/v2/styles"
	"charm.land/lipgloss/v2"
)

var (
	cBg        = lipgloss.Color("#16121f") // violet-black ground
	cText      = lipgloss.Color("#e8e3f5")
	cSub       = lipgloss.Color("#a49dbb")
	cDim       = lipgloss.Color("#6e6585")
	cBorder    = lipgloss.Color("#3a3350")
	cPink      = lipgloss.Color("#ff5fd2")
	cPinkDim   = lipgloss.Color("#b9489c")
	cViolet    = lipgloss.Color("#9d7cff")
	cVioletDim = lipgloss.Color("#745cbc")
	cMint      = lipgloss.Color("#5fe3b0") // pass
	cMintDim   = lipgloss.Color("#49a484")
	cCoral     = lipgloss.Color("#ff6b81") // fail
	cCoralDim  = lipgloss.Color("#b95064")
	cAmber     = lipgloss.Color("#ffcf5c") // running, marked
	cAmberDim  = lipgloss.Color("#b9964a")
	cSel       = lipgloss.Color("#2a2140") // cursor row
	cBar       = lipgloss.Color("#231c33") // merge bar
)

func fg(c color.Color) lipgloss.Style { return lipgloss.NewStyle().Foreground(c) }

func chip(bg color.Color) lipgloss.Style { return fg(cBg).Background(bg).Bold(true) }

var (
	sText      = fg(cText)
	sSub       = fg(cSub)
	sDim       = fg(cDim)
	sBorder    = fg(cBorder)
	sPink      = fg(cPink)
	sPinkDim   = fg(cPinkDim)
	sViolet    = fg(cViolet)
	sVioletDim = fg(cVioletDim)
	sMint      = fg(cMint)
	sMintDim   = fg(cMintDim)
	sCoral     = fg(cCoral)
	sCoralDim  = fg(cCoralDim)
	sAmber     = fg(cAmber)
	sAmberDim  = fg(cAmberDim)
	sTabOn     = chip(cViolet)
	sChipFail  = chip(cCoral)
	sChipWarn  = chip(cAmber)
	sBar       = lipgloss.NewStyle().Background(cBar)
)

// title pill gradient, pink to violet
var pillStops = []color.Color{cPink, cViolet}

// glamourStyle is the dark glamour style recoloured to Charm Glow, with no margins.
func glamourStyle() ansi.StyleConfig {
	s := styles.DarkStyleConfig
	str := func(v string) *string { return &v }
	zero := uint(0)
	s.Document.Margin = &zero
	s.Document.BlockPrefix, s.Document.BlockSuffix = "", ""
	s.Document.Color = str("#e8e3f5")
	s.Heading.Color = str("#ff5fd2")
	s.H1.Color, s.H1.BackgroundColor = str("#16121f"), str("#9d7cff")
	s.H6.Color = str("#a49dbb")
	s.Link.Color = str("#9d7cff")
	s.LinkText.Color = str("#ff5fd2")
	s.Code.Color, s.Code.BackgroundColor = str("#ff5fd2"), str("#2a2140")
	s.CodeBlock.Margin = &zero
	s.CodeBlock.Color = str("#a49dbb")
	s.HorizontalRule.Color = str("#3a3350")
	s.BlockQuote.Color = str("#a49dbb")
	return s
}
