# Claude Code statusline: context, branch and a decision tree

How to reproduce, on a clean workstation, the statusline that shows directory, branch,
model, context usage and a suggestion of what to do when the context fills up.

Verified against Claude Code **2.1.266** (macOS). Everything is files under `~/.claude/`;
nothing needs to be installed.

```
dummy-project · feature/search-filters · Opus 5 · █░░░░░░░░░ 6% 60k/1.0M
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 17% 170k/1.0M · smart zone limit · /arbol
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 22% 220k/1.0M · dumb zone · /clear if disposable, else /handoff
dummy-project · feature/search-filters · Opus 5 · █████████░ 92% 920k/1.0M · out of window · /compact or /clear NOW
```

> The command is named `/arbol` ("tree" in Spanish) because that is the filename the hint
> points at. Rename the file and the `hint` strings together if you prefer `/tree`.

## The thresholds: absolute tokens, not a percentage

The hint distinguishes **two risks that are not the same thing**:

- **Leaving the smart zone** — reasoning quality degrades well before the window fills,
  and that point **does not scale with window size**. It is a threshold in **absolute
  tokens** (`SZ`, **200k** by default, configurable).
- **Running out of window** — that one *is* a percentage, and it is what triggers
  auto-compact.

Conflating them is an easy mistake: a "65% of context" threshold is 130k tokens on a 200k
window (reasonable by accident) but **650k** on a 1M one, long after quality is gone. That
is why `SZ` is absolute and the percentage only covers the end of the window. The default
is **200k tokens**.

| Condition | Colour | Hint | Tree branch |
|---|---|---|---|
| `tok < 0.8·SZ` (< 160k) | green | — | stay in the session |
| `tok ≥ 0.8·SZ` (≥ 160k) | yellow | `smart zone limit · /arbol` | run it and decide |
| `tok ≥ SZ` (≥ 200k) | yellow | `dumb zone · /clear if disposable, else /handoff` | `/clear` or `/handoff` |
| `tok ≥ 1.5·SZ` (≥ 300k) | red | same as above | `/clear` or `/handoff` |
| `pct ≥ 80` | yellow | `window limit · /clear or /handoff` | `/clear` or `/handoff` |
| `pct ≥ 90` | red | `out of window · /compact or /clear NOW` | `/compact` |

The most urgent condition wins. Colour follows the hint, so both tell the same story.

**On a 200k window the default `SZ` is never reached**: at 160k tokens you are already at
80% and `window limit` fires. In practice those models are covered by the percentage
thresholds alone. If you want the smart-zone warning there too, lower it with `perModel`
(see below).

