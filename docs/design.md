# Statusline de Claude Code: contexto, branch y árbol de decisión

Cómo replicar en una workstation limpia la statusline que muestra directorio, branch,
modelo, uso de contexto y una sugerencia de qué hacer cuando el contexto se llena.

Verificado contra Claude Code **2.1.266** (macOS). Todo son archivos en `~/.claude/`;
no hay que instalar nada.

```
dummy-project · feature/search-filters · Opus 5 · █░░░░░░░░░ 6% 60k/1.0M
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 17% 170k/1.0M · smart zone al limite · /arbol
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 22% 220k/1.0M · dumb zone · /clear si es descartable, si no /handoff
dummy-project · feature/search-filters · Opus 5 · █████████░ 92% 920k/1.0M · sin ventana · /compact o /clear YA
```

## Los umbrales: tokens absolutos, no porcentaje

El hint distingue **dos riesgos que no son el mismo**:

- **Salir de la smart zone** — la calidad de razonamiento se degrada mucho antes de
  llenar la ventana, y ese punto **no escala con el tamaño de la ventana**. Es un
  umbral en **tokens absolutos** (`SZ`, por defecto **200k**, configurable).
- **Quedarse sin ventana** — eso sí es un porcentaje, y es lo que dispara el
  auto-compact.

Mezclarlos es un error fácil: un umbral de "65% del contexto" son 130k tokens con una
ventana de 200k (razonable por casualidad) pero **650k** con una de 1M, mucho después
de que la calidad se haya ido. Por eso `SZ` es absoluto y el % solo cubre el final de
la ventana. El default es **200k tokens**.

| Condición | Color | Hint | Rama del árbol |
|---|---|---|---|
| `tok < 0.8·SZ` (< 160k) | verde | — | seguí en la sesión |
| `tok ≥ 0.8·SZ` (≥ 160k) | amarillo | `smart zone al limite · /arbol` | correlo y decidí |
| `tok ≥ SZ` (≥ 200k) | amarillo | `dumb zone · /clear si es descartable, si no /handoff` | `/clear` o `/handoff` |
| `tok ≥ 1.5·SZ` (≥ 300k) | rojo | igual que arriba | `/clear` o `/handoff` |
| `pct ≥ 80` | amarillo | `ventana al limite · /clear o /handoff` | `/clear` o `/handoff` |
| `pct ≥ 90` | rojo | `sin ventana · /compact o /clear YA` | `/compact` |

Gana la condición más urgente. El color sigue al hint, así que ambos cuentan la misma
historia.

**Con una ventana de 200k, el default de `SZ` no se alcanza nunca**: a 160k tokens ya
estás al 80% y dispara `ventana al limite`. En la práctica esos modelos quedan cubiertos
solo por los umbrales de porcentaje. Si querés el aviso de smart zone también ahí,
bajalo con `perModel` (ver más abajo).

`SZ` es **criterio, no medición**: 200k es un punto de partida, no un número que yo
haya validado. Se cambia sin tocar el script — ver
[Configurar la smart zone](#configurar-la-smart-zone).

---

## Requisitos

- Claude Code 2.1.x o posterior (`claude --version`).
- `python3` en el PATH. En macOS viene con las Command Line Tools; en Linux es
  el paquete `python3` de la distro.
- Una terminal con soporte de color de 24 bits (iTerm2, Ghostty, Kitty, WezTerm,
  Terminal.app reciente, Windows Terminal). Sin truecolor los colores caen a lo
  más cercano, pero nada se rompe.

---

## Qué muestra, y de dónde sale cada dato

Claude Code invoca el comando de `statusLine` y le pasa por **stdin** un JSON con el
estado de la sesión. Los campos que usa este script:

| Campo del payload | Se muestra como |
|---|---|
| `workspace.current_dir` | nombre del directorio |
| `model.display_name` | modelo |
| `context_window.used_percentage` | barra + porcentaje |
| `context_window.total_input_tokens` / `.context_window_size` | `700k/1.0M` |

**La branch no viene en el payload.** `workspace` trae `current_dir`, `project_dir`,
`added_dirs`, `git_worktree` (un path) y `repo` (`{host, owner, name}`) — ningún campo
con el nombre de la rama. Por eso el script la lee de `.git/HEAD` directamente, sin
invocar `git`: la statusline se refresca seguido y un fork por refresco se nota.
Maneja worktrees (donde `.git` es un archivo con `gitdir:`) y HEAD detached (muestra
`@<sha7>`).

---

## Instalación

### 1. El script

```bash
mkdir -p ~/.claude
cat > ~/.claude/statusline.sh <<'SH'
#!/bin/sh
# Statusline de Claude Code: directorio · branch · modelo · uso de contexto · hint.
# Recibe por stdin el JSON de estado de la sesion.
payload=$(cat)
[ -z "$payload" ] && exit 0


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
SH
chmod +x ~/.claude/statusline.sh
```

### 2. Cablearlo en settings

En `~/.claude/settings.json`, **agregando** la clave (no reemplaces el archivo: puede
tener permisos, hooks y plugins que querés conservar):

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/TU_USUARIO/.claude/statusline.sh"
  }
}
```

Usá la ruta **absoluta**: `~` no se expande en ese campo de forma confiable.

Merge no destructivo desde la shell:

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

### 3. Verificar sin abrir Claude

El script es una función pura de su stdin, así que se prueba con un payload falso:

```bash
for tok in 60000 170000 220000 920000; do
  echo "{\"workspace\":{\"current_dir\":\"$PWD\"},\"model\":{\"display_name\":\"Opus 5\"},\"context_window\":{\"used_percentage\":$((tok/10000)),\"context_window_size\":1000000,\"total_input_tokens\":$tok}}" \
    | ~/.claude/statusline.sh
