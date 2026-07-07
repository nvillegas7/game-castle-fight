# QA Balance Report — T-025
> **Test Date**: 2026-04-07 | **Agent**: A4 (QA Engineer)
> **Framework**: `tests/test_balance.gd` — 100 headless AI-vs-AI matches

---

## Results

| Metric | Value |
|--------|-------|
| Kingdom wins | 100 (100%) |
| Horde wins | 0 (0%) |
| Draws | 0 |
| Crashes | 0 |
| Avg match length | 1878 ticks (188s / 3.1 min) |
| Median match length | 1849 ticks (185s / 3.1 min) |
| Shortest match | 1728 ticks (173s / 2.9 min) |
| Longest match | 2167 ticks (217s / 3.6 min) |

**Verdict: FAIL** — Kingdom wins 100% of matches. Target is 45-55%.

---

## Analysis

### Match Length: GOOD
- Average 3.1 minutes is within the 2-5 minute target
- Tight spread (2.9 - 3.6 min) shows consistent pacing
- No timeouts (all matches end decisively)

### Faction Balance: CRITICAL IMBALANCE
Kingdom dominates with 100% win rate across 100 random seeds. Potential causes:

1. **Priest Healing**: Priest Temple's Holy Light AoE heal may sustain Kingdom army much longer than Horde equivalents. War Drums (+attack speed aura) doesn't compensate for incoming damage.

2. **Knight Charge**: Knight's charge skill gives massive first-hit burst + 2x speed. Berserker's Evasion (15% dodge) is less impactful when facing multiple hitters.

3. **Guard Tower vs Flame Tower**: Guard Tower (Pierce, range 5, dmg 10) may outperform Flame Tower (Magic, range 4, dmg 8) in this test's build order.

4. **Build Order Sensitivity**: Both sides follow a fixed build order. The test doesn't account for counter-picking. Real AI uses counter-play which may produce different results.

### Recommendations for A1 (Game Developer)

1. **Buff Horde healing**: Consider adding a Horde building with HP regen or lifesteal mechanic
2. **Review War Drums aura**: The +20% attack speed aura may need a wider range or stronger bonus
3. **Review Berserker stats**: Berserker may need more HP or a stronger Evasion proc rate
4. **Run with counter-play AI**: The balance test uses fixed build orders — consider adding adaptive AI strategies to the test for more realistic results

---

## Test Methodology

- 100 matches with seeds 12345-12444
- Fixed build order for both factions (no counter-play)
- Kingdom: barracks → archer_range → gold_mine → barracks → priest_temple → guard_tower → knight_hall → siege_workshop → armory → war_horn
- Horde: war_camp → axe_range → plunder_camp → war_camp → war_drums → flame_tower → berserker_pit → demolisher_works → blood_altar → blood_totem
- Buildings placed every 30 ticks (3s) when gold available
- Match timeout: 6000 ticks (10 min)
- Starting gold: 0 for both
