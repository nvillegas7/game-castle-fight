# Archive — retired 7-agent process artifacts

These files are historical artifacts of the **7-agent markdown-polling model** that ran
Castle Fight development through 2026-07-06. In that model, agents A0–A6 ran `/loop` crons
on fixed intervals, claimed tasks and messaged each other through `dispatch.md`, and gated
work via a per-agent onboarding + QA protocol.

On **2026-07-07** that model was retired in favor of a **single orchestrator + ephemeral
scoped subagents**. The reasons and the new pipeline are in `tasks/PROCESS.md`
(and the rationale audit in `tasks/plan-polish-parity.md` Part 1).

## What's here and what replaced it

| Archived file | What it was | Replaced by |
|---------------|-------------|-------------|
| `dispatch.md` | 3,775-line task DB + inter-agent coordination log | `tasks/backlog.md` (live OPEN list) + git history (permanent log) |
| `team-protocol.md` | QA capabilities + agent coordination protocol | `tasks/PROCESS.md` §2–3 (pipeline + gate) |
| `agent-loop-prompts.md` | The `/loop` cron prompts each agent self-invoked | Nothing — cron polling is retired; orchestrator spawns subagents on demand |

## Why kept

Reference only: root-cause write-ups, historical decisions, and the audit trail of the
~85 tasks completed under the old model. **Do not add to these files or act on them as
current instructions.** The A0–A6 roles survive only as *subagent file scopes* in
`tasks/PROCESS.md` §6 — not as standing agents.

Superseded by `tasks/PROCESS.md` as of 2026-07-07.
