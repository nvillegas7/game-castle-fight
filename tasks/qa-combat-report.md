# QA Combat Analysis Report — AI-vs-AI Test
> **Test**: 60 seconds of Kingdom vs Horde, both sides auto-building
> **Result**: 20 units, 10 buildings, 0 castle damage at tick 585

---

## GAMEPLAY ISSUES (For Game Designer + Mechanics Agent)

### 1. Units Target Buildings Instead of Nearby Enemy Troops [DESIGN ISSUE]
- **Observation**: Grunt #29 at (430, 722) bypassed enemy footmen to attack player Barracks #25
- **Root cause**: `_acquire_target()` treats units and buildings equally — picks NEAREST target regardless of type
- **Impact**: Troops walk past enemies to attack buildings, feels wrong to players
- **Recommendation**: Add targeting priority — units should prefer enemy troops over buildings unless no troops are in aggro range. Siege units (role=4) should be the exception — they prefer buildings.

### 2. Multiple Units Targeting Same Nearly-Dead Enemy [WASTE]
- **Observation**: Footman #28 has 7 HP but 4 grunts (#26, #32, #33, #35) are all targeting it
- **Impact**: 3 grunts waste their time walking to a target that will die from 1 hit
- **Recommendation**: Add target spreading — when acquiring targets, prefer enemies that aren't already targeted by 2+ allies. Or re-evaluate targets when current target dies.

### 3. No Castle Damage After 60 Seconds [PACING]
- **Observation**: Both castles at 10000 HP after 585 ticks
- **Impact**: Matches may feel too slow. In Kingdom Rush, the action escalates quickly.
- **Recommendation**: Consider lower castle HP, faster unit spawn rates, or earlier T2 unit availability. Starting gold=0 means first building at ~10 seconds, first units at ~30 seconds. Combat doesn't really start until 40+ seconds.

### 4. Archer Positioning is Correct [WORKING]
- Archer #22 at y=678 correctly stays back and shoots at grunt at y=591 (87px, within 112px range)
- Archer #31 at y=695 shooting grunt at y=722 (109px, within range)
- Ranged units maintain proper distance

### 5. Melee Engagement is Correct [WORKING]
- Footman #13 at (370,604) targeting grunt #24 at (374,577) = 27px away — within 28px range
- Melee units properly walk close before attacking (2D distance fix confirmed)

---

## UI/UX ISSUES (For Visual Agent)

### From Frame Analysis (30 frames captured):

### 6. Units Clump Together in Combat [VISUAL]
- When multiple units fight, they stack on the same position creating an unreadable blob
- **Recommendation**: Increase unit separation distance or add slight position offsets during combat

### 7. Player's Archer Range Building Has Damage (HP=464/500) [BUG?]
- The archer_range building lost 36 HP despite no visible attackers reaching it
- **Possible cause**: A grunt (#29) targeted and reached the build zone
- **Verify**: Is building combat working correctly? Buildings should be destroyable but units should prefer enemy troops.

### 8. Card Hand Fits 8 Buildings [FIXED]
- Reduced CARD_W from 92→84 and CARD_GAP from 5→4 = 707px total
- All 8 buildings (including new Wall) visible

### 9. HUD Text Readable [WORKING]
- "Gold: 10 Time 0:58" and "HP 10000 | Foe 10000" clearly visible at 18/16px font sizes

### 10. Trees and Terrain Decorations Rendering [WORKING]
- Multiple pine trees visible on both sides
- Bushes along zone edges
- Rocks in combat lane
- Grass texture variation patches visible

### 11. Water Borders Muted [WORKING]
- Dark teal color, no longer jarring bright cyan

---

## RECOMMENDED PRIORITIES

**For Mechanics Agent:**
1. Add unit-targeting priority (units > buildings for non-siege)
2. Add target spreading (max 2 attackers per target)
3. Review match pacing (first combat too slow?)

**For Visual Agent:**
1. Increase unit separation push distance for clearer combat visuals
2. Add HP bars above units (currently hard to see unit health in combat)
3. Consider unit outlines or team-colored glow for better identification

**For Game Designer:**
1. Review starting economy (0g + 20 income = slow start)
2. Consider faster first income tick or starting gold
3. Review wall/palisade building balance (15g, 1x1, no units — is it useful?)
