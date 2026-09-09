#!/usr/bin/env bash
# Removes the statusline: drops the settings.json key and the installed pieces.
# The theme and /tree are only touched with their respective flags.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

ALSO_THEME=0
ALSO_TREE=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --also-theme) ALSO_THEME=1 ;;
    --also-tree) ALSO_TREE=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: ./uninstall.sh [--also-theme] [--also-tree] [--dry-run]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] $*"; else "$@"; fi; }

say "Uninstalling from: $CLAUDE_DIR"

SETTINGS="$SETTINGS" ALSO_THEME="$ALSO_THEME" DRY_RUN="$DRY_RUN" python3 <<'PY'
import json, os, pathlib, shutil, sys, time

settings = pathlib.Path(os.environ["SETTINGS"])
drop_theme = os.environ["ALSO_THEME"] == "1"
dry = os.environ["DRY_RUN"] == "1"

if not settings.exists():
    print("  settings.json does not exist; nothing to clean")
    raise SystemExit

try:
    data = json.loads(settings.read_text() or "{}")
except json.JSONDecodeError as e:
    sys.exit(f"ERROR: {settings} is not valid JSON ({e}); nothing was touched.")

changed = False
if "statusLine" in data:
    print("  removing statusLine")
    if not dry:
        del data["statusLine"]
    changed = True
else:
    print("  there was no statusLine")

if drop_theme and data.get("theme") == "custom:naranja":
    print("  removing theme custom:naranja")
    if not dry:
        del data["theme"]
    changed = True

if changed and not dry:
    backup = settings.with_suffix(f".json.bak.{time.strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(settings, backup)
    print(f"  backup: {backup.name}")
    settings.write_text(json.dumps(data, indent=2) + "\n")
PY

say "· statusline.sh"
run rm -f "$CLAUDE_DIR/statusline.sh"

if [ "$ALSO_TREE" = 1 ]; then
  say "· commands/tree.md"
  run rm -f "$CLAUDE_DIR/commands/tree.md"
fi
if [ "$ALSO_THEME" = 1 ]; then
  say "· themes/naranja.json"
  run rm -f "$CLAUDE_DIR/themes/naranja.json"
fi

say ""
say "Done. The statusline reverts to the native one in the next session."
