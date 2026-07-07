# Design Flow — how screens get their look (adopted 2026-07-08)

## The failure this replaces (root-cause diagnosis)

The user commissioned design mockups (Desktop `v1/v2/v3.png`) built from the SAME
Tiny Swords assets we ship. They look dramatically better than the game did after
weeks of iteration. Forensics (see git history of 3.3b + `wf_772ab315` audit) found
the gap was never the assets — it was the workflow:

1. **Art was composed blind, in code.** Terrain/decoration placement lived as
   hand-written coordinates in GDScript. Every look-tweak = edit `.gd` → boot the
   full game → `capture.sh` → inspect 20 PNGs. Audit measured **~80–95s visual
   feedback latency + 1–2 min inspection ≈ 3–5 min per placement decision**, vs
   ~0.1s per full render in image space (50–100× gap). Nobody composes good art
   at 3 minutes/brushstroke.
2. **No pixel target existed IN the loop.** The v1/v2/v3 mockups lived on the
   Desktop — zero copies in the repo, never resolution-matched to captures, never
   diffed. We iterated toward verbal goals; each round was judged "better than
   last round", not "close to the target", so iterations plateaued at local optima.
3. **Acceptance was an element checklist, not composition parity.** "Trees ✓
   sheep ✓ gold ✓" all shipped while the field stayed **2.3× sparser** than the
   mockup (measured: object-content 12.9% vs 29.4%; flat-grass 82.3% vs 50.6%;
   central-field decoration coverage 7% vs 23%).
4. **Scale was inherited from the sim, never art-directed.** Castle = 14.7% of
   frame height in-game vs 24.9% in the mockup (**1.7× mismatch**); sim cells
   (28px) dictated ~56px buildings. Visual scale is independent of sim footprint —
   nobody ever set it deliberately.
5. **Global nerfs fought the art.** "Readability" fixes (T-039) alpha-faded every
   decoration (0.18–0.95, most 0.35–0.7), modulate-tinted zones, and tinted the
   water from native (71,171,169) down to (28,86,93) — pixel-verified. The mockups
   are 100% opaque, native palette everywhere — readability comes from *placement*
   (clean center lane), not transparency. Bonus finds: rocks randomly ROTATED
   (jagged pixel-art artifacts), procedural vector banners/flowers mixed into
   pixel art, and the edge-tile builders needed for coastlines
   (`_build_tiled_zone`, `_build_elevated_zone`) existing as dead code — never called.

## The flow

```
1. COMPOSE   tools/compose_<screen>.py — build the screen in image space from the
             real assets at real resolution, sim geometry constraints drawn in.
             Iterate HERE (~0.1s/render). Compare side-by-side vs reference EVERY
             round (lessons.md: the reference image is the spec).
2. APPROVE   Show the user the composed target next to the reference. The approved
             PNG is committed as design/<screen>_target.png — it IS the pixel spec.
3. PORT      Implement in-game by mechanically mirroring the compositor's LAYOUT
             table (same asset, same xy, same scale, same z-order). No creative
             decisions during the port — those all happened in step 1.
4. GATE      Capture the real screen; perceptual-diff vs the target (per-region
             color histogram / structural check in tests). "Looks close" becomes a
             measured number, like the determinism golden but for art.
```

## Rules (learned the hard way)

- **Compose in image space; port to code.** Never art-direct by editing GDScript
  coordinates against a 90s capture loop.
- **The compositor's LAYOUT table is the single source of truth.** The game reads
  the same numbers. If the port hand-translates, drift returns.
- **Full opacity, native palette.** No modulate tints, no alpha-faded decorations.
  Readability = placement (keep unit lanes clean), never transparency.
- **Scale is an art decision.** Landmark buildings (castles, towers) render at
  mockup scale regardless of sim footprint; sim hitboxes stay unchanged.
- **Exploit non-gameplay space.** All gameplay is x=[206,514]; the ~166px outer
  bands + water margins are free composition space — that's where framing lives.
- **HUD honesty.** The compositor blocks out real HUD zones (top bar, card hand) so
  the design is judged on what players actually see.

## Tooling

| Tool | Purpose |
|------|---------|
| `castle_clash/tools/compose_arena.py` | battle-arena compositor → `design/arena_target.png` (`--grid` overlays sim geometry) |
| `castle_clash/design/*_target.png` | approved pixel specs (committed) |
| `tests/capture.sh` | still the source of REAL captures for the gate |
| (per-screen compositors as needed) | menus follow the same pattern: compose → approve → port → gate |

## Status

- [x] Arena target composed (3 rounds, ~0.14s each) — matches mockup-v2 family
- [x] User approved `design/arena_target.png` (2026-07-08)
- [x] Ported to `game_arena.gd`/`castle_visual.gd` from LAYOUT (commit 8b565f6)
- [x] Parity gate: 4 arena detectors in `tests/test_screen_layout.gd`,
      RED on old build → GREEN after port (15/15)
- [ ] Menu screens: same treatment (compose vs CR reference → approve → port) — NEXT