`SZ` is **judgement, not measurement**: 200k is a starting point, not a number I validated.
It changes without touching the script — see
[Configuring the smart zone](#configuring-the-smart-zone).

---

## Requirements

- Claude Code 2.1.x or later (`claude --version`).
- `python3` on PATH. On macOS it ships with the Command Line Tools; on Linux it is the
  distro's `python3` package.
- A terminal with 24-bit colour support (iTerm2, Ghostty, Kitty, WezTerm, recent
  Terminal.app, Windows Terminal). Without truecolor the colours fall back to the nearest
  match, but nothing breaks.

---

## What it shows, and where each field comes from

Claude Code invokes the `statusLine` command and passes it, over **stdin**, a JSON blob
with the session state. The fields this script uses:

| Payload field | Rendered as |
|---|---|
| `workspace.current_dir` | directory name |
| `model.display_name` | model |
| `context_window.used_percentage` | bar + percentage |
| `context_window.total_input_tokens` / `.context_window_size` | `700k/1.0M` |

**The branch is not in the payload.** `workspace` carries `current_dir`, `project_dir`,
`added_dirs`, `git_worktree` (a path) and `repo` (`{host, owner, name}`) — no field with
the branch name. So the script reads it from `.git/HEAD` directly, without invoking `git`:
the statusline refreshes often and one fork per refresh is noticeable. It handles worktrees
(where `.git` is a file containing `gitdir:`) and detached HEAD (shows `@<sha7>`).

---

## Installation

> If you cloned this repository, `./install.sh` does all of the following for you. The
> steps below are the manual path, and the reference for what the installer touches.

### 1. The script

```bash
mkdir -p ~/.claude
cat > ~/.claude/statusline.sh <<'SH'
#!/bin/sh
# Reads the statusline payload once, forwards it to the Orca hook (telemetry;
# that script prints nothing) and prints the context counter.
payload=$(cat)
[ -z "$payload" ] && exit 0

orca=~/.orca/agent-hooks/claude-statusline.sh
if [ -x "$orca" ]; then
  printf '%s' "$payload" | /bin/sh "$orca" >/dev/null 2>&1 &
fi

printf '%s' "$payload" | python3 -c '
import json, os, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

O, R, DIM = "\033[38;2;255;140;0m", "\033[0m", "\033[2m"
YEL, RED, GREY = "\033[38;2;220;180;60m", "\033[38;2;220;80;80m", "\033[38;2;150;150;150m"
GRN = "\033[38;2;120;200;120m"

CFG_PATH = os.path.join(os.path.expanduser("~"), ".claude", "statusline.json")
DEFAULTS = {"smartZoneTokens": 200_000, "windowWarnPct": 80, "windowCriticalPct": 90}


def load_cfg():
    """Optional config. Never breaks the statusline: on a bad file it returns
    the defaults and flags the error so it can be shown."""
    try:
        if not os.path.isfile(CFG_PATH):
            return {}, False
        with open(CFG_PATH) as f:
            loaded = json.load(f)
        return (loaded, False) if isinstance(loaded, dict) else ({}, True)
    except Exception:
        return {}, True


def num(value, fallback):
    try:
        n = int(value)
        return n if n > 0 else fallback
    except (TypeError, ValueError):
        return fallback


def smart_zone(cfg, model):
    """Precedence: env > perModel > smartZoneTokens > default."""
    env = os.environ.get("CLAUDE_SMART_ZONE_TOKENS")
    if env:
        return num(env, DEFAULTS["smartZoneTokens"])
    base = num(cfg.get("smartZoneTokens"), DEFAULTS["smartZoneTokens"])
    per = cfg.get("perModel")
    if isinstance(per, dict) and model in per:
        return num(per[model], base)
    return base


def git_branch(start):
    """Reads the branch from .git/HEAD without invoking git (worktrees included)."""
    try:
        d = os.path.abspath(start)
        while True:
            g = os.path.join(d, ".git")
            if os.path.isdir(g):
                head = os.path.join(g, "HEAD")
                break
            if os.path.isfile(g):
                with open(g) as f:
                    line = f.read().strip()
                if not line.startswith("gitdir:"):
                    return None
                gd = line.split(":", 1)[1].strip()
                if not os.path.isabs(gd):
                    gd = os.path.join(d, gd)
                head = os.path.join(gd, "HEAD")
                break
            parent = os.path.dirname(d)
            if parent == d:
                return None
            d = parent
        with open(head) as f:
            ref = f.read().strip()
        if ref.startswith("ref: refs/heads/"):
            return ref[len("ref: refs/heads/"):]
        return "@" + ref[:7] if ref else None
    except Exception:
        return None


cfg, cfg_broken = load_cfg()
parts = []

d_ = d.get("workspace", {}).get("current_dir") or ""
if d_:
    parts.append(f"{O}{os.path.basename(d_)}{R}")

br = git_branch(d_) if d_ else None
if br:
    if len(br) > 34:
        br = br[:31] + "..."
    parts.append(f"{GREY}{br}{R}")

model = (d.get("model") or {}).get("display_name") or ""
if model:
    parts.append(f"{DIM}{model}{R}")

cw = d.get("context_window") or {}
used = cw.get("used_percentage")
size = cw.get("context_window_size") or 0
tok = cw.get("total_input_tokens") or 0
if used is not None:
    pct = int(round(used))
    # Smart zone: an ABSOLUTE token threshold, not a % of the window. Quality
    # degradation does not scale with window size; 65% of 1M is 650k tokens,
    # far past any reasonable smart zone.
    SZ = smart_zone(cfg, model)
    warn = num(cfg.get("windowWarnPct"), DEFAULTS["windowWarnPct"])
    crit = num(cfg.get("windowCriticalPct"), DEFAULTS["windowCriticalPct"])

    filled = max(0, min(10, round(pct / 10)))
    bar = "█" * filled + "░" * (10 - filled)
    def h(n):
        return f"{n/1_000_000:.1f}M" if n >= 1_000_000 else f"{n/1000:.0f}k"
    label = f"{h(tok)}/{h(size)}" if size else h(tok)

    # Decision tree (Matt Pocock): the statusline can only answer the first
    # question -- "do you have smart zone left?". The other three depend on
    # the session, so past the threshold it defers to /arbol.
    # Two distinct risks: running out of WINDOW (%) and leaving the SMART
    # ZONE (absolute tokens). The most urgent one wins.
    if pct >= crit:
        hint = "out of window · /compact or /clear NOW"
    elif tok >= SZ:
        hint = "dumb zone · /clear if disposable, else /handoff"
    elif pct >= warn:
        hint = "window limit · /clear or /handoff"
    elif tok >= SZ * 0.8:
        hint = "smart zone limit · /arbol"
    else:
        hint = None

    color = RED if (pct >= crit or tok >= SZ * 1.5) else (YEL if hint else GRN)
    parts.append(f"{color}{bar} {pct}%{R} {DIM}{label}{R}")
    if hint:
        parts.append(f"{color}{hint}{R}")

if cfg_broken:
    parts.append(f"{RED}statusline.json unreadable{R}")

print(" · ".join(parts))
'
SH
chmod +x ~/.claude/statusline.sh
```

### 2. Wire it into settings

In `~/.claude/settings.json`, **adding** the key (do not replace the file: it may hold
permissions, hooks and plugins you want to keep):

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/YOUR_USER/.claude/statusline.sh"
  }
}
```

Use the **absolute** path: `~` is not reliably expanded in that field.

Non-destructive merge from the shell:

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".claude/settings.json"
d = json.loads(p.read_text()) if p.exists() else {}
d["statusLine"] = {
    "type": "command",
    "command": str(pathlib.Path.home() / ".claude/statusline.sh"),
}
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print("ok:", d["statusLine"]["command"])
PY
```

