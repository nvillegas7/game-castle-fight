# Agent Autonomous Loop Prompts
> Copy-paste the prompt for each role into `/loop 30m <prompt>` after telling the instance its role.

---

## How It Works

1. Spin up a new Claude Code terminal
2. Tell it: "You are A5" (it reads CLAUDE.md, onboards itself)
3. Run: `/loop 30m <paste the prompt below>`
4. The agent will check for work every 30 minutes autonomously

Each loop iteration:
- Reads dispatch.md for new tasks / QA_FAIL items / bugs
- Claims and executes if found
- Marks complete and checks for more
- Goes idle if nothing to do

---

## A0 — Lead Game Designer Loop

```
Read tasks/dispatch.md. Check the Coordination Log for any messages addressed to A0 or ALL since your last check. Check if any tasks are QA_FAIL that need design revision. Check tasks/qa-bug-tracker.md for new bugs that need design decisions. If there are new feature requests from the user in the coordination log, create design specs at tasks/design-*.md and file new tasks in dispatch.md. Update tasks/todo.md if the roadmap changed. Report what you found and what you did.
```

---

## A1 — Lead Programmer Loop

```
Read tasks/dispatch.md. Check for READY or QA_FAIL tasks where Owner-agent=A1. Check the Coordination Log for messages to A1 or ALL. If a task is available: claim it (set IN_PROGRESS), implement it, run tests (godot --headless -s tests/test_simulation.gd), set QA_REVIEW. Your domain: autoload/game_manager.gd, autoload/network_manager.gd, autoload/event_bus.gd, autoload/player_data.gd, project.godot, export_presets.cfg. Do NOT modify core/simulation.gd (A5 owns that) or scripts/ui/ (A2 owns that). If nothing to do, check tasks/qa-bug-tracker.md for infrastructure bugs. Report what you found and what you did.
```

---

## A2 — UI/UX Designer Loop

```
Read tasks/dispatch.md. Check for READY or QA_FAIL tasks where Owner-agent=A2. Check the Coordination Log for messages to A2 or ALL — especially from A6 requesting sprite_registry.gd UNIT_MAP wiring. If a task is available: claim it (set IN_PROGRESS), implement it, set QA_REVIEW. Your domain: scripts/ui/*.gd, scripts/game/sprite_*.gd, scripts/game/building_visual.gd, scripts/game/unit_visual.gd, scripts/game/effects.gd, scripts/game/castle_visual.gd, scripts/game/building_grid.gd, scenes/**/*.tscn, autoload/sprite_registry.gd. Do NOT create unit sprites (A6 does that). If A6 logged new sprites, add UNIT_MAP entries. Report what you found and what you did.
```

---

## A3 — Sound Designer Loop

```
Read tasks/dispatch.md. Check for READY or QA_FAIL tasks where Owner-agent=A3. Check the Coordination Log for messages to A3 or ALL. If a task is available: claim it (set IN_PROGRESS), implement it, set QA_REVIEW. Your domain: autoload/sfx.gd, assets/audio/**, default_bus_layout.tres. Downloaded SFX packs are at ~/Downloads/Dowloaded_Game_Assets/ (kenney_impact-sounds, Hammer_Free, kenney_rpg-audio, kenney_ui-audio, 80-CC0-RPG-SFX, kenney_music-jingles). Convert WAV to OGG with: ffmpeg -i input.wav -c:a libvorbis -q:a 4 output.ogg. Report what you found and what you did.
```

---

## A4 — QA Lead Loop

```
Read tasks/dispatch.md. Check for tasks with Status=QA_REVIEW — these need your verification. For each QA_REVIEW task: read its acceptance criteria, run the relevant test (godot --headless -s tests/test_simulation.gd for sim changes, godot --path castle_clash -- --autotest for visual changes), verify each criterion. If ALL pass: set Status=DONE, QA-verdict=PASS. If ANY fail: set Status=QA_FAIL, write specific failures in QA-notes. Also check tasks/qa-bug-tracker.md and file any new bugs you discover. Run godot --headless -s tests/test_behavior_audit.gd to check movement quality. Report what you reviewed and verdicts.
```

---

## A5 — Gameplay Programmer Loop

```
Read tasks/dispatch.md. Check for READY or QA_FAIL tasks where Owner-agent=A5. Check the Coordination Log for messages to A5 or ALL. If a task is available: claim it (set IN_PROGRESS), implement it in core/simulation.gd or data/ files, run tests BEFORE and AFTER (godot --headless -s tests/test_simulation.gd + godot --headless -s tests/test_behavior_audit.gd), set QA_REVIEW with before/after comparison. Your domain: core/simulation.gd, core/*.gd, data/units/*.tres, data/buildings/*.tres, data/factions/*.tres, data_scripts/*.gd. Also check tasks/qa-bug-tracker.md for gameplay bugs (combat, targeting, movement, AI, skills, economy). Report what you found and what you did.
```

---

## A6 — Technical Artist Loop

```
Read tasks/dispatch.md. Check for READY or QA_FAIL tasks where Owner-agent=A6. Check the Coordination Log for messages to A6 or ALL. If a task is available: claim it (set IN_PROGRESS), create the sprite using PIL/Pillow+NumPy (reference tools/generate_knight.py for patterns), output to assets/sprites/units/blue_{name}/ and red_{name}/, open the output PNG to verify quality, set QA_REVIEW. Log a coordination message asking A2 to add UNIT_MAP entry in sprite_registry.gd. Source assets at ~/Downloads/Dowloaded_Game_Assets/. Report what you found and what you did.
```

---

## Startup Commands (copy-paste per terminal)

Terminal 1 (A0): `You are A0, the Lead Game Designer.` then `/loop 30m Read tasks/dispatch.md...` (paste A0 prompt above)

Terminal 2 (A1): `You are A1, the Lead Programmer.` then `/loop 30m Read tasks/dispatch.md...` (paste A1 prompt)

Terminal 3 (A2): `You are A2, the UI/UX Designer.` then `/loop 30m Read tasks/dispatch.md...` (paste A2 prompt)

Terminal 4 (A3): `You are A3, the Sound Designer.` then `/loop 30m Read tasks/dispatch.md...` (paste A3 prompt)

Terminal 5 (A4): `You are A4, the QA Lead.` then `/loop 30m Read tasks/dispatch.md...` (paste A4 prompt)

Terminal 6 (A5): `You are A5, the Gameplay Programmer.` then `/loop 30m Read tasks/dispatch.md...` (paste A5 prompt)

Terminal 7 (A6): `You are A6, the Technical Artist.` then `/loop 30m Read tasks/dispatch.md...` (paste A6 prompt)

---

## Notes

- **30 minutes** is a good interval — enough time to complete most tasks between checks. Adjust to 15m for urgent sprints or 60m for background work.
- **File conflicts**: dispatch.md is the main contention point. Agents should read → claim → work → update in one pass. If a write fails due to modification, re-read and retry.
- **A4 (QA) should run at 15m** since it's the review bottleneck — faster QA cycles unblock everyone else.
- **A0 (Designer) can run at 60m** since design work is less frequent.
- Each loop iteration is stateless — the agent re-reads dispatch.md fresh each time, so it always has current state.
