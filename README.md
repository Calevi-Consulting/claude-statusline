# claude-statusline

Statusline para Claude Code que muestra **directorio · branch · modelo · uso de contexto**
y, cuando hace falta, **qué hacer** con ese contexto.

```
dummy-project · feature/search-filters · Opus 5 · █░░░░░░░░░ 6% 60k/1.0M
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 17% 170k/1.0M · smart zone al limite · /arbol
dummy-project · feature/search-filters · Opus 5 · ██░░░░░░░░ 22% 220k/1.0M · dumb zone · /clear si es descartable, si no /handoff
dummy-project · feature/search-filters · Opus 5 · █████████░ 92% 920k/1.0M · sin ventana · /compact o /clear YA
```

La barra va **verde → amarillo → rojo**. Verde no es "poco contexto": es "todavía estás
en la zona donde el modelo razona bien".

## Instalación

```bash
git clone <url-de-este-repo> claude-statusline
cd claude-statusline
./install.sh
```

Opciones: `--with-theme` (instala y activa el tema naranja del borde del prompt),
`--no-arbol` (no instala el comando `/arbol`), `--dry-run` (muestra qué haría).
Respeta `CLAUDE_CONFIG_DIR`; por defecto usa `~/.claude`.

Para revertir: `./uninstall.sh` (`--also-theme`, `--also-arbol` si querés llevarte eso también).

El instalador **hace backup de `settings.json`** antes de tocarlo y preserva el resto de
las claves. Si ya tenías una statusline, lo avisa antes de reemplazarla.

## Por qué hay un instalador y no un plugin

Porque la statusline **no es empaquetable como plugin**. Verificado en Claude Code
`2.1.266`:

```
$ claude plugin validate ./probe
  ❯ statusLine: Unknown field 'statusLine'. Claude Code ignores it at load time.
```

Lo mismo bajo `experimental.statusLine`. La clave sólo se lee de `settings.json`, y su
`command` tiene que ser una **ruta absoluta de la máquina donde corre** — que es
exactamente lo que un plugin distribuido no puede saber. Un plugin sí podría *traer* el
script, pero alguien tendría que cablear la clave igual. De ahí `install.sh`.

(El **tema** sí es empaquetable, bajo `experimental.themes`. Sólo la statusline no.)

## Los umbrales: tokens absolutos, no porcentaje

El hint distingue **dos riesgos que no son el mismo**:

- **Salir de la smart zone** — la calidad de razonamiento se degrada mucho antes de llenar
  la ventana, y ese punto **no escala con el tamaño de la ventana**. Umbral en **tokens
  absolutos** (`SZ`, por defecto 200k).
- **Quedarse sin ventana** — eso sí es un porcentaje, y es lo que dispara el auto-compact.

Mezclarlos es el error fácil: "65% del contexto" son 130k tokens con una ventana de 200k
(razonable por casualidad) pero **650k** con una de 1M, mucho después de que la calidad se
haya ido.

| Condición | Color | Hint |
|---|---|---|
| `tok < 0.8·SZ` | verde | — |
| `tok ≥ 0.8·SZ` | amarillo | `smart zone al limite · /arbol` |
| `tok ≥ SZ` | amarillo | `dumb zone · /clear si es descartable, si no /handoff` |
| `tok ≥ 1.5·SZ` | rojo | igual que arriba |
| `pct ≥ 80` | amarillo | `ventana al limite · /clear o /handoff` |
| `pct ≥ 90` | rojo | `sin ventana · /compact o /clear YA` |

Gana la condición más urgente. El color sigue al hint, así que ambos cuentan la misma historia.

## Configuración

Todo opcional, en `~/.claude/statusline.json`:

```json
{
  "smartZoneTokens": 200000,
  "windowWarnPct": 80,
  "windowCriticalPct": 90,
  "perModel": { "Opus 5 (1M)": 300000 }
}
```

Precedencia: `CLAUDE_SMART_ZONE_TOKENS` (env) > `perModel` > `smartZoneTokens` > default.
Un archivo mal formado **no rompe la statusline**: cae a los defaults y lo dice en la línea.

Colores: las constantes al tope del bloque Python — `GRN` (sano), `YEL` (aviso), `RED`
(crítico) para la barra, `O` para el nombre del directorio.

## Requisitos

- Claude Code (verificado en `2.1.266`)
- `python3` en el PATH — el instalador falla temprano si no está
- Una terminal con color de 24 bits (iTerm2, Ghostty, Kitty, WezTerm, Terminal.app
  reciente, Windows Terminal)

## Nota sobre Orca

`statusline.sh` reenvía el payload a `~/.orca/agent-hooks/claude-statusline.sh` si ese
archivo existe y es ejecutable. Es telemetría de Orca, que instala su propia statusline
**que no imprime nada** y puede pisar la clave en `settings.json`. Si no usás Orca el
bloque no hace nada (el guard `-x` falla). Si querés sacarlo, son 4 líneas al principio
del script.

## Diseño

`docs/design.md` tiene el razonamiento completo: qué trae y qué no trae el payload del
statusline, por qué la branch se lee del disco, por qué el umbral es absoluto, el comando
`/arbol`, y la lista de lo que se probó y no se puede hacer.