### 3. Verify without opening Claude

The script is a pure function of its stdin, so it can be tested with a fake payload:

```bash
for tok in 60000 170000 220000 920000; do
  echo "{\"workspace\":{\"current_dir\":\"$PWD\"},\"model\":{\"display_name\":\"Opus 5\"},\"context_window\":{\"used_percentage\":$((tok/10000)),\"context_window_size\":1000000,\"total_input_tokens\":$tok}}" \
    | ~/.claude/statusline.sh
done
```

Expected output — the same four lines from the top of this document:

```
dummy-project · feature/search-filters · Opus 5 · █░░░░░░░░░ 6% 60k/1.0M
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 17% 170k/1.0M · smart zone limit · /arbol
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 22% 220k/1.0M · dumb zone · /clear if disposable, else /handoff
dummy-project · feature/search-filters · Opus 5 · █████████░ 92% 920k/1.0M · out of window · /compact or /clear NOW
```

With the directory and branch of wherever you ran the loop, and in colour. If the branch
does not appear, run it from inside a git repository.

To confirm that `SZ` is what governs and not the percentage, repeat the loop with a small
window: the same token totals must produce the same hints, even though the percentage is
very different.

```bash
for tok in 60000 105000 130000 185000; do
  echo "{\"workspace\":{\"current_dir\":\"$PWD\"},\"model\":{\"display_name\":\"Sonnet 5\"},\"context_window\":{\"used_percentage\":$((tok/2000)),\"context_window_size\":200000,\"total_input_tokens\":$tok}}" \
    | ~/.claude/statusline.sh
done
```

Then restart Claude Code: the statusline is read when the session starts.

---

## The `/arbol` command (optional, but it is the other half)

The statusline's hint can only answer the **first** question of Matt Pocock's decision
tree — "do you have smart zone left?" — because it is the only one that is a number. The
other three (is the context disposable? is a handoff needed? can it run AFK?) depend on
what happened in the session, and no script knows that. So the hint defers to a command
that *can* see the conversation:

```bash
mkdir -p ~/.claude/commands
cat > ~/.claude/commands/arbol.md <<'EOF'
---
description: Recommends what to do at the end of a work phase (Matt Pocock's decision tree) based on the real state of this session
---

I just finished a phase of work. Walk Matt Pocock's decision tree **in order** and decide
for me: the first affirmative answer wins, and `/compact` is what is left when none apply.

Answer each question by looking at **this conversation**, not in the abstract. For each
one, give a single line: the answer and the concrete evidence behind it.

1. **Can I continue?** Is there smart zone left (check the context % in the statusline),
   or is what remains simple enough to do in the dumb zone?
   → if yes: **stay in the session**.
2. **Is the context irrelevant?** Are this session's explorations and decisions
   disposable, or are there findings that would be lost?
   → if yes: **`/clear`**.
3. **Do I need a handoff?** Does this continue in another agent, another directory or
   with another person?
   → if yes: **`/handoff`**.
4. **Can the task be done AFK?** Does it need human input while it runs?
   → if it does not: **subagent**.
5. If none applied: **`/compact`**.

Finish with:

- **Recommendation**: the exact command to run.
- **Why that branch and not the previous one**: one sentence.
- **What would be lost**: if the branch discards context (`/clear`, `/compact`), name the
  concrete things from this session that do not survive, so I can decide to save them first.

Do not execute anything. Only recommend.

$ARGUMENTS
EOF
```

