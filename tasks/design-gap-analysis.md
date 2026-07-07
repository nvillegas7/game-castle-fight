# Gap Analysis: Current Game vs Benchmarks
> **Author**: A0 (Game Designer) | **Date**: 2026-04-05
> **Benchmarks**: Kingdom Rush (battle screen), Clash Royale (menus), WC3 Castle Fight (strategy)
> **Current state verified via**: Full codebase exploration + competitive research

---

## GAME NAME DECISION

**"Castle Clash" is taken** by IGG (millions of downloads). We MUST rename before any public deployment.

### Top Candidates (verified not taken by any existing game)

| # | Name | Why |
|---|------|-----|
| 1 | **Rampart Rivals** | Perfectly describes the game — build ramparts (walls), fight rivals. Alliterative. Clear genre signal. Works as brand. |
| 2 | **Siege Sworn** | Epic, unique. "Sworn" evokes commitment. Two syllables each, rolls off the tongue. |
| 3 | **Ironkeep** | Single compound word. Strong brand. Easy to type/search. Works across cultures. |
| 4 | **Castle Fray** | "Castle" = clear genre. "Fray" = unique vs all the Clash/War/Siege games. Short, clean. |
| 5 | **Fief Fight** | Shortest, punchiest. Strong alliteration. "Fief" = medieval land grant. |

**Recommendation**: **Rampart Rivals** — it literally describes what players do (build ramparts, rival each other). Alliterative names are proven memorable in mobile (Candy Crush, Fruit Frenzy, Pocket Planes). Works for App Store search. No trademark conflicts found.

**Runner-up**: **Ironkeep** if we want a single-word brand (easier logo, domain, hashtag).

### Logo Brief (for UI/UX Artist — A2)
Once name is chosen:
- Style: Tiny Swords pixel art aesthetic, hand-painted feel
- Elements: Two opposing castle towers/ramparts, crossed swords or banner between them
- Colors: Blue vs Red (faction colors), gold accents
- Must work at: 512x512 (app icon), 128x128 (in-game), 32x32 (favicon)
- Reference: Swords.png from our Tiny Swords assets as starting point
- Format: PNG with transparency + square app icon variant

---

## SECTION 1: BATTLE SCREEN — Us vs Kingdom Rush

### What Kingdom Rush Does That We Don't

| Gap | KR Approach | Our Current State | Impact | Effort |
|-----|------------|------------------|--------|--------|
| **Terrain quality** | Hand-painted, lush, multi-toned | Flat ColorRects (grass=single green, dirt=single brown) | HUGE — first thing players notice | Medium |
| **Radial building menu** | Tap tower → radial options appear around it | Right-click to sell, no info popup | High — feels modern vs desktop-era | Medium |
| **Wave preview** | Skull icon → preview incoming enemies, tap again to send early for bonus gold | "WAVE 1" text announcement, no preview | High — adds tactical depth | Small |
| **Environmental storytelling** | Every map tells a story through terrain details | Random scatter of decorations | Medium — polish feel | Small |
| **Particle effects density** | Particles on tower upgrades, attacks, environment | Basic death poof, arrow, heal sparkle | High — "alive" feeling | Medium |
| **Visual hierarchy** | Muted earth bg, bright interactables | Everything same brightness level | High — readability | Small |
| **Juice on interactions** | Elastic menus, screen shake, satisfying feedback | Basic scale tween on placement | Medium — "feel" | Small |
| **No idle state** | Something is always animating (clouds, birds, water) | Clouds drift, but terrain/buildings are static | Medium — alive world | Small |

### What We Already Do Well (Keep)
- Portrait mobile layout with clear zone separation ✓
- Card hand with cost/stats/lock indicators ✓
- Building grid with ghost preview ✓
- Team color differentiation (blue vs red) ✓
- HP bars on units and buildings ✓
- Arrow projectile and heal effect sprites ✓
- Camera zoom for detail viewing ✓
- Death animations with poof effects ✓

### Specific Battle Screen Iterations (Priority Order)

