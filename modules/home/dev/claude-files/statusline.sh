#!/usr/bin/env bash
# Claude Code status line styled after the user's Tide fish prompt.
# Left half mirrors tide_left_prompt_items (os, pwd, git); the rest shows
# model, context window usage, session cost/churn, and rate-limit usage.
set -u

# Nix-substituted: jq, git, gawk, coreutils. Claude Code runs the status line
# with the user's PATH, which may not have them (e.g. inside `ns` sandboxes).
PATH="@binPath@:$PATH"

input=$(cat)

fg() { printf '\033[38;2;%d;%d;%dm' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
bg() { printf '\033[48;2;%d;%d;%dm' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
reset=$'\033[0m'
sep=$''

prev_bg=""
out=""
segment() { # $1=bg $2=fg $3=text
  if [ -n "$prev_bg" ]; then
    out+="$(bg "$1")$(fg "$prev_bg")${sep}"
  else
    out+="$(bg "$1")"
  fi
  out+="$(fg "$2") $3 "
  prev_bg="$1"
}

eval "$(printf '%s' "$input" | jq -r '
  def q: @sh;
  "cwd=\(.workspace.current_dir // .cwd // "" | q)",
  "model=\(.model.display_name // "" | q)",
  "style=\(.output_style.name // "" | q)",
  "ctx_pct=\(.context_window.used_percentage // "" | tostring | q)",
  "ctx_used=\(.context_window.total_input_tokens // 0 | q)",
  "ctx_size=\(.context_window.context_window_size // 0 | q)",
  "cost=\(.cost.total_cost_usd // "" | tostring | q)",
  "lines_add=\(.cost.total_lines_added // 0 | q)",
  "lines_del=\(.cost.total_lines_removed // 0 | q)",
  "rl5=\(.rate_limits.five_hour.used_percentage // "" | tostring | q)",
  "rl5_reset=\(.rate_limits.five_hour.resets_at // "" | tostring | q)",
  "rl7=\(.rate_limits.seven_day.used_percentage // "" | tostring | q)",
  "rl7_reset=\(.rate_limits.seven_day.resets_at // "" | tostring | q)"
')"

# os segment (tide_os_*: nix icon, D4D4D4 bg / C70036 fg)
segment D4D4D4 C70036 $''

# pwd segment (tide_pwd_*: 3465A4 bg / E4E4E4 fg), last two components
short=${cwd/#$HOME/\~}
case "$short" in
  '~') disp=$'' ;;
  *) disp=$(printf '%s' "$short" | awk -F/ '{n=NF; if (n>2) printf "%s/%s", $(n-1), $n; else print $0}') ;;
esac
segment 3465A4 E4E4E4 "$disp"

# git segment (tide_git_*: 4E9A06 clean / C4A000 dirty, black fg)
if branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$cwd" describe --tags --exact-match 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null); then
  if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
    gbg=C4A000
  else
    gbg=4E9A06
  fi
  segment "$gbg" 000000 "$(printf '') $branch"
fi

# model segment (tide_context_*: 444444 bg / D7AF87 fg)
[ -n "$model" ] && segment 444444 D7AF87 "$(printf '\U000f0e73') $model"

# context window (tide_status_*: 2E3436 bg, green → amber → red as it fills)
if [ -n "$ctx_pct" ]; then
  if [ "$ctx_pct" -ge 90 ] 2>/dev/null; then cfg=FF5F5F
  elif [ "$ctx_pct" -ge 70 ] 2>/dev/null; then cfg=FFFF00
  else cfg=4E9A06; fi
  label=$(awk -v u="$ctx_used" -v w="$ctx_size" 'BEGIN{
    if (w >= 1000000) wl = sprintf("%.0fM", w/1000000); else wl = sprintf("%.0fk", w/1000);
    printf "%.0fk/%s", u/1000, wl }')
  segment 2E3436 "$cfg" "$(printf '\U000f035b') $label ${ctx_pct}%"
fi

# session cost + diff churn (tide_cmd_duration_*: C4A000 bg / black fg)
if [ -n "$cost" ]; then
  segment C4A000 000000 "$(awk -v c="$cost" 'BEGIN{printf "$%.2f", c}') +${lines_add}/-${lines_del}"
fi

# rate limits: 5-hour window (with reset countdown) and 7-day window
fmt_reset() { # epoch -> "2h14m"
  [ -n "$1" ] || return
  awk -v r="$1" -v n="$(date +%s)" 'BEGIN{
    d = r - n; if (d < 0) d = 0;
    h = int(d/3600); m = int((d%3600)/60);
    if (h > 0) printf "%dh%02dm", h, m; else printf "%dm", m }'
}
rl_color() { # pct -> fg hex
  if [ "$1" -ge 90 ] 2>/dev/null; then printf FF5F5F
  elif [ "$1" -ge 70 ] 2>/dev/null; then printf FFFF00
  else printf 87D7FF; fi
}
if [ -n "$rl5" ]; then
  segment 3A3A3A "$(rl_color "$rl5")" "$(printf '\U000f0954') 5h ${rl5}%$( [ -n "$rl5_reset" ] && printf ' ↻%s' "$(fmt_reset "$rl5_reset")" )"
fi
if [ -n "$rl7" ]; then
  segment 303030 "$(rl_color "$rl7")" "7d ${rl7}%$( [ -n "$rl7_reset" ] && printf ' ↻%s' "$(fmt_reset "$rl7_reset")" )"
fi

# output style, when not default
[ -n "$style" ] && [ "$style" != "default" ] && segment 808000 000000 "$style"

printf '%s%s%s%s' "$out" "$(fg "$prev_bg")" "$reset$sep" "$reset"
