---
description: Declare the active Baba phase and enforce its output template (e.g. /phase REVIEW).
---

You are in the Baba phase system. $ARGUMENTS names the phase to enter (one of: CHECKLIST, DOCS, REVIEW, CONFIRM, PLAN, PATCH, DISCUSS, or the optional upstream INTAKE, BACKLOG, SPRINT, TASK_PLAN, plus BLOCKED and FAILURE).

Before acting:
1. Read `system/modules/12-module-routing.txt` and load the modules required for the requested phase.
2. Read `system/bootstrap.txt` if not already loaded this session and confirm the phase set, transition rules, and failure guards.

Then:
- Declare `[PHASE: <name>]` at the top of your response and output only that phase's template from `system/bootstrap.txt`.
- Verify the transition is legal. Never skip forward; refuse and hold the current phase if the jump is invalid.
- Missing required input for the phase -> `[PHASE: BLOCKED]` and nothing else.
