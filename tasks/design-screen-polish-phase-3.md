# Phase 3 Screen Polish — Loading / Main Menu / Victory-Defeat

> **Status**: DRAFT (2026-04-18)
> **Author**: A0
> **Owner-agent**: A2 (A6 coordination where new sprite atlases needed)
> **Benchmarks**: Clash Royale, Kingdom Rush
> **Goal**: Raise our three non-gameplay screens to CR/KR visual standards while keeping the Tiny Swords identity.

---

## Executive summary

Our three screens each work mechanically but feel unfinished next to CR/KR. The biggest gaps are (1) weak primary-CTA visual dominance on main menu, (2) static loading screen with no reward moments, (3) victory celebration that doesn't deliver the **Kingdom Rush star-pop** dopamine hit.

This spec closes all three with A2-owned Godot UI work + small amounts of A6 compositing where new pre-made art beats runtime construction. No gameplay changes.

Research inputs: `https://pixelfrog-assets.itch.io/tiny-swords` (asset catalog), CR/KR design breakdowns (Interface In Game, therookies, gornicki, Karim Muhtar case study, Emily Miles KR analysis, NN/Group animation standards), plus local audit of Tiny Swords assets in `~/Downloads/Dowloaded_Game_Assets/Tiny Swords (Free Pack)/` and already-imported sprites in `castle_clash/assets/sprites/`.

---

## Design principles (applies to all 3 screens)

### Color language (CR convention, enforce consistently)

