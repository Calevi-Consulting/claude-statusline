#!/usr/bin/env python3
"""Render the statusline's own output to SVG, one file per threshold state.

The point of generating rather than screenshotting: these images come from
running statusline.sh for real and parsing the ANSI it emits. Change a colour
or a threshold and `make images` produces correct SVGs — a screenshot would
silently keep showing the old ones.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "statusline.sh"
OUT_DIR = ROOT / "docs" / "img"

# The four rows of the thresholds table in the README.
STATES = [
    ("healthy", 6, 60_000, 1_000_000),
    ("smart-zone", 17, 170_000, 1_000_000),
    ("dumb-zone", 22, 220_000, 1_000_000),
    ("out-of-window", 92, 920_000, 1_000_000),
]

BG = "#0d1520"          # matches a dark terminal background
FONT = ("ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, "
        "'DejaVu Sans Mono', monospace")
FONT_SIZE = 15
CHAR_W = FONT_SIZE * 0.601   # advance width of the monospace stack above
PAD_X, PAD_Y = 16, 12

ANSI = re.compile(r"\x1b\[(?:(38;2;(\d+);(\d+);(\d+))|(\d+))m")


def fake_repo(tmp):
    """A git repo with a fixed name and branch, so output is reproducible."""
    repo = pathlib.Path(tmp) / "dummy-project"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "feature/search-filters"],
                   cwd=repo, check=True)
    return repo


def run(repo, pct, tokens, window):
    payload = json.dumps({
        "workspace": {"current_dir": str(repo)},
        "model": {"display_name": "Opus 5"},
        "context_window": {
            "used_percentage": pct,
            "context_window_size": window,
            "total_input_tokens": tokens,
        },
    })
    out = subprocess.run([str(SCRIPT)], input=payload, capture_output=True,
                         text=True, check=True).stdout
    return out.rstrip("\n")


def parse(line):
    """ANSI string -> [(text, colour, dim)] runs."""
    runs, pos, colour, dim = [], 0, "#c9d1d9", False
    for m in ANSI.finditer(line):
        if m.start() > pos:
            runs.append((line[pos:m.start()], colour, dim))
        if m.group(1):
            colour = "#{:02x}{:02x}{:02x}".format(*(int(m.group(i)) for i in (2, 3, 4)))
        else:
            code = int(m.group(5))
            if code == 0:
                colour, dim = "#c9d1d9", False
            elif code == 2:
                dim = True
        pos = m.end()
    if pos < len(line):
        runs.append((line[pos:], colour, dim))
    return [r for r in runs if r[0]]


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def svg(runs):
    cols = sum(len(t) for t, _, _ in runs)
    w = int(cols * CHAR_W + PAD_X * 2)
    h = int(FONT_SIZE * 1.6 + PAD_Y * 2)
    spans, x = [], PAD_X
    for text, colour, dim in runs:
        op = ' opacity="0.65"' if dim else ""
        # textLength pins each run to the width we computed, so the image looks
        # the same whether or not the viewer has the monospace stack installed.
        tl = len(text) * CHAR_W
        spans.append(f'<text x="{x:.1f}" y="{h/2 + FONT_SIZE*0.36:.1f}" '
                     f'fill="{colour}"{op} textLength="{tl:.1f}" '
                     f'lengthAdjust="spacingAndGlyphs" '
                     f'xml:space="preserve">{esc(text)}</text>')
        x += tl
    body = "\n  ".join(spans)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}" role="img">\n'
            f'  <rect width="{w}" height="{h}" rx="6" fill="{BG}"/>\n'
            f'  <g font-family="{FONT}" font-size="{FONT_SIZE}">\n  {body}\n  </g>\n'
            f'</svg>\n')


def main():
    if not SCRIPT.exists():
        sys.exit(f"missing {SCRIPT}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = tempfile.mkdtemp()
    try:
        repo = fake_repo(tmp)
        for name, pct, tokens, window in STATES:
            runs = parse(run(repo, pct, tokens, window))
            path = OUT_DIR / f"state-{name}.svg"
            path.write_text(svg(runs))
            plain = "".join(t for t, _, _ in runs)
            print(f"{path.relative_to(ROOT)}  <-  {plain}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
