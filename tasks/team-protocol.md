# Team Communication Protocol
> 4 agents working in parallel. Coordinate through these shared files.

## Agent Roles
| Agent | Role | Owns |
|-------|------|------|
| **QA** | Testing, bug finding, automated test runs, sign-off | `tasks/qa-*.md`, `tests/` |
| **Mechanics** | Simulation, combat, AI, balance | `core/`, `data/` |
| **Visual** | Sprites, UI, effects, polish | `scripts/game/sprite_*.gd`, `scripts/ui/`, `scenes/` |
| **Game Designer** | Features, depth, new content, roadmap | `tasks/design-*.md`, game design docs |

## Communication Files
- `tasks/qa-bug-tracker.md` — QA files bugs, agents update status when fixed
- `tasks/qa-combat-report.md` — QA combat analysis from automated AI-vs-AI tests
- `tasks/qa-accountability-report.md` — QA quality assessment
- `tasks/team-protocol.md` — This file, read by all agents
- `memory/active-session.md` — QA session state

## Workflow
1. **Game Designer** creates feature specs in `tasks/design-*.md`
2. **Mechanics/Visual** agents implement features
3. **QA** runs automated tests: `godot --headless -s tests/test_simulation.gd` (104 tests)
4. **QA** runs visual tests: `godot --path castle_clash -- --autotest` (30 frames + game state JSON)
5. **QA** analyzes screenshots and game state, files bugs in tracker
6. **QA** signals "READY FOR NEXT FEATURE" when all bugs are fixed and tests pass

## QA Sign-Off Protocol
Before any feature is considered "done":
- [ ] Headless simulation tests pass (104/104)
- [ ] Visual autotest shows feature rendering correctly
- [ ] No new bugs in bug tracker
- [ ] Combat report shows no targeting/behavior issues
- [ ] QA writes "APPROVED" in the relevant tracker entry

## How to Request QA Testing
Any agent can write to `tasks/qa-test-request.md`:
```
## Test Request
- Changed files: [list]
- What to verify: [description]
- Priority: HIGH/MEDIUM/LOW
```
QA will pick it up and run tests.

## Current QA Capabilities
- **Headless sim tests**: 104 tests covering FP math, sprites, combat, income, building sell
- **AI-vs-AI visual test**: 60 seconds of gameplay, 30 screenshots, full game state JSON
- **Automated analysis**: Pixel analysis for rendering verification
- **Screenshot review**: Can read and analyze game frames directly
