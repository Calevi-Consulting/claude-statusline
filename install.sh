#!/usr/bin/env bash
# Installs the Claude Code context statusline.
#
# The `statusLine` key is only read from settings.json — it cannot be packaged
# as a plugin (verified on 2.1.266: `claude plugin validate` answers
# "Unknown field 'statusLine'"). Hence this installer: it copies the pieces and
# wires the key with the absolute path of THIS machine.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$CLAUDE_DIR/settings.json"
TARGET="$CLAUDE_DIR/statusline.sh"

WITH_THEME=0
WITH_TREE=1
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

  --with-theme   Also install the "naranja" theme and activate it (overwrites the
                 current theme). Without this flag the theme is left alone.
  --no-tree      Skip the /tree command.
  --dry-run      Show what it would do, write nothing.
  -h, --help     This help.

Honours CLAUDE_CONFIG_DIR if set; defaults to ~/.claude.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-theme) WITH_THEME=1 ;;
    --no-tree)   WITH_TREE=0 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] $*"; else "$@"; fi; }

# --- Requirements ---------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is not available; the statusline needs it to read the payload." >&2
  exit 1
}

say "Installing into: $CLAUDE_DIR"
[ "$DRY_RUN" = 1 ] && say "(dry-run: nothing is written)"

# settings.json is validated BEFORE copying anything: a broken JSON aborts the whole
# install instead of leaving files in place with the key unwired.
if [ -s "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" python3 -c '
import json, os, sys, pathlib
p = pathlib.Path(os.environ["SETTINGS"])
try:
    json.loads(p.read_text() or "{}")
except json.JSONDecodeError as e:
    sys.exit(f"ERROR: {p} is not valid JSON ({e}).\n"
             "Fix or move it before installing; nothing was touched.")
' || exit 1
fi

# --- Pieces -------------------------------------------------------------------
run mkdir -p "$CLAUDE_DIR"
say "· statusline.sh"
run cp "$SRC/statusline.sh" "$TARGET"
run chmod +x "$TARGET"

if [ "$WITH_TREE" = 1 ]; then
  say "· commands/tree.md"
  run mkdir -p "$CLAUDE_DIR/commands"
  run cp "$SRC/commands/tree.md" "$CLAUDE_DIR/commands/tree.md"
fi

if [ "$WITH_THEME" = 1 ]; then
  say "· themes/naranja.json"
  run mkdir -p "$CLAUDE_DIR/themes"
  run cp "$SRC/themes/naranja.json" "$CLAUDE_DIR/themes/naranja.json"
fi

# --- settings.json ------------------------------------------------------------
# Edited with python (not sed) so everything else is preserved intact.
say "· settings.json → statusLine"
SETTINGS="$SETTINGS" TARGET="$TARGET" WITH_THEME="$WITH_THEME" DRY_RUN="$DRY_RUN" python3 <<'PY'
import json, os, pathlib, shutil, sys, time

settings = pathlib.Path(os.environ["SETTINGS"])
target   = os.environ["TARGET"]
theme    = os.environ["WITH_THEME"] == "1"
dry      = os.environ["DRY_RUN"] == "1"

data = {}
if settings.exists():
    text = settings.read_text()
    if text.strip():
        try:
            data = json.loads(text)
        except json.JSONDecodeError as e:
            sys.exit(f"ERROR: {settings} is not valid JSON ({e}). "
                     "Fix or move it before installing; nothing was touched.")

previous = data.get("statusLine")
if previous and previous.get("command") != target:
    print(f"  note: a statusLine was already set, pointing at {previous.get('command')!r}")
    print("        it is being replaced; the backup sits next to settings.json")

data["statusLine"] = {"type": "command", "command": target}
if theme:
    data["theme"] = "custom:naranja"

if dry:
    print("  [dry-run] statusLine =", json.dumps(data["statusLine"]))
    if theme:
        print('  [dry-run] theme = "custom:naranja"')
    raise SystemExit

if settings.exists():
    backup = settings.with_suffix(f".json.bak.{time.strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(settings, backup)
    print(f"  backup: {backup.name}")

settings.parent.mkdir(parents=True, exist_ok=True)
settings.write_text(json.dumps(data, indent=2) + "\n")
PY

say ""
say "Done. Open a new Claude Code session to see it."
say "Try it without opening Claude:"
say "  echo '{\"workspace\":{\"current_dir\":\"'\"\$PWD\"'\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":15,\"context_window_size\":1000000,\"total_input_tokens\":150000}}' | $TARGET"
[ "$WITH_THEME" = 0 ] && say "" && say "The theme was not installed. For the orange prompt border: ./install.sh --with-theme"
exit 0
