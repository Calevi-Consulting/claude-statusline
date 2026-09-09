#!/bin/sh
# Lee el payload del statusline una sola vez, lo reenvia al hook de Orca
# (telemetria; ese script no imprime nada) e imprime el contador de contexto.
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
    """Config opcional. Nunca rompe la statusline: si el archivo esta mal,
    devuelve los defaults y marca el error para mostrarlo."""
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
    """Precedencia: env > perModel > smartZoneTokens > default."""
    env = os.environ.get("CLAUDE_SMART_ZONE_TOKENS")
    if env:
        return num(env, DEFAULTS["smartZoneTokens"])
    base = num(cfg.get("smartZoneTokens"), DEFAULTS["smartZoneTokens"])
    per = cfg.get("perModel")
    if isinstance(per, dict) and model in per:
        return num(per[model], base)
    return base


def git_branch(start):
    """Lee la branch de .git/HEAD sin invocar git (worktrees incluidos)."""
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
    # Smart zone: umbral ABSOLUTO en tokens, no un % de la ventana. La
    # degradacion de calidad no escala con el tamano de la ventana; 65% de
    # 1M son 650k tokens, muy pasada cualquier smart zone razonable.
    SZ = smart_zone(cfg, model)
    warn = num(cfg.get("windowWarnPct"), DEFAULTS["windowWarnPct"])
    crit = num(cfg.get("windowCriticalPct"), DEFAULTS["windowCriticalPct"])

    filled = max(0, min(10, round(pct / 10)))
    bar = "█" * filled + "░" * (10 - filled)
    def h(n):
        return f"{n/1_000_000:.1f}M" if n >= 1_000_000 else f"{n/1000:.0f}k"
    label = f"{h(tok)}/{h(size)}" if size else h(tok)

    # Arbol de decision (Matt Pocock): la statusline solo puede juzgar la
    # primera pregunta -- "¿te queda smart zone?". Las otras tres dependen
    # de la sesion, asi que a partir del umbral remite a /arbol.
    # Dos riesgos distintos: quedarse sin VENTANA (%) y salirse de la SMART
    # ZONE (tokens absolutos). El mas urgente gana.
    if pct >= crit:
        hint = "sin ventana · /compact o /clear YA"
    elif tok >= SZ:
        hint = "dumb zone · /clear si es descartable, si no /handoff"
    elif pct >= warn:
        hint = "ventana al limite · /clear o /handoff"
    elif tok >= SZ * 0.8:
        hint = "smart zone al limite · /arbol"
    else:
        hint = None

    color = RED if (pct >= crit or tok >= SZ * 1.5) else (YEL if hint else GRN)
    parts.append(f"{color}{bar} {pct}%{R} {DIM}{label}{R}")
    if hint:
        parts.append(f"{color}{hint}{R}")

if cfg_broken:
    parts.append(f"{RED}statusline.json ilegible{R}")

print(" · ".join(parts))
'