---

## The orange prompt border (optional)

Separate from the statusline, but part of the same setup.

`/color orange` is declared in the binary as *"Set the prompt bar color for **this
session**"* — it does not persist, by design. To make it permanent you override the
theme's `promptBorder` key, which is where the border colour resolver falls back to when
no `/color` is active:

```bash
mkdir -p ~/.claude/themes
cat > ~/.claude/themes/naranja.json <<'EOF'
{
  "name": "Naranja",
  "base": "dark",
  "overrides": {
    "promptBorder": "rgb(255,178,102)",
    "promptBorderShimmer": "rgb(255,210,160)"
  }
}
EOF
```

And in `settings.json`: `"theme": "custom:naranja"` (the slug is the filename without
`.json`, prefixed with `custom:`).

- `base` accepts: `dark`, `light`, `light-daltonized`, `dark-daltonized`, `light-ansi`,
  `dark-ansi`.
- Colours accept `rgb(r,g,b)`, `#rrggbb`, `#rgb`, `ansi256(n)` and `ansi:<name>`.
- Claude Code watches `~/.claude/themes/` and reloads on save — no restart needed to
  iterate on the colour.
- Other useful keys in the same object: `claude`, `claudeShimmer`, `planMode`,
  `autoAccept`, `bashBorder`, `suggestion`, `success`, `error`, `warning`, `diffAdded`,
  `diffRemoved`.
- `rgb(255,178,102)` is exactly the orange `/color orange` gives on a `dark` base.
  `rgb(255,140,0)` is the saturated variant.

---

## Configuring the smart zone

Three ways, in decreasing order of precedence:

**1. `CLAUDE_SMART_ZONE_TOKENS`** — the environment variable. It beats everything else, so
it works both for trying a value out and for setting it permanently.

For a one-off session, touching nothing:

```bash
CLAUDE_SMART_ZONE_TOKENS=150000 claude
```

To make it stick, in your `~/.zshrc` (or `~/.bashrc`):

```bash
export CLAUDE_SMART_ZONE_TOKENS=150000
```

The value is in **tokens**, not thousands and not a percentage: `150000`, not `150` or
`15`. A non-numeric or ≤ 0 value is ignored and falls through to the next level, silently.

A caveat about the env var as a permanent mechanism: it only reaches Claude if the process
inherits your shell rc. If you launch Claude from the app, a launcher or the IDE, it may
not be there — which is why option 2 exists.

**2. `~/.claude/statusline.json`** — persistent, and unlike the env var it does not depend
on your shell rc having been loaded (important if you launch Claude from the app or the
IDE):

```json
{
  "smartZoneTokens": 200000,
  "perModel": { "Sonnet 5": 120000 },
  "windowWarnPct": 80,
  "windowCriticalPct": 90
}
```

All keys are optional. `perModel` is indexed by the model's `display_name` — the same
string you see in the statusline — and overrides `smartZoneTokens` for that model only.
Note: a model having a larger window does not imply its smart zone is larger; they are
different things, and this file is where you put your judgement about each. The example's
`perModel` exists precisely for that: with a 200k window, an `SZ` of 200k is out of reach,
so a lower number is the useful one there.

**3. The script's defaults**: `smartZoneTokens` 200k, `windowWarnPct` 80,
`windowCriticalPct` 90.

An invalid value (negative, non-numeric) falls silently through to the next level. If the
file exists but is not valid JSON, the statusline **does not break**: it uses the defaults
and appends `statusline.json unreadable` to the end of the line, so you are not debugging
blind.

The derived steps (`0.8·SZ` for the first warning, `1.5·SZ` for red) are fixed in the
script; they are two multipliers in the hint block.

## Customisation

- **Smart zone and window thresholds**: see the section above — no need to edit the script.
- **Colours**: the truecolor constants at the top of the Python block — `GRN` (healthy),
  `YEL` (warning), `RED` (critical) for the bar, and `O` for the directory name. Changing
  `GRN` changes only the bar; `O` also drags the directory along.
