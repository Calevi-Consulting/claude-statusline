#!/usr/bin/env bash
# Instala la statusline de contexto de Claude Code.
#
# La clave `statusLine` sólo se lee de settings.json — no es empaquetable como
# plugin (verificado en 2.1.266: `claude plugin validate` responde
# "Unknown field 'statusLine'"). Por eso este instalador existe: copia las
# piezas y cablea la clave con la ruta absoluta de ESTA máquina.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$CLAUDE_DIR/settings.json"
TARGET="$CLAUDE_DIR/statusline.sh"

WITH_THEME=0
WITH_ARBOL=1
DRY_RUN=0

usage() {
  cat <<'USAGE'
Uso: ./install.sh [opciones]

  --with-theme   Instala también el tema "naranja" y lo activa (pisa el tema actual).
                 Sin este flag el tema no se toca.
  --no-arbol     No instala el comando /arbol.
  --dry-run      Muestra qué haría, sin escribir nada.
  -h, --help     Esta ayuda.

Respeta CLAUDE_CONFIG_DIR si está definida; por defecto usa ~/.claude.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-theme) WITH_THEME=1 ;;
    --no-arbol)   WITH_ARBOL=0 ;;
    --dry-run)    DRY_RUN=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY_RUN" = 1 ]; then say "  [dry-run] $*"; else "$@"; fi; }

# --- Requisitos ---------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 no está disponible; la statusline lo necesita para leer el payload." >&2
  exit 1
}

say "Instalando en: $CLAUDE_DIR"
[ "$DRY_RUN" = 1 ] && say "(dry-run: no se escribe nada)"

# settings.json se valida ANTES de copiar nada: un JSON roto aborta la instalación
# entera en vez de dejar los archivos puestos y la clave sin cablear.
if [ -s "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" python3 -c '
import json, os, sys, pathlib
p = pathlib.Path(os.environ["SETTINGS"])
try:
    json.loads(p.read_text() or "{}")
except json.JSONDecodeError as e:
    sys.exit(f"ERROR: {p} no es JSON valido ({e}).\n"
             "Arreglalo o movelo antes de instalar; no se toco nada.")
' || exit 1
fi

# --- Piezas -------------------------------------------------------------------
run mkdir -p "$CLAUDE_DIR"
say "· statusline.sh"
run cp "$SRC/statusline.sh" "$TARGET"
run chmod +x "$TARGET"

if [ "$WITH_ARBOL" = 1 ]; then
  say "· commands/arbol.md"
  run mkdir -p "$CLAUDE_DIR/commands"
  run cp "$SRC/commands/arbol.md" "$CLAUDE_DIR/commands/arbol.md"
fi

if [ "$WITH_THEME" = 1 ]; then
  say "· themes/naranja.json"
  run mkdir -p "$CLAUDE_DIR/themes"
  run cp "$SRC/themes/naranja.json" "$CLAUDE_DIR/themes/naranja.json"
fi

# --- settings.json ------------------------------------------------------------
# Se edita con python (no sed) para preservar todo lo demás intacto.
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
            sys.exit(f"ERROR: {settings} no es JSON válido ({e}). "
                     "Arreglalo o movelo antes de instalar; no se tocó nada.")

previous = data.get("statusLine")
if previous and previous.get("command") != target:
    print(f"  aviso: ya había una statusLine apuntando a {previous.get('command')!r}")
    print("         se reemplaza; el backup queda al lado de settings.json")

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
say "Listo. Abrí una sesión nueva de Claude Code para verla."
say "Probala sin abrir Claude:"
say "  echo '{\"workspace\":{\"current_dir\":\"'\"\$PWD\"'\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":15,\"context_window_size\":1000000,\"total_input_tokens\":150000}}' | $TARGET"
[ "$WITH_THEME" = 0 ] && say "" && say "El tema no se instaló. Para el borde naranja del prompt: ./install.sh --with-theme"
exit 0