done
```

Salida esperada — las mismas cuatro líneas del principio de este documento:

```
dummy-project · feature/search-filters · Opus 5 · █░░░░░░░░░ 6% 60k/1.0M
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 17% 170k/1.0M · smart zone al limite · /arbol
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 22% 220k/1.0M · dumb zone · /clear si es descartable, si no /handoff
dummy-project · feature/search-filters · Opus 5 · █████████░ 92% 920k/1.0M · sin ventana · /compact o /clear YA
```

Con el directorio y la branch de donde hayas corrido el bucle, y con color. Si no
aparece la branch, corrélo parado dentro de un repo git.

Para comprobar que `SZ` es lo que manda y no el porcentaje, repetí el bucle con una
ventana chica: los mismos totales de tokens tienen que dar los mismos hints, aunque el
porcentaje sea muy distinto.

```bash
for tok in 60000 105000 130000 185000; do
  echo "{\"workspace\":{\"current_dir\":\"$PWD\"},\"model\":{\"display_name\":\"Sonnet 5\"},\"context_window\":{\"used_percentage\":$((tok/2000)),\"context_window_size\":200000,\"total_input_tokens\":$tok}}" \
    | ~/.claude/statusline.sh
done
```

Después reiniciá Claude Code: la statusline se lee al arrancar la sesión.

---

## El comando `/arbol` (opcional, pero es la otra mitad)

El hint de la statusline solo puede contestar la **primera** pregunta del árbol de
decisión de Matt Pocock — "¿te queda smart zone?" — porque es la única que es un
número. Las otras tres (¿el contexto es descartable? ¿hay handoff? ¿es AFK?) dependen
de qué pasó en la sesión, y ningún script las sabe. Por eso el hint remite a un
comando que sí ve la conversación:

```bash
mkdir -p ~/.claude/commands
cat > ~/.claude/commands/arbol.md <<'EOF'
---
description: Recomienda qué hacer al terminar una fase (árbol de Matt Pocock) según el estado real de esta sesión
---

Terminé una fase de trabajo. Recorré el árbol de decisión de Matt Pocock **en orden**
y decidí por mí: la primera respuesta afirmativa gana, y `/compact` es lo que queda
cuando ninguna aplica.

Contestá cada pregunta mirando **esta conversación**, no en abstracto. Para cada una,
una línea: la respuesta y la evidencia concreta que la sostiene.

1. **¿Puedo continuar?** ¿Queda smart zone (mirá el % de contexto en la statusline),
   o lo que falta es lo bastante simple para hacerlo en la dumb zone?
   → si sí: **seguí en la sesión**.
2. **¿El contexto es irrelevante?** ¿Las exploraciones y decisiones de esta sesión son
   descartables, o hay hallazgos que se perderían?
   → si sí: **`/clear`**.
3. **¿Necesito un handoff?** ¿Esto sigue en otro agente, otro directorio u otro colega?
   → si sí: **`/handoff`**.
4. **¿La tarea se puede hacer AFK?** ¿Necesita input humano mientras corre?
   → si no lo necesita: **subagente**.
5. Si ninguna aplicó: **`/compact`**.

Terminá con:

- **Recomendación**: el comando exacto a ejecutar.
- **Por qué esa rama y no la anterior**: una frase.
- **Qué se perdería**: si la rama descarta contexto (`/clear`, `/compact`), nombrá lo
  concreto de esta sesión que no sobrevive, para que yo pueda decidir guardarlo antes.

No ejecutes nada. Solo recomendá.