- **Branch length**: the `34` / `31` in the truncation.
- **Separator**: the `" · "` in the final `print`.
- **Branch glyph**: I do not use  (Powerline) so as not to depend on a Nerd Font. If your
  terminal has one, add it before `{br}`.

---

## Why it is built this way

The decisions that cost an iteration, so they are not relitigated:

- **The smart-zone threshold is absolute, not a percentage.** The first version used "65%
  of context". On a 200k window that is 130k tokens (plausible by accident); on 1M it is
  650k, i.e. the warning arrives half a million tokens late. Quality degradation does not
  scale with window size, so the threshold cannot either.
- **But the percentage did not go away.** Running out of window is a different risk from
  leaving the smart zone, and that one *is* proportional — it is what triggers
  auto-compact. So both coexist and the most urgent wins.
- **Colour follows the hint.** In an intermediate version the colour changed at 60/85 and
  the hint at 65/80/90, so the bar went yellow while there was nothing to do about it. Now
  both tell the same story.
- **Green → yellow → red.** The healthy state uses green, not the theme's orange: orange
  is reserved for the directory name and the prompt border, so reusing it in the bar made
  "all good" and "do something" the same colour.
- **The statusline does not decide for you.** Of the tree's four questions, only the first
  is a number. The other three depend on what happened in the session, which is why the
  hint defers to `/arbol` instead of recommending a branch it cannot justify.
- **Never break.** A statusline that dies on a badly edited JSON leaves you with no bar and
  no clue. Any config error falls back to the defaults and says so on the line.
- **`SZ = 200k` is judgement, not measurement.** No number in this document comes from an
  experiment; they are starting points for you to move.

---

## If you also use Orca

Orca installs its own global `statusLine` pointing at
`~/.orca/agent-hooks/claude-statusline.sh`. That script **prints nothing**: it only POSTs
the payload to the Orca app for telemetry. Overwriting it with this script would lose that
integration, so the block that preserves it **is already in `statusline.sh`**, right after
the `[ -z "$payload" ]` line:

```sh
orca=~/.orca/agent-hooks/claude-statusline.sh
if [ -x "$orca" ]; then
  printf '%s' "$payload" | /bin/sh "$orca" >/dev/null 2>&1 &
fi
```

It runs in the background, because that script makes a `curl` with up to a 1.5s timeout and
you do not want that latency on every refresh. If you do not use Orca the block is a no-op
(the `-x` guard fails); delete those four lines if you would rather not carry it.

Careful: if Orca reinstalls its hook it may overwrite the `statusLine` key in
`settings.json` again. If the bar goes blank one day, that is the first suspect.

---

## What cannot be done (verified, so you do not lose time)

- **Packaging the statusline as a plugin.** `claude plugin validate` on a manifest
  declaring `statusLine` answers: `Unknown field 'statusLine'. Claude Code ignores it at
  load time.` Same under `experimental.statusLine`. The key is only read from
  `settings.json`. A plugin *can* ship the script, but somebody has to wire the key.
- **The theme *is* packageable**, under `experimental.themes: "./themes"`. Declaring it at
  the top level still loads but is deprecated.
- **`/color` does not persist.** There is nowhere to store it; it is per-session by design.
- **The branch is not in the payload.** It has to be read from disk.

---

## A prompt to have Claude Code install it for you

On the new workstation, open Claude Code in any directory and paste:

> Install the statusline described in this document: <paste the contents of this .md, or
> its path if you already copied it>. Create `~/.claude/statusline.sh`, the
> `~/.claude/commands/arbol.md` command and the `~/.claude/themes/naranja.json` theme, and
> add the `statusLine` and `theme` keys to `~/.claude/settings.json` **by merging**,
> without losing what is already there. Back up `settings.json` before writing. Then test
> the script with fake payloads at 42/70/84/93% and show me the output. If you detect that
> Orca already has a `statusLine` installed, include the block that forwards the payload
> to it.

If you would rather it build the thing from scratch than copy the script, this prompt is
enough:

> I want a statusline for Claude Code showing: directory, git branch, model, and a bar
> with the % of context used plus the tokens (`700k/1.0M`), and a hint that from 65% on
> suggests which branch of Matt Pocock's decision tree to consider (`/clear`, `/handoff`,
> `/compact`). Before writing anything, find out which fields the JSON Claude Code passes
> to the `statusLine` command actually contains — do not assume it carries the branch.
> Install it under `~/.claude/` and verify it with fake payloads without relying on
> restarting Claude.
