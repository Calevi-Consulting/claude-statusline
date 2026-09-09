# claude-statusline

A statusline for Claude Code showing **directory · branch · model · context usage** —
and, when it matters, **what to do** about that context.

```
dummy-project · feature/search-filters · Opus 5 · █░░░░░░░░░ 6% 60k/1.0M
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 17% 170k/1.0M · smart zone limit · /tree
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 22% 220k/1.0M · dumb zone · /clear if disposable, else /handoff
dummy-project · feature/search-filters · Opus 5 · █████████░ 92% 920k/1.0M · out of window · /compact or /clear NOW
```

The bar runs **green → yellow → red**. Green does not mean "little context used": it means
"you are still in the zone where the model reasons well".

## Install

```bash
git clone https://github.com/mhereu/claude-statusline.git
cd claude-statusline
./install.sh
```

Flags: `--with-theme` (also installs and activates the orange prompt-border theme),
`--no-tree` (skip the `/tree` command), `--dry-run` (show what it would do, write nothing).
Honours `CLAUDE_CONFIG_DIR`; defaults to `~/.claude`.

To revert: `./uninstall.sh` (add `--also-theme`, `--also-tree` to remove those too).

The installer **backs up `settings.json`** before touching it and preserves every other key.
If you already had a statusline configured, it says so before replacing it.

## Why an installer and not a plugin

Because a statusline **cannot be packaged as a plugin**. Verified on Claude Code `2.1.266`:

```
$ claude plugin validate ./probe
  ❯ statusLine: Unknown field 'statusLine'. Claude Code ignores it at load time.
```

Same under `experimental.statusLine`. The key is only read from `settings.json`, and its
`command` must be an **absolute path on the machine where it runs** — precisely what a
distributed plugin cannot know. A plugin could ship the script, but somebody would still
have to wire the key. Hence `install.sh`.

(The **theme** *is* packageable, under `experimental.themes`. Only the statusline is not.)

## The thresholds: absolute tokens, not a percentage

The hint distinguishes **two risks that are not the same thing**:

- **Leaving the smart zone** — reasoning quality degrades well before the window fills, and
  that point **does not scale with window size**. So the threshold is in **absolute tokens**
  (`SZ`, 200k by default).
- **Running out of window** — that one *is* a percentage, and it is what triggers auto-compact.

Conflating them is the easy mistake: "65% of context" is 130k tokens on a 200k window
(reasonable by accident) but **650k** on a 1M window — long after quality is gone.

| Condition | Colour | Hint |
|---|---|---|
| `tok < 0.8·SZ` | green | — |
| `tok ≥ 0.8·SZ` | yellow | smart zone limit · `/tree` |
| `tok ≥ SZ` | yellow | dumb zone · `/clear` if disposable, else `/handoff` |
| `tok ≥ 1.5·SZ` | red | same as above |
| `pct ≥ 80` | yellow | window limit · `/clear` or `/handoff` |
| `pct ≥ 90` | red | out of window · `/compact` or `/clear` NOW |

The most urgent condition wins. Colour follows the hint, so both tell the same story.

## Configuration

All optional, in `~/.claude/statusline.json`:

```json
{
  "smartZoneTokens": 200000,
  "windowWarnPct": 80,
  "windowCriticalPct": 90,
  "perModel": { "Opus 5 (1M)": 300000 }
}
```

Precedence: `CLAUDE_SMART_ZONE_TOKENS` (env) > `perModel` > `smartZoneTokens` > default.
A malformed file **does not break the statusline**: it falls back to the defaults and says
so on the line.

Colours: the constants at the top of the Python block — `GRN` (healthy), `YEL` (warning),
`RED` (critical) for the bar, and `O` for the directory name.

## Requirements

- Claude Code (verified on `2.1.266`)
- `python3` on PATH — the installer fails early if it is missing
- A terminal with 24-bit colour (iTerm2, Ghostty, Kitty, WezTerm, recent Terminal.app,
  Windows Terminal)

## Note on Orca

`statusline.sh` forwards the payload to `~/.orca/agent-hooks/claude-statusline.sh` when that
file exists and is executable. That is Orca telemetry: Orca installs its own statusline,
**which prints nothing**, and can overwrite the key in `settings.json`. If you do not use
Orca the block is a no-op (the `-x` guard fails). To drop it, delete the four lines at the
top of the script.

## Design

`docs/design.md` carries the full reasoning: what the statusline payload does
and does not contain, why the branch is read from disk, why the threshold is absolute, the
`/tree` command, and the list of things that were tried and cannot be done.

## License

MIT — see [LICENSE](LICENSE).