$ARGUMENTS
EOF
```

---

## El borde naranja del prompt (opcional)

Va aparte de la statusline, pero es parte del mismo setup.

`/color orange` está declarado en el binario como *"Set the prompt bar color for **this
session**"* — no persiste, por diseño. Para que sea permanente hay que overridear la
clave `promptBorder` del tema, que es a lo que cae el resolvedor de color del borde
cuando no hay un `/color` activo:

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

Y en `settings.json`: `"theme": "custom:naranja"` (el slug es el nombre del archivo sin
`.json`, prefijado con `custom:`).

- `base` acepta: `dark`, `light`, `light-daltonized`, `dark-daltonized`, `light-ansi`,
  `dark-ansi`.
- Los colores aceptan `rgb(r,g,b)`, `#rrggbb`, `#rgb`, `ansi256(n)` y `ansi:<nombre>`.
- Claude Code vigila `~/.claude/themes/` y recarga al guardar — no hace falta reiniciar
  para iterar el color.
- Otras claves útiles del mismo objeto: `claude`, `claudeShimmer`, `planMode`,
  `autoAccept`, `bashBorder`, `suggestion`, `success`, `error`, `warning`, `diffAdded`,
  `diffRemoved`.
- `rgb(255,178,102)` es exactamente el naranja que da `/color orange` sobre base `dark`.
  `rgb(255,140,0)` es la variante saturada.

---

## Configurar la smart zone

Tres formas, de mayor a menor precedencia:

**1. `CLAUDE_SMART_ZONE_TOKENS`** — la variable de entorno. Gana sobre todo lo demás,
así que sirve tanto para probar un valor como para fijarlo de forma permanente.

Para una sesión suelta, sin tocar nada:

```bash
CLAUDE_SMART_ZONE_TOKENS=150000 claude
```

Para dejarlo fijo, en tu `~/.zshrc` (o `~/.bashrc`):

```bash
export CLAUDE_SMART_ZONE_TOKENS=150000
```

El valor está en **tokens**, no en miles ni en porcentaje: `150000`, no `150` ni `15`.
Un valor no numérico o ≤ 0 se ignora y cae al nivel siguiente, sin avisar.

Ojo con la env var como mecanismo permanente: solo llega a Claude si el proceso hereda
tu shell rc. Si lanzás Claude desde la app, un launcher o el IDE, puede no estar — por
eso existe la opción 2.

**2. `~/.claude/statusline.json`** — persistente, y a diferencia de la env var no
depende de que tu shell rc se haya cargado (importante si lanzás Claude desde la app o
el IDE):

```json
{
  "smartZoneTokens": 200000,
  "perModel": { "Sonnet 5": 120000 },
  "windowWarnPct": 80,
  "windowCriticalPct": 90
}
```

Todas las claves son opcionales. `perModel` se indexa por el `display_name` del modelo
—  el mismo string que ves en la statusline — y pisa a `smartZoneTokens` solo para ese
modelo. Ojo: que un modelo tenga una ventana más grande no implica que su smart zone lo
sea; son cosas distintas y este archivo es donde ponés tu criterio sobre cada una. El
`perModel` del ejemplo existe justamente por eso: con ventana de 200k, un `SZ` de 200k
queda fuera de alcance, así que ahí conviene un número más bajo.

**3. Los defaults del script**: `smartZoneTokens` 200k, `windowWarnPct` 80,
`windowCriticalPct` 90.

Un valor inválido (negativo, no numérico) cae silenciosamente al nivel siguiente. Si el
archivo existe pero no es JSON válido, la statusline **no se rompe**: usa los defaults y
agrega `statusline.json ilegible` al final de la línea, para que no lo debuguees a
ciegas.

Los escalones derivados (`0.8·SZ` para el primer aviso, `1.5·SZ` para el rojo) están
fijos en el script; son dos multiplicadores en el bloque del hint.

## Personalización

- **Smart zone y umbrales de ventana**: ver la sección anterior — no hace falta editar
  el script.
- **Colores**: las constantes truecolor del tope del bloque Python — `GRN` (sano), `YEL`
  (aviso), `RED` (crítico) para la barra, y `O` para el nombre del directorio. Cambiar
  `GRN` cambia solo la barra; `O` arrastra también el directorio.
- **Longitud de la branch**: el `34` / `31` del truncado.
- **Separador**: el `" · "` del `print` final.
- **Glifo de branch**: no uso  (Powerline) para no depender de una Nerd Font. Si tu
  terminal la tiene, agregalo antes de `{br}`.

---

## Por qué está hecho así

Las decisiones que costaron una iteración, para no volver a discutirlas:

- **El umbral de smart zone es absoluto, no un porcentaje.** La primera versión usaba
  "65% del contexto". Con ventana de 200k eso da 130k tokens (plausible por casualidad);
  con 1M da 650k, o sea el aviso llega medio millón de tokens tarde. La degradación de
  calidad no escala con el tamaño de la ventana, así que el umbral tampoco puede.
- **Pero el porcentaje no se fue del todo.** Quedarse sin ventana es un riesgo distinto
  de salirse de la smart zone, y ese sí es porcentual — es lo que dispara el
  auto-compact. Por eso conviven los dos y gana el más urgente.
- **El color sigue al hint.** En una versión intermedia el color cambiaba en 60/85 y el
  hint en 65/80/90, así que la barra se ponía amarilla sin que hubiera nada que hacer.
  Ahora ambos cuentan la misma historia.
- **Semáforo verde → amarillo → rojo.** El estado sano usa verde, no el naranja del tema:
  el naranja queda para el nombre del directorio y el borde del prompt, así que reutilizarlo
  en la barra hacía que "todo bien" y "decorá" fueran el mismo color.
- **La statusline no decide por vos.** De las cuatro preguntas del árbol, solo la
  primera es un número. Las otras tres dependen de qué pasó en la sesión, y por eso el
  hint remite a `/arbol` en vez de recomendar una rama que no puede justificar.
- **Nunca romperse.** Una statusline que muere por un JSON mal editado te deja sin barra
  y sin pista. Cualquier error de config cae a los defaults y lo dice en la línea.
- **`SZ = 200k` es criterio, no medición.** Ningún número de este documento sale de un
  experimento; son puntos de partida para que los muevas.

---

## Si además usás Orca

Orca instala su propio `statusLine` global apuntando a
`~/.orca/agent-hooks/claude-statusline.sh`. Ese script **no imprime nada**: solo hace
POST del payload a la app de Orca para telemetría. Si lo pisás con este script, perdés
esa integración. Para conservarla, insertá esto justo después del `[ -z "$payload" ]`:

```sh
orca=~/.orca/agent-hooks/claude-statusline.sh
if [ -x "$orca" ]; then
  printf '%s' "$payload" | /bin/sh "$orca" >/dev/null 2>&1 &
fi
```

En background, porque ese script hace un `curl` con hasta 1.5s de timeout y no querés
esa latencia en cada refresco.

Ojo: si Orca reinstala su hook puede volver a pisar la clave `statusLine` de
`settings.json`. Si un día la barra aparece vacía, ese es el primer sospechoso.

---

## Lo que no se puede (verificado, para no perder tiempo)

- **Empaquetar la statusline como plugin.** `claude plugin validate` sobre un manifiesto
  que declara `statusLine` responde: `Unknown field 'statusLine'. Claude Code ignores it
  at load time.` Lo mismo bajo `experimental.statusLine`. La clave solo se lee de
  `settings.json`. Un plugin sí puede *traer* el script, pero alguien tiene que cablear
  la clave.
- **El tema sí es empaquetable**, bajo `experimental.themes: "./themes"`. Declararlo en
  el nivel superior todavía carga pero está deprecado.
- **`/color` no persiste.** No hay dónde guardarlo; es por sesión por diseño.
- **La branch no está en el payload.** Hay que leerla del disco.

---

## Prompt para que Claude Code lo instale solo

En la workstation nueva, abrí Claude Code en cualquier directorio y pegá:

> Instalá la statusline descrita en este documento: <pegá el contenido de este .md, o
> la ruta si ya lo copiaste>. Creá `~/.claude/statusline.sh`, el comando
> `~/.claude/commands/arbol.md` y el tema `~/.claude/themes/naranja.json`, y agregá las
> claves `statusLine` y `theme` a `~/.claude/settings.json` **haciendo merge**, sin
> perder lo que ya tenga. Antes de escribir, hacé backup de `settings.json`. Después
> probá el script con payloads falsos de 42/70/84/93% y mostrame la salida. Si detectás
> que Orca ya tiene un `statusLine` instalado, incluí el bloque que le reenvía el
> payload.

Si preferís que lo arme desde cero en vez de copiar el script, este prompt alcanza:

> Quiero una statusline para Claude Code que muestre: directorio, branch de git,
> modelo, y una barra con el % de contexto usado y los tokens (`700k/1.0M`), más un
> hint que a partir del 65% me sugiera qué rama del árbol de decisión de Matt Pocock
> considerar (`/clear`, `/handoff`, `/compact`). Antes de escribir nada, averiguá qué
> campos trae realmente el JSON que Claude Code le pasa al comando de `statusLine` —
> no asumas que trae la branch. Instalalo en `~/.claude/` y verificalo con payloads
> falsos sin depender de reiniciar Claude.
