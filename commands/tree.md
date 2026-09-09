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