| Role | Color | Use |
|---|---|---|
| **Primary CTA** | **Yellow** (#F2C94C gold — matches Tiny Swords Ribbon_Yellow) | BATTLE, PLAY AGAIN, START — one per screen max |
| **Secondary action** | **Green** (#4CAF50) | Secondary buttons (Shop, Menu, Back) |
| **Tertiary / info** | **Blue** (#2980B9 — matches Tiny Swords blue team) | Info panels, faction select |
| **Alert / notification** | **Red** (#C0392B — matches Tiny Swords red team) | Errors, defeat, warnings |
| **Passive background** | Cream/parchment (#E8D4A9) + dark brown outline (#3E2817) | Paper, WoodTable, ribbon fills |

### Typography

- **Primary font**: `MorkDungeon.ttf` (already in `assets/fonts/`) — we have it. Keep using it.
- **Fallback/body**: Godot default. Later, can swap in Google Fonts "Lilita One" if MorkDungeon feels too thin at small sizes.
- **Outline**: 2-3 px dark navy (#16202E) outline on all headline text. Thicker (4-6 px) on victory/defeat titles.
- **Shadow**: +2/+2 px offset drop shadow (50% alpha black) below outline layer for depth.

### Animation timings (NN/Group + CR observed)

| Animation | Duration | Easing |
|---|---|---|
| Button press (down) | 80 ms | ease-out |
| Button press (rebound) | 200 ms | cubic-bezier(0.34, 1.56, 0.64, 1) (overshoot) |
| Primary CTA pulse loop | 1.2 s | ease-in-out-sine, scale 1.0→1.04→1.0 |
| Screen cross-fade | 250 ms | linear |
| Tab slide | 350 ms | ease-out-cubic |
| Victory/defeat title scale-in | 350 ms | ease-out-back (overshoot 1.7) |
| Star pop (KR pattern) | 300 ms each + 200 ms gap | scale 0→1.2→1.0 + radial flash |
| Loading tip rotation | 3.5 s display + 250 ms cross-fade | linear |

### UI depth rule (CR)

Never more than one popup/modal layer at a time. Popups cover ~70% of screen, keep background visible (arena stays at 40% dim on end screen; main menu stays visible when Settings modal opens).

---

## Screen 1 — Loading Screen

### Current state
- Scenic background built via `_build_scenic_background()` (castle, trees, clouds)
- Logo at y=320-620 wrapped in SpecialPaper NinePatchRect
- Simple progress bar at bottom (tween 0→30%→70%→100% over ~2.6 s)
- `SFX.play_music("loading_ambient")` already playing
- Status label cycles "Loading assets..." → "Preparing battle..."

### Target state (CR/KR benchmark)
- Full-bleed painted scene feels intentional, not procedural
- Logo **is** the hero — avoid visual noise competing with it
- Progress bar reads as a medieval wooden frame, not a ColorRect
- **Rotating tip** during load (3.5 s per tip, cross-fade)
- Smooth 250 ms cross-fade OUT to main menu (currently hard-cuts)

### Concrete changes

**1. Scenic background refresh** (A2 owns layout, A6 optional)
- Keep existing castle + trees + clouds composition
- Add subtle **parallax**: clouds drift slowly rightward at 8 px/s
- Add **2-3 animated birds** crossing the sky (use `Birds.png` in assets) on a 12-15 s loop, spawn offscreen left, cross at y=150-300 with gentle sine bob
- Darken the bottom 20% of the sky gradient to ground the scene and give logo/progress bar breathing room

**2. Logo presentation**
- Remove the SpecialPaper NinePatchRect wrapper — the v5 logo already has its own framing via ribbon + radial fade (per A6's T-092 v5 work)
- Center logo at y=280-580 (shift up 40 px to give space for rotating tip below)
- Add subtle **idle bob**: translate y ±4 px on a 3 s ease-in-out-sine loop to give the scene life

**3. Progress bar — wooden frame**
- Replace ColorRect-based bar with NinePatchRect using `BigBar_Base.png` (outer) + `BigBar_Fill.png` (inner)
- Position: centered, y=900, width 500 px, height 32 px
- Fill tween unchanged (0→30→70→100 over total ~2.6 s), but easing bumped to `ease-out-cubic` for snappier first segment
- Add a **subtle shine sweep** across the fill every 1.5 s (white gradient moving left→right, 200 ms duration, 60% alpha)

**4. Rotating tip strip** (NEW)
- Position: below progress bar, y=960, width 600 px, centered
- Tinys Swords `RegularPaper.png` as background, 9-patch stretched
- Text: 1 of ~10 rotating tips, MorkDungeon 18 px, dark brown on parchment
- Rotation: display 3.5 s, cross-fade to next tip over 250 ms
- Sample tip copy (A0 to review, A2 can start with these):
  - "Wall buildings redirect enemy paths — use them to create chokepoints."
  - "Priests heal nearby allies every few seconds. Keep them behind your front line."
  - "Castle Wrath triggers at 30% HP — a one-time blast wipes nearby enemies."
  - "Place Gold Mines early for compound income (+15% per mine)."
  - "Archers shred Footmen (Pierce vs Light = 150% damage)."
  - "Siege units (Catapult, Ballista) crush buildings but lose to speed."
  - "Upgrade buildings give stacking buffs — Armory/Blood Altar."
  - "Mages cast fireball in a 1.5-cell radius — cluster your enemies at your peril."
  - "Mirror matches only use your selected faction. Blitz mode doubles income."
  - "Flying units (Gryphon, Wyvern) ignore terrain — plan anti-air."

**5. Transition OUT**
- Currently `_go_to_menu()` hard-cuts via `get_tree().change_scene_to_file()`
- Wrap with `SceneTransition` autoload (already exists per 2026-04-07 coord log entry) for 250 ms fade-to-black
- Verify audio crossfade: loading_ambient → menu_theme fades cleanly via existing `SFX.play_music()` crossfade

### Files-touch (T-098)
- `scripts/ui/loading_screen.gd` — parallax, bird animation, progress bar NinePatch swap, tip rotation system, SceneTransition wrap
- `scenes/ui/loading_screen.tscn` — progress bar node replacement, tip strip node
- **A6 coord (optional)**: pre-composited logo already done; no new art needed unless A2 wants a dedicated "loading hero scene" sprite — skip for this phase

### Acceptance (T-098)
- [ ] Clouds parallax at 8 px/s rightward
- [ ] 2-3 birds loop across sky every 12-15 s
- [ ] Logo idle-bobs ±4 px on 3 s loop
- [ ] Progress bar uses BigBar_Base/Fill NinePatchRect
- [ ] Shine sweep across progress fill every 1.5 s
- [ ] Rotating tip strip shows 1 of 10 tips, rotates every 3.5 s with 250 ms cross-fade
- [ ] 250 ms SceneTransition fade-out to main menu
- [ ] No regression in existing logo placement or music crossfade
- [ ] Matches CR feel: painted scene, no static feel, intentional progress communication

---

## Screen 2 — Main Menu

### Current state (inferred from `main_menu.gd` size 1676 lines + earlier coord log)
- 5-tab bottom bar (Battle / Shop / Army / Social / Settings)
- Yellow BATTLE button, pulse animation
- Faction selection, perk selection, game mode selector
- Progression display (arena banner, trophy bar) with wood_table/banner_slot textures
- Avatar header
- Scenic painted background

### Target state (CR/KR benchmark)
- BATTLE button is **unmistakably** the focal point — brighter, bigger pulse, shine sweep
- Top bar currency (gold, gems if applicable) reads universally — icon + counter left-pinned
- Bottom tab bar has raised/larger center tab (CR pattern)
- Persistent bottom-bar pattern (KR) — tabs never hide even during modals
- Subtle parallax on background (sky 0.3x vs foreground 1.0x)
- Animated idle elements (flags waving, smoke from chimneys, banners flapping)

### Concrete changes

**1. BATTLE button emphasis**
- Currently yellow, 460×100 — per earlier coord log
- Upgrade to: 500×110 (10% bigger), `Ribbon_Yellow.png` as NinePatchRect base, `BigBlueButton_Regular.png` as inner shine panel
- **Pulse loop**: 1.2 s, scale 1.0→1.04→1.0, ease-in-out-sine (currently 1.0→1.05 per earlier log, tightening to 1.04 for CR parity)
- **Shine sweep**: additive white gradient, 200 px wide, moving left→right across button every 1.8 s, 400 ms duration
- Text "BATTLE" in MorkDungeon 48 px, gold fill, 3 px dark navy outline, 2/2 drop shadow
- Position: centered, y=840 (above tab bar which is y≈1180-1280)

**2. Top currency bar** (NEW or enhance existing)
- Left-pinned at y=20-80, height 60 px
- Gold icon (Icon_04 from Tiny Swords — coin variant) + counter "350" in MorkDungeon 24 px, gold fill, dark outline
- Counter **tick animation** when gold changes: scale 1.0→1.2→1.0 over 200 ms with +1, +5 floating text above
- Reserve right side for future gems counter (Phase 4 — ranked currency)

**3. Tab bar center emphasis** (CR pattern)
- Currently 5 equal tabs. Raise the center tab (Battle) by 12 px with a wider selected indicator
- Selected tab uses `Banner_Slots.png` + gold ring, 72×72 icon area
- Non-selected tabs stay at 56×56, neutral brown tint
- Tap transitions: 350 ms ease-out-cubic slide (currently 0.2s per coord log — tighten to 350 ms + icon bounce on selection)

**4. Background parallax**
- Split scene into 2 layers:
  - Sky/clouds layer (back): moves at 0.3x rate of any input drag
  - Foreground terrain/castle (front): moves at 1.0x
- Idle auto-scroll of sky layer: 3 px/s rightward (continuous, wraps)
- Idle animations:
  - 2-3 flags on castle towers waving (±4° rotation, 1.5 s loop, sine)
  - 1-2 smoke columns from chimneys (use Dust_01 particles at 0.5 alpha, rising ±40 px over 2 s)
  - Water foam along bottom edge already exists (T-060) — keep

**5. Persistent bottom bar** (KR pattern)
- When Settings modal opens, keep bottom tab bar visible (modal covers top ~70%, bar stays at bottom)
- When Shop/Army/Social tabs open, the tab bar should still be tappable — avoid full-screen content

**6. Progression display polish**
- Arena banner + trophy bar already built (T-046). Polish:
  - Add gentle **pulse on rank-up**: banner scale 1.0→1.1→1.0 over 400 ms when trophies cross threshold
  - Trophy icon (Icon_07 or similar) with **ding-ding counter** animation when trophies change

### Files-touch (T-099)
- `scripts/ui/main_menu.gd` (1676 lines — surgical edits only)
- `scenes/ui/main_menu.tscn`
- **A6 coord (optional)**: if A2 wants a pre-composited "castle + flags + smoke" animated sprite sheet, A6 can composite; otherwise do it in Godot with Sprite2D nodes + tweens

### Acceptance (T-099)
- [ ] BATTLE button: 500×110, pulse 1.2 s scale 1.0→1.04, shine sweep every 1.8 s
- [ ] Gold currency top-left with counter tick animation
- [ ] Tab bar center (Battle) raised 12 px, gold ring selected indicator
- [ ] Tab transitions 350 ms ease-out-cubic + icon bounce
- [ ] Sky layer parallax at 0.3x of input drag, 3 px/s idle auto-scroll
- [ ] 2-3 castle flags waving ±4° on 1.5 s loop
- [ ] 1-2 smoke columns rising from chimneys
- [ ] Bottom tab bar stays visible when modals (Settings) open
- [ ] Rank-up pulse on progression banner when trophies cross threshold
- [ ] No regression in existing faction/perk/mode selection flows

---

## Screen 3 — Victory / Defeat (End Screen)

### Current state
- Dark overlay + ribbon behind title + parchment behind stats
- Shows victory/defeat, kill breakdown, buildings built, MVP unit, trophy change, share-to-clipboard button (T-017, T-048)
- Confetti + scale-in title animation + gold highlight (T-048)

### Target state
- **KR star pop is the headline feature** — 1-3 stars based on castle HP remaining. This is the cheapest, highest-ROI visual steal.
- Victory title hits harder: gold-on-gold with overshoot scale + radial burst
- Defeat subdued, not sad — tactical, stoic, "retry now" framing
- Arena stays visible at 40% dim behind panel (currently 88% dim — too much)

### Concrete changes

**1. Dim overlay tuning**
- Current: `Color(0.06, 0.04, 0.02, 0.88)` — too opaque, arena invisible
- Change to: `Color(0.0, 0.0, 0.0, 0.40)` — CR-style dim, arena barely visible through panel
- Arena stays slightly visible = player feels "in the match" rather than "kicked to menu"

**2. Star-pop visual (headline feature)**
- Compute stars based on own castle HP at match end:
  - **3 stars**: 75%+ HP remaining
  - **2 stars**: 40-74% HP remaining
  - **1 star**: 1-39% HP remaining
  - **0 stars**: lost (castle dead) → show crossed-out/grayed-out stars instead
- Position: top of panel, between title and stats, centered horizontally
- 3 star slots at 72×72 px each, spaced 100 px apart
- **Pop sequence** (1 star at a time):
  - 0 ms: slot visible as dim outline
  - 0 ms: star pops in — scale 0→1.2→1.0 over 300 ms, ease-out-back (overshoot 2.0)
  - 150 ms: radial flash behind star (expanding white circle, 0 → 80 px radius, alpha 0.8 → 0 over 200 ms)
  - 300 ms: star settles
  - 500 ms (200 ms gap): next star pops
- Full sequence: ~1.5 s for 3 stars
- Star sprite: use `Icon_05.png` or `Icon_06.png` from Tiny Swords Icons — whichever is the star. If neither fits, A6 composites a gold 5-point star (simple shape)
- **Defeat variant**: show 3 grayed-out stars with dark X overlay

**3. Victory title animation** (refine existing)
- Current: scale-in exists. Tighten to:
  - 0 ms: invisible (scale 0.5, alpha 0)
  - 350 ms: scale 1.0, alpha 1.0, ease-out-back (tension 1.7)
  - Simultaneously: radial gold particle burst (20-40 particles, 300 ms lifetime) behind title
- Title text: "VICTORY!" in MorkDungeon 80 px, gold fill (#F2C94C), 6 px dark navy outline, 4/4 drop shadow
- Defeat: "DEFEAT" in MorkDungeon 72 px (smaller — not the celebration moment), desaturated brown (#6B4423), 5 px outline
- Keep ribbon behind title (already done)

**4. Stats card refinement**
- Current parchment background — keep
- Reorganize stats vertically:
  - **Stars** (top, prominent)
  - **Match duration** (MVP card — existing)
  - **Kills dealt** + **kills received** in 2-column layout
  - **Buildings built** + **gold earned** in 2-column
  - **MVP unit** with sprite preview (already done T-048)
- Add subtle **slide-in** for each stat row: stagger by 100 ms, slide from right, ease-out-cubic 300 ms each. Sequence plays AFTER stars finish (~1.5 s delay)

**5. Trophy change animation** (refine)
- Already exists (T-046)
- Tighten: trophy counter ticks up/down with ding-ding sound (already wired — SFX.play_ui)
- Add +X or -X floating text above counter for 1 s, fade out
- Sequence plays AFTER stats slide-in (~3 s total delay from screen open)

**6. Button refresh**
- "PLAY AGAIN" — yellow NinePatchRect using `Ribbon_Yellow.png` or `BigBlueButton_Regular.png` tinted yellow, 280×80 px
- "MENU" — smaller, brown/neutral, 200×60 px (secondary action)
- Both with 80 ms press-down + 200 ms overshoot rebound

**7. Confetti / celebration particles** (refine existing)
- Currently exists (T-048 confetti). Cap at 30 particles for perf, 1.2 s lifetime, gravity 50 px/s²
- Only on victory. Defeat has NO particles (respect the moment)

**8. Music**
- Victory: `victory_fanfare` plays on screen open (already wired)
- Defeat: `defeat_fanfare` plays on screen open (already wired)
- Keep as-is — no changes needed

### Files-touch (T-100)
- `scripts/ui/end_screen.gd` (475 lines, surgical)
- `scenes/ui/end_screen.tscn`
- `scripts/game/effects.gd` (possibly — for star-pop radial flash, reusable from existing VFX helpers)
- **A6 coord**: if `Icon_05/06` aren't obvious stars, A6 composites a simple gold 5-point star sprite (1 hour of work)

### Acceptance (T-100)
- [ ] Dim overlay at 40% alpha (arena visible through panel)
- [ ] 1-3 stars computed from castle HP% remaining
- [ ] Stars pop sequentially (300 ms each + 200 ms gap) with radial flash
- [ ] Defeat shows 3 grayed stars with X overlay (no pop animation)
- [ ] Victory title scale-in 350 ms ease-out-back + radial gold particle burst
- [ ] Defeat title desaturated, no particles
- [ ] Stats rows stagger-slide-in after stars finish
- [ ] Trophy change animates with +X floating text
- [ ] PLAY AGAIN button yellow NinePatchRect, 280×80, overshoot rebound
- [ ] No regression in existing T-017/T-048 stats/confetti/MVP work

---

## Cross-cutting: shared helpers A2 should build once

These help all 3 screens + future UI work:

1. **`SceneTransition` helper** — already exists (2026-04-07), verify 250 ms cross-fade is the default
2. **`AnimatedButton` scene** — wraps a Button/TextureButton with standardized press animation (80 ms down + 200 ms overshoot rebound). Use everywhere.
3. **`PulseEffect` component** — attach to any Control for 1.2 s scale 1.0→1.04 loop (add `@export` for timing so it's tunable per-use)
4. **`StarPopSequence` component** — reusable star-pop animation (takes count 0-3, callback on complete). Reuse in tutorial rewards, season pass rewards (Phase 4+)
5. **`TipRotator` component** — rotating text/icon carousel. Reuse on end screen for "did you know" tips (Phase 4+)

---

## A6 coordination

Minimal new sprite work needed. A6 involvement only if A2 decides Godot runtime composition is slower than pre-composited sprite atlases. Specifically:

1. **Gold star sprite** (if Icon_05/06 aren't clearly stars) — 1 hour. 64×64 px gold 5-point star with dark outline, transparent background, matches Tiny Swords palette.
2. **Wooden frame for progress bar** — if `BigBar_Base.png` doesn't 9-patch cleanly, A6 composites a 600×40 wooden frame with rope tassels. Optional.
3. **Animated flag sprite sheet** — if A2 wants pre-animated waving flags (8-frame loop) for main menu castle, A6 can composite. Otherwise A2 does it via Sprite2D + rotation tween.

A2 to flag any of these in the coord log if needed.

---

## Implementation order

**Week 1**: T-098 Loading Screen (smallest, high-reward — builds helpers)
**Week 2**: T-100 End Screen (star pop is the big win)
**Week 3**: T-099 Main Menu (biggest file, saves for last)

Total ~3 weeks of A2 work. Can parallelize with A5's T-096 (castle shrink) and A4's T-093 (general polish audit).

---

## Success metric

User playtests the game and says "this feels like a real mobile game" without prompting. Specifically:
- Loading screen feels intentional, not a placeholder
- Main menu's BATTLE button is irresistible (tap instinct)
- Victory feels rewarding ("I got 3 stars!"), defeat feels like a setback not a punishment

---

## Out of scope (Phase 4+ followups)

- Full ranked mode UI (Phase 4)
- Season pass / battle pass UI (Phase 4+ monetization)
- Chat / social screens (Phase 5 community features)
- Landscape mode (currently portrait-only, per CR convention)
