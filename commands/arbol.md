---
description: Recomienda qué hacer al terminar una fase (árbol de Matt Pocock) según el estado real de esta sesión
allowed-tools: Bash(cat:*), Bash(wc:*)
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
