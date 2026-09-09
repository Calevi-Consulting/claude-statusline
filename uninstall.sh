#!/usr/bin/env bash
# Quita la statusline: borra la clave de settings.json y las piezas instaladas.
# El tema y /arbol sólo se tocan con los flags correspondientes.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

ALSO_THEME=0
ALSO_ARBOL=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --also-theme) ALSO_THEME=1 ;;
    --also-arbol) ALSO_ARBOL=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)
      echo "Uso: ./uninstall.sh [--also-theme] [--also-arbol] [--dry-run]"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] $*"; else "$@"; fi; }

say "Desinstalando de: $CLAUDE_DIR"

SETTINGS="$SETTINGS" ALSO_THEME="$ALSO_THEME" DRY_RUN="$DRY_RUN" python3 <<'PY'
import json, os, pathlib, shutil, sys, time

settings = pathlib.Path(os.environ["SETTINGS"])
drop_theme = os.environ["ALSO_THEME"] == "1"
dry = os.environ["DRY_RUN"] == "1"

if not settings.exists():
    print("  settings.json no existe; nada que limpiar")
    raise SystemExit

try:
    data = json.loads(settings.read_text() or "{}")
except json.JSONDecodeError as e:
    sys.exit(f"ERROR: {settings} no es JSON válido ({e}); no se tocó nada.")

changed = False
if "statusLine" in data:
    print("  quitando statusLine")
    if not dry:
        del data["statusLine"]
    changed = True
else:
    print("  no había statusLine")

if drop_theme and data.get("theme") == "custom:naranja":
    print("  quitando theme custom:naranja")
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

if [ "$ALSO_ARBOL" = 1 ]; then
  say "· commands/arbol.md"
  run rm -f "$CLAUDE_DIR/commands/arbol.md"
fi
if [ "$ALSO_THEME" = 1 ]; then
  say "· themes/naranja.json"
  run rm -f "$CLAUDE_DIR/themes/naranja.json"
fi

say ""
say "Listo. La statusline vuelve a la nativa en la próxima sesión."