#### ITERATION B1: Terrain Upgrade (HIGHEST PRIORITY)
**Problem**: Grass zones are flat RGB(0.38, 0.58, 0.25) ColorRects. Combat lane is flat RGB(0.72, 0.6, 0.38). This screams "prototype."

**Fix**: We already have tileset PNGs in `assets/sprites/terrain/Tileset/`. Use them.
- Replace GrassMain ColorRect with tiled grass texture (Tileset variant, tiled as TextureRect)
- Replace CombatLane ColorRect with tiled dirt/path texture
- Add grass-to-dirt transition sprites at zone boundaries
- Add subtle texture variation (2-3 tileset color variants blended)
- Water edges already use textures — extend this pattern to all terrain

**Acceptance**: No flat ColorRects visible. Terrain has texture variety. Zones visually distinct through texture, not just color.

#### ITERATION B2: Visual Hierarchy — Mute Background, Brighten Interactables
**Problem**: Everything is same brightness. Cards, terrain, units, decorations — all compete for attention.

**Fix**:
- Darken terrain by 15-20% (lower modulate on grass/dirt nodes)
- Reduce decoration alpha from 0.7-0.95 → 0.5-0.7
- Increase unit sprite brightness/contrast slightly (+10% modulate)
- Make selected card glow MORE (pulse the gold border)
- Building grid overlay: brighter green/red for valid/invalid placement
- HUD gold text: add subtle glow/shadow for pop

**Acceptance**: Screenshot test — eyes are drawn to units and cards first, not terrain/decorations.

#### ITERATION B3: Wave Preview System
**Problem**: "WAVE 1" text is informational noise. Player gets no strategic value from it.

**Fix** (Kingdom Rush-inspired):
- 5 seconds before wave, show a small preview panel at top of combat lane
- Preview shows: unit sprite icons that will spawn this wave (both sides)
- Counts: "x3 Footman, x2 Archer" etc.
- Panel auto-dismisses when wave spawns
- Future: "Send Early" button for bonus gold (risk/reward mechanic from KR)

**Acceptance**: Player can see what's coming before it spawns. Makes building decisions more tactical.

#### ITERATION B4: Building Interaction Radial Menu
**Problem**: Right-click to sell feels desktop, not mobile. No way to see building info in-game.

**Fix**:
- Tap owned building → radial menu appears around it (3 options):
  1. **Sell** (coin icon + refund amount) — replaces right-click
  2. **Info** (i icon) — shows unit stats popup (HP, DMG, skill)
  3. **Cancel** (X icon) — dismisses menu
- Menu appears as 3 circular buttons in a semicircle above the building
- Animated expand (0.2s scale from 0) like KR
- Dismiss on tap elsewhere

**Acceptance**: Long-press or tap building shows radial. Sell works from radial. Info panel shows unit stats.

#### ITERATION B5: More Particle Effects
**Problem**: Deaths are small poofs. Attacks have no impact particles. Castle damage has fire but it's procedural circles.

**Fix** (using our UNUSED Tiny Swords assets):
- Unit death: Explosion_01/02 plays at death position (in addition to poof)
- Siege attack impact: Explosion effect at target
- Castle low HP: Fire_01/02/03 sprite sheet animation (replacing procedural circles)
- Unit walking: Dust_01/02 at feet periodically
- Building placement: Dust burst from ground
- Healing: Water Splash effect on heal target

**Acceptance**: Every major game event has a visible particle effect. No "silent" actions.

#### ITERATION B6: Idle World Animation
**Problem**: Between waves, the battlefield feels dead. Only clouds move.

**Fix**:
- Trees: Subtle sway animation (sin wave on rotation, ±3 degrees, 3s cycle)
- Water edges: Foam animation using Water Foam.png sprite sheet
- Bushes: Very slight scale pulse (0.98-1.02, 5s cycle)
- Building spawn buildings: Subtle smoke from chimney (3 small circles rising)
- Income buildings: Coin sparkle already exists — make it more visible

**Acceptance**: When game is paused or between waves, the world still feels alive.

