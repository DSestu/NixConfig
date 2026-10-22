#!/usr/bin/env python3
"""Render the diagram <svg> of a diagram HTML file to a tightly cropped PNG.

    python3 render_png.py diagram.html [out.png] [--scale 2]

Keeps the page <head> (fonts, CSS), drops the page chrome, sizes the window to
the SVG viewBox, and screenshots it with headless Chromium. Needs chromium or
google-chrome on PATH, and Pillow.
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("html", type=Path)
    parser.add_argument("out", type=Path, nargs="?")
    parser.add_argument("--scale", type=int, default=2)
    args = parser.parse_args()

    source = args.html.read_text(encoding="utf-8")
    head = re.search(r"<head>(.*?)</head>", source, re.S)
    # shortcut: first <svg> to the last </svg>, fine while diagrams hold no sibling SVGs
    svg = re.search(r"<svg\b.*</svg>", source, re.S)
    if not head or not svg:
        print("no <head> or <svg> found", file=sys.stderr)
        return 2
    viewbox = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg.group(0))
    if not viewbox:
        print("svg has no viewBox", file=sys.stderr)
        return 2
    width, height = (round(float(v)) for v in viewbox.groups())

    page = (
        f"<!DOCTYPE html><html><head>{head.group(1)}"
        "<style>html,body{margin:0;padding:0;display:block;min-height:0}"
        f"svg{{display:block;width:{width}px;height:{height}px;min-width:0}}</style>"
        f"</head><body>{svg.group(0)}</body></html>"
    )
    browser = shutil.which("chromium") or shutil.which("google-chrome")
    if not browser:
        print("chromium or google-chrome not found", file=sys.stderr)
        return 2

    out = (args.out or args.html.with_suffix(".png")).resolve()
    with tempfile.TemporaryDirectory() as tmp:
        page_path = Path(tmp) / "page.html"
        page_path.write_text(page, encoding="utf-8")
        subprocess.run(
            [
                browser, "--headless", "--disable-gpu", "--no-sandbox",
                "--hide-scrollbars", f"--force-device-scale-factor={args.scale}",
                # headless Chromium eats part of the window height, so render taller and crop
                f"--window-size={width},{height + 200}", "--virtual-time-budget=5000",
                f"--screenshot={out}", page_path.as_uri(),
            ],
            check=True, capture_output=True, timeout=120,
        )
    from PIL import Image

    with Image.open(out) as image:
        image.crop((0, 0, width * args.scale, height * args.scale)).save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
