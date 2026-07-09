# repo-report.nix — put in your home-manager config and add to home.packages
{pkgs}:
pkgs.writers.writePython3Bin "repo-report" {
  libraries = [pkgs.python3Packages.rich];
  flakeIgnore = [
    "E501" "E402" "E401" "E203" "E226" "E231" "E241" "E261" "E265"
    "E302" "E305" "E306" "E701" "E702" "E703" "E711" "E721"
    "E722" "E731" "E741" "W291" "W292" "W293"
  ];
} ''
  import subprocess, sys, os, termios, tty, select
  from concurrent.futures import ThreadPoolExecutor
  from pathlib import Path
  from rich.console import Console
  from rich.live import Live
  from rich.table import Table
  from rich.text import Text

  MODES = [
      "local branch  →  its upstream",
      "local default →  remote default",
      "local branch  →  local default",
  ]

  def run(cmd, cwd):
      r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
      return r.stdout.strip()

  def fetch_repo(path):
      subprocess.run(["git", "fetch", "--all", "--quiet"], cwd=path,
                     stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)

  def detect_default(path):
      r = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], path)
      if r:
          return r.split("/", 1)[1] if "/" in r else r
      for b in ("main", "master"):
          if run(["git", "rev-parse", "--verify", "--quiet", b], path):
              return b
      return None

  def scan_repo(path):
      branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], path)
      upstream = run(["git", "rev-parse", "--abbrev-ref", "@{u}"], path) or None
      default = detect_default(path)
      dirty = len([l for l in run(["git", "status", "--porcelain"], path).splitlines() if l])
      added = removed = 0
      for line in run(["git", "diff", "HEAD", "--numstat"], path).splitlines():
          parts = line.split("\t")
          if len(parts) >= 2:
              try: added += int(parts[0])
              except: pass
              try: removed += int(parts[1])
              except: pass
      return dict(name=path.name, path=path, branch=branch, upstream=upstream,
                  default=default, dirty=dirty, added=added, removed=removed)

  def ahead_behind(path, base, head):
      if not base or not head:
          return (0, 0)
      a = run(["git", "rev-list", "--count", f"{base}..{head}"], path)
      b = run(["git", "rev-list", "--count", f"{head}..{base}"], path)
      try: a = int(a)
      except: a = 0
      try: b = int(b)
      except: b = 0
      return (a, b)

  def pair_for_mode(repo, mode_idx):
      if mode_idx == 0:
          return repo["branch"], repo["upstream"]
      if mode_idx == 1:
          d = repo["default"]
          return d, (f"origin/{d}" if d else None)
      return repo["branch"], repo["default"]

  def build_table(repos, mode_idx, status_line):
      t = Table(
          title=f"[bold]repo-report[/]   mode {mode_idx+1}/{len(MODES)}: [cyan]{MODES[mode_idx]}[/]",
          caption=status_line,
          caption_style="bright_black",
          header_style="bold",
          expand=False,
      )
      t.add_column("", no_wrap=True)
      t.add_column("repo", style="bold")
      t.add_column("head")
      t.add_column("")
      t.add_column("base")
      t.add_column("↑", justify="right")
      t.add_column("↓", justify="right")
      t.add_column("±", justify="right")
      t.add_column("+", justify="right")
      t.add_column("-", justify="right")
      for r in repos:
          head, base = pair_for_mode(r, mode_idx)
          ahead, behind = ahead_behind(r["path"], base, head) if (head and base) else (0, 0)
          missing = not (head and base)
          clean = (not missing) and r["dirty"] == 0 and ahead == 0 and behind == 0
          if missing:
              icon = Text("○", style="bright_black")
          elif clean:
              icon = Text("●", style="green")
          else:
              icon = Text("◆", style="yellow")
          def col(v, style):
              return Text(str(v), style=style if v else "bright_black")
          t.add_row(
              icon,
              r["name"],
              Text(head or "-", style="cyan" if head else "bright_black"),
              Text("→", style="bright_black"),
              Text(base or "-", style="bright_black"),
              col(ahead,  "green"),
              col(behind, "yellow"),
              col(r["dirty"], "red"),
              col(r["added"], "green"),
              col(r["removed"], "red"),
          )
      return t

  def get_key(fd, timeout=0.1):
      r, _, _ = select.select([fd], [], [], timeout)
      if not r:
          return None
      data = os.read(fd, 8)
      if not data:
          return None
      if data == b"\x1b":
          r2, _, _ = select.select([fd], [], [], 0.05)
          if r2:
              data += os.read(fd, 8)
      if data.startswith(b"\x1b["):
          return {b"\x1b[A": "up", b"\x1b[B": "down",
                  b"\x1b[C": "right", b"\x1b[D": "left"}.get(data[:3], "esc")
      if data == b"\x1b":
          return "esc"
      try:
          return data.decode(errors="replace")[0]
      except Exception:
          return None

  def scan_all(dirs):
      with ThreadPoolExecutor(max_workers=32) as ex:
          list(ex.map(fetch_repo, dirs))
      with ThreadPoolExecutor(max_workers=32) as ex:
          return sorted(ex.map(scan_repo, dirs), key=lambda r: r["name"].lower())

  def main():
      root = Path(sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/github"))
      if not root.is_dir():
          print(f"not a directory: {root}", file=sys.stderr)
          sys.exit(1)
      dirs = sorted([p for p in root.iterdir() if (p / ".git").exists()])
      if not dirs:
          print(f"no git repos in {root}", file=sys.stderr)
          sys.exit(1)

      console = Console()
      console.print(f"[bold]scanning {len(dirs)} repos in {root} (parallel)...[/]")
      repos = scan_all(dirs)

      mode_idx = 0
      status = "←/→ switch mode   r refresh   q quit"

      fd = sys.stdin.fileno()
      old = termios.tcgetattr(fd)
      try:
          tty.setcbreak(fd)
          with Live(build_table(repos, mode_idx, status),
                    console=console, refresh_per_second=15, screen=True) as live:
              while True:
                  k = get_key(fd, 0.1)
                  if k == "q":
                      break
                  if k == "left":
                      mode_idx = (mode_idx - 1) % len(MODES)
                      live.update(build_table(repos, mode_idx, status))
                  elif k == "right":
                      mode_idx = (mode_idx + 1) % len(MODES)
                      live.update(build_table(repos, mode_idx, status))
                  elif k == "r":
                      live.update(build_table(repos, mode_idx, "refreshing in parallel..."))
                      repos = scan_all(dirs)
                      live.update(build_table(repos, mode_idx, status))
      finally:
          termios.tcsetattr(fd, termios.TCSADRAIN, old)

  if __name__ == "__main__":
      main()
''