#### ITERATION B7: Gold Bar Redesign
**Problem**: Current gold bar is a thin dark strip at Y=1000-1040. Easy to miss. Not satisfying to watch fill.

**Fix** (Clash Royale elixir bar inspired):
- Taller bar (50px instead of 40px)
- Segmented: visual tick marks every 50g
- Fill animation: smooth lerp when gold changes (not instant)
- Income pulse: brief glow/flash on each income tick (+20g)
- Show next building cost as a marker on the bar ("you need THIS much more")
- Icon: Coin sprite from Tiny Swords instead of text "Gold:"

**Acceptance**: Gold bar is visually prominent, satisfying to watch fill, and shows progress toward next purchase.

---

## SECTION 2: MENU SCREEN — Us vs Clash Royale

### What Clash Royale Does That We Don't

| Gap | CR Approach | Our Current State | Impact | Effort |
|-----|------------|------------------|--------|--------|
| **Battle button dominance** | Center, yellow, largest element, animated | Green, mid-screen, pulsing but not dominant | HUGE — conversion to play | Small |
| **Color hierarchy** | Yellow=CTA, Green=positive, Red=alert, Blue=bg | All brown/dark tones, no hierarchy | High — visual clarity | Small |
| **Progression on home screen** | Trophies, arena name, card deck, chests | Only trophies + rank name | High — motivation | Medium |
| **Reward slots / return hooks** | 4 chest slots with timers | Nothing | High — retention | Large |
| **Card deck visible** | 8-card deck always shown on home | Hidden until battle | Medium — identity | Small |
| **Objects as buttons** | Tap chest to open, tap card to view | Labeled text buttons | Medium — premium feel | Medium |
| **Smooth transitions** | Everything animates between states | Instant panel show/hide | Medium — polish | Small |
| **Arena theming** | Each trophy range has unique visual theme | Static scenic background | Medium — progression feel | Medium |

### What We Already Do Well (Keep)
- 5-tab bottom navigation ✓
- Scenic background with castle/trees/clouds ✓
- Faction selection with descriptions ✓
- Trophy count + rank display ✓
- Player avatar in header ✓

### Specific Menu Iterations (Priority Order)

#### ITERATION M1: Battle Button Redesign (HIGHEST PRIORITY)
**Problem**: Battle button is green RGB(0.1, 0.48, 0.18), competes with other elements. Not the visual centerpiece.

**Fix** (Clash Royale pattern):
- Color: **YELLOW/GOLD** — RGB(1.0, 0.85, 0.2) with darker border RGB(0.8, 0.6, 0.1)
- Size: **460x100px** (currently 400x90) — make it the biggest element
- Position: Center screen, slightly above middle
- Text: **"BATTLE"** in bold (drop the "(vs AI)" — that's a detail, not a CTA)
- Animation: Continuous pulse scale 1.0→1.05 (bigger than current 1.03) + subtle glow
- Shadow: Larger, more dramatic drop shadow
- Use BigBlueButton or BigRedButton texture from Tiny Swords as base (but gold-tinted)
- Add crossed swords icon above the text

**Acceptance**: Battle button is the first thing eyes go to. Yellow dominates. Feels urgent.

#### ITERATION M2: Color Hierarchy
**Problem**: Everything is brown/dark wood tones. No visual priority system.

**Fix**:
- **Yellow/Gold**: BATTLE button, gold amounts, premium indicators
- **Green**: "Play Online", positive actions, faction selection confirm
- **Red**: Horde faction accent, notifications, alerts
- **Blue**: Kingdom faction accent, informational, background
- **Dark brown**: Tab bar, panels, secondary UI — remains as canvas
- Tab bar selected state: Use YELLOW highlight (not blue) for the active tab

**Acceptance**: Screenshot the menu — can you tell what the #1 action is within 1 second? If yes, hierarchy works.

#### ITERATION M3: Home Screen Progression Display
**Problem**: Only shows "New Commander" or trophy count. No sense of journey.

**Fix**:
- **Arena Banner**: Named arena based on trophies (Wooden Arena → Stone Arena → Iron Arena → Gold Arena → Legend Arena)
  - Visual: Banner texture from Tiny Swords changes color per arena
  - Position: Below header, above faction selection
- **Trophy Progress Bar**: Horizontal bar showing progress to next arena
  - Example: "Stone Arena — 142/300 trophies"
- **Card Deck Preview**: Show 3-4 building cards from selected faction on home screen
  - Miniature versions, tap to see full info
  - Shows what you'll fight with
- **Win Streak**: If on a streak, show flame icon + "3 Win Streak!"
- **Faction Mastery**: Show mastery level badge next to faction button

**Acceptance**: Home screen communicates: where you are, where you're going, what you're fighting with.

#### ITERATION M4: Smooth Tab Transitions
**Problem**: Tabs instantly show/hide panels. Feels like 2005 web design.

**Fix**:
- Panel slide: New panel slides in from right (0.2s), old panel slides out left
- Or: Fade transition (0.15s cross-fade)
- Tab icon: Animate selected tab (slight bounce/grow on select, 0.1s)
- Content: Stagger child elements appearing (each element 0.05s delay)

**Acceptance**: No instant panel swaps. Every screen change feels animated.

#### ITERATION M5: End Screen Overhaul
**Problem**: End screen shows basic stats. Doesn't celebrate victory or motivate retry.

**Fix** (Clash Royale post-match):
- **Victory**: Big animated banner with confetti particles, trophy gain animation (+30 counting up)
- **Defeat**: Subdued but not punishing. "Almost!" messaging. Trophy loss shown gently.
- **Stats cards**: Flip-reveal animation for each stat (units killed, buildings placed, MVP unit, gold earned)
- **MVP Unit**: Spotlight the unit type that dealt the most damage with sprite + name
- **"Play Again" button**: Yellow, prominent, center. Not just "Restart."
- **Trophy animation**: Current → New trophy count with filling bar
- **First Win Bonus**: Special glow if daily bonus earned

**Acceptance**: Victory feels EARNED. Defeat makes you want to retry. Stats are interesting to read.

---

## SECTION 3: STRATEGIC DEPTH — Us vs Castle Fight

### What Castle Fight Has That We're Missing

| Feature | Castle Fight | Our Game | Priority | Feasible Now? |
|---------|-------------|----------|----------|--------------|
| **12+ races** | 12-14 completely distinct races | 2 factions (Kingdom, Horde) | Low now | No — need more art |
| **Special buildings w/ active spells** | Buildings with mana bars that cast spells | No active abilities during match | HIGH | Yes |
| **Compound income (Treasure Box)** | Income buildings that boost income % | Flat +3g/tick from Gold Mine | HIGH | Yes |
| **Building upgrade paths** | T1→T2→T3 buildings | T1 and T2 exist but no upgrade-in-place | MEDIUM | Yes |
| **Draft mode** | Pick buildings from random packs | All buildings always available | MEDIUM | Yes |
| **Perk system** | Pre-game perk with upside+downside | Nothing | MEDIUM | Yes |
| **Secondary resource (lumber)** | Forces resource allocation | Only gold | LOW | Maybe later |
| **Game mode variants** | 6+ modes (Unique Races, Domination, etc.) | One mode only | MEDIUM | Yes (simple) |
| **Team play (2v2, 3v3)** | Core experience is team-based | 1v1 only | LOW now | Needs multiplayer |
| **Farming/Boxing strategy** | Trap enemy units to control flow | Anti-block prevents full blocking | LOW | Partial via maze |

### Features We CAN Add With Current 2 Factions (No New Art Needed)

#### STRATEGY S1: Special Buildings with Active Abilities (HIGH PRIORITY)
**Castle Fight's unique hook**: Special buildings have mana bars and cast spells. You time when to activate them.

**Our version** — 1 special building per faction:
- **Kingdom: War Horn** (100g) — Active ability: "Rally Cry" — When activated, ALL Kingdom units get +30% movement speed for 10 seconds. 60-second cooldown. Mana bar fills over time.
- **Horde: Blood Totem** (100g) — Active ability: "Blood Rage" — When activated, ALL Horde units get +25% attack damage for 8 seconds but take 10% more damage. 60-second cooldown.

**UI**: Special building shows a glowing button on the HUD when ability is ready. Player taps to activate. This is the ONLY direct player interaction during battle (besides building).

**Why this matters**: Adds timing decisions. "Do I pop Rally Cry now to push, or save it for the next wave?" This is the Castle Fight strategic depth in a single mechanic.

#### STRATEGY S2: Compound Income Building (HIGH PRIORITY)
**Castle Fight's Treasure Box**: Income buildings that boost your income by a percentage, not a flat amount.

**Our version** — Upgrade the existing Gold Mine / Plunder Camp:
- **Current**: Gold Mine gives +3g/tick (flat)
- **New**: Gold Mine gives +15% income bonus (multiplicative). Base income = 20g/5s. One Gold Mine = 23g/5s. Two = 26.5g/5s. Three = 30.4g/5s.
- **Cost increase**: First Gold Mine 80g, second 120g, third 180g (diminishing returns on investment)

**Why this matters**: Creates the core Castle Fight dilemma: "Do I invest in economy now (Gold Mine) or army now (Barracks)?" Early Gold Mine = weaker army but snowball economy. Late Gold Mine = wasted potential.

#### STRATEGY S3: Pre-Game Perk Selection (MEDIUM PRIORITY)
**Castle Fight Definitive Edition's perk system**: Pick one perk before the match. Each has an upside AND a downside.

**Our version** — 3 perks per faction to choose from:
- **Kingdom Perks**:
  1. *Iron Discipline*: +10% unit HP, -10% unit damage
  2. *Swift March*: +15% move speed, -1 armor to all units
  3. *War Economy*: +25% starting income, first building costs 50% more
- **Horde Perks**:
  1. *Bloodthirst*: +10% damage, units take 5% max HP bleed per 10s
  2. *Savage Rush*: First 3 units spawn instantly, income -15%
  3. *Pillage*: Kill bounty +50%, income buildings cost 40% more

**UI**: After faction selection, before match starts, a perk selection screen shows 3 options with descriptions. Pick one. Can pick "No Perk" for default.

**Why this matters**: Adds pre-game strategic decision. Creates build diversity — same faction plays differently with different perks.

#### STRATEGY S4: Game Mode Variants (MEDIUM PRIORITY)
Simple variants that use existing mechanics:

1. **Blitz Mode**: Double income, double spawn speed. Matches last 2 minutes instead of 5.
2. **Tower Defense**: No spawner buildings allowed. Only towers + walls. Survive AI waves.
3. **No Walls**: Wall/Palisade buildings disabled. Pure army composition strategy.
4. **Mirror Match**: Both players use same faction. Pure skill test.

**UI**: Mode selector on battle tab (horizontal scroll of mode cards).

#### STRATEGY S5: Building Upgrade In-Place (MEDIUM PRIORITY)
**Problem**: Currently you build separate T2 buildings. Can't upgrade existing ones.

**Fix**: Tap existing T1 spawner building → radial menu shows "Upgrade" option if you have the gold and prerequisite. Building upgrades in-place to T2 version.
- Barracks (50g) → Knight Hall (70g upgrade, total 120g)
- War Camp (45g) → Berserker Pit (65g upgrade, total 110g)
- Visual: Building sprite changes, brief construction dust animation

**Why this matters**: Saves grid space. Creates decisions about WHEN to upgrade vs build new. Matches Castle Fight's tech-up timing.

#### STRATEGY S6: Wave Preview + Send Early (SMALL BUT IMPACTFUL)
**Kingdom Rush's best mechanic**: See what's coming, option to trigger early for bonus.

**Our version**:
- 5s before each wave, show unit count/type preview at top of combat lane
- "Send Now" button appears — tap to trigger wave early
- Bonus: +10g per second remaining on timer (max +50g if sent 5s early)
- Risk: Your units might not be ready if you upgraded recently

---

## SECTION 4: LOGO & BRANDING

### Logo Creation Task (A2)

**Requirements**:
1. **Style**: Match Tiny Swords pixel art. Hand-painted feel with clean edges.
2. **Composition options**:
   - Option A: Two opposing castle towers with crossed swords between them
   - Option B: Shield emblem with castle battlements on top, faction colors split down middle
   - Option C: Single imposing keep/rampart with banner flowing from it
3. **Color palette**: 
   - Primary: Gold RGB(1.0, 0.85, 0.3) + Dark brown RGB(0.2, 0.12, 0.05)
   - Faction accents: Blue RGB(0.3, 0.6, 1.0) vs Red RGB(1.0, 0.35, 0.3)
4. **Sizes needed**: 512x512 (app icon), 256x256 (splash), 128x128 (in-game), 32x32 (favicon)
5. **Text treatment**: Game name below or integrated into the emblem. Bold, medieval-styled but READABLE font.
6. **Constraint**: Must work as square app icon (no text required at 32x32 — icon alone should be recognizable)

### Name Change Propagation
Once name is decided, update in:
- `project.godot` — config/name
- Loading screen title text
- Main menu title text
- End screen header
- Any "Castle Clash" text strings in code

---

## SECTION 5: PRIORITIZED ITERATION PLAN

### Wave 1: Foundation Polish (Do FIRST — biggest visual impact)
| # | Task | Agent | Impact | Effort |
|---|------|-------|--------|--------|
| 1 | **Decide game name** | User + A0 | Critical | Decision |
| 2 | **Terrain texture upgrade** (B1) | A2 | Huge | Medium |
| 3 | **Battle button redesign** (M1) | A2 | Huge | Small |
| 4 | **Color hierarchy** (M2) | A2 | High | Small |
| 5 | **Visual hierarchy — mute bg** (B2) | A2 | High | Small |

### Wave 2: Feel & Juice (Makes the game feel "real")
| # | Task | Agent | Impact | Effort |
|---|------|-------|--------|--------|
| 6 | **Particle effects** (B5) | A2 | High | Medium |
| 7 | **Idle world animation** (B6) | A2 | Medium | Small |
| 8 | **Smooth tab transitions** (M4) | A2 | Medium | Small |
| 9 | **Gold bar redesign** (B7) | A2 | Medium | Small |
| 10 | **End screen overhaul** (M5) | A2 | High | Medium |

### Wave 3: Strategic Depth (Makes the game DEEP)
| # | Task | Agent | Impact | Effort |
|---|------|-------|--------|--------|
| 11 | **Special buildings w/ active abilities** (S1) | A1 | High | Medium |
| 12 | **Compound income** (S2) | A1 | High | Small |
| 13 | **Wave preview + send early** (S6) | A1+A2 | High | Small |
| 14 | **Building radial menu** (B4) | A2 | High | Medium |
| 15 | **Home screen progression** (M3) | A2 | High | Medium |

### Wave 4: Replayability & Depth
| # | Task | Agent | Impact | Effort |
|---|------|-------|--------|--------|
| 16 | **Pre-game perk selection** (S3) | A1+A2 | Medium | Medium |
| 17 | **Game mode variants** (S4) | A1+A2 | Medium | Small |
| 18 | **Building upgrade in-place** (S5) | A1+A2 | Medium | Medium |
| 19 | **Logo creation** | A2 | Critical | Medium |
| 20 | **Name change propagation** | A2 | Critical | Small |

---

## WHAT TO DEPRIORITIZE (from old dispatch.md)

The following tasks from the old Phase 2 plan should be DEPRIORITIZED in favor of the iterations above:
- T-007/T-008 (sprite HP bars) — nice-to-have, not a gap vs benchmarks
- T-009 (button textures) — folded into M1/M2 color hierarchy work
- T-016 (shop tab) — premature, no reward economy yet
- T-019-T-026 (second skills) — defer until after strategic depth features (S1-S6) which are higher impact

**Rationale**: Second skills add depth to combat, but special buildings with active abilities (S1), compound income (S2), and perks (S3) add depth to STRATEGY — which is what Castle Fight is actually about. Combat depth is secondary to macro strategy.
