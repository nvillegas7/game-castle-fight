# Castle Clash: Game Design Document

> A Castle Fight-inspired team-based auto-battler with chibi art, built for web + mobile.

---

## 1. Game Overview

### Elevator Pitch
**Castle Clash** is a team-based multiplayer auto-battler where players place buildings that automatically spawn chibi units to fight the enemy team. Destroy the enemy castle to win. Simple to play, deep to master.

### Core Identity
- **Genre**: Auto-battler / Tower Defense hybrid (inspired by WC3 Castle Fight)
- **Art Style**: Chibi / Cartoonish 2D (low GPU requirements)
- **Platform**: Web-first (Godot 4 + HTML5), then mobile (Android/iOS)
- **Match Length**: 8-15 minutes
- **Team Size**: 2v2 (core), 3v3 (standard), 1v1 (ranked)
- **Monetization**: F2P with Battle Pass + Cosmetics + Rewarded Ads

---

## 2. Core Game Mechanics (From Castle Fight)

### The Loop
```
Choose Faction -> Earn Income -> Place Buildings -> Units Auto-Spawn ->
Units Auto-Fight -> Waves Clash -> Survivors Push -> Damage Castle -> Repeat
```

### Key Mechanics

| Mechanic | Description |
|----------|-------------|
| **Building Placement** | Grid-based, in your team's zone only. Space is limited -- strategic placement matters. |
| **Synchronized Waves** | All buildings spawn units at the same time (~25s intervals). Creates clear wave-vs-wave combat. |
| **Auto-Combat** | Zero unit control. Units march, engage nearest enemy, auto-cast abilities. |
| **Single Resource (Gold)** | Passive income ticks every few seconds. Spent on buildings and upgrades. |
| **Scouting** | Enemy buildings are visible. Read their composition, counter it. |
| **Shared Castle** | One castle per team (~10,000 HP). If it falls, everyone loses. |
| **Survivors Carry Over** | Units that win a wave keep marching toward the enemy castle. Snowball effect. |

### Building Tiers

| Tier | Cost Range | Unlock | Examples |
|------|-----------|--------|----------|
| T1 | 30-80 gold | Immediate | Basic barracks, archer range |
| T2 | 80-150 gold | Requires T1 tech building | Knight hall, mage tower |
| T3 | 150-300 gold | Requires T2 tech building | Siege workshop, dragon roost |
| T4 (Ultimate) | 300-600 gold | Requires T3 tech, limit 1 | Hero summon portal |

### Unit Roles

| Role | Function | Counter |
|------|----------|---------|
| **Melee Tank** | High HP, soak damage frontline | AoE, magic damage |
| **Ranged DPS** | Moderate HP, damage from distance | Rush melee, flanking |
| **Caster/Support** | Heals, buffs, debuffs, AoE | Magic-immune units, burst |
| **Flying** | Ignores ground pathing | Anti-air units |
| **Siege** | High building damage, needed to finish castle | Everything (they're fragile) |
| **Elite/Hero** | Powerful single unit with abilities | Swarming, counter-abilities |

### Damage Type Matrix (Simplified for clarity)
```
Attack vs Armor:  Light   Medium  Heavy   Fortified
Physical:         100%    100%    75%     50%
Pierce:           150%    75%     100%    50%
Magic:            125%    75%     100%    100%
Siege:            50%     50%     50%     150%
```
*Displayed with clear color-coded icons in-game so players learn the system visually.*

### Factions (4 at launch, expandable)

**1. The Kingdom (Balanced)**
- Strong healing + armor. Sustain-oriented.
- Priests keep units alive longer, multiplying value.
- Good for beginners.

**2. The Horde (Aggressive)**
- High damage, powerful buffs (Warcry).
- Snowball strategy -- win waves decisively.
- Rewards aggressive play.

**3. The Undead (Attrition)**
- Necromancers raise skeletons from corpses.
- Weak individually, overwhelming in long fights.
- High skill ceiling.

**4. The Wilds (Ranged/Mobile)**
- Excellent archers, nature magic, flying units.
- Dryads are magic-immune (counter caster comps).
- Punishes slow, melee-heavy opponents.

---

## 3. Modern Improvements Over Castle Fight

| Original Problem | Our Solution |
|------------------|-------------|
| Opaque damage matrix | Color-coded visual indicators, tooltip system, "effective/ineffective" markers |
| No active abilities | 1-2 timed abilities per match (faction-specific ultimate, targeted spell) |
| Single passive income | Income buildings + kill bounties + risk/reward gambles |
| Space management unclear | Visual grid with adjacency bonuses shown before placement |
| No progression between matches | Ranked seasons, battle pass, unlockable cosmetics |
| Stalemates | Escalating income + damage over time after 15 min mark |
| No comeback when far behind | "Last Stand" mechanic: castle gains temporary shield when below 25% HP |

---

## 4. Multiplayer Architecture

### Networking Model: Relay + Deterministic Lockstep

```
Player A (Mobile/Web)  --|
Player B (Mobile/Web)  --|--> Relay Server (Nakama) --> Broadcasts to all
Player C (Mobile/Web)  --|
Player D (Mobile/Web)  --|

Each client runs identical deterministic simulation locally.
Server only relays commands, not game state.
```

**Why this model:**
- 10-30x cheaper than authoritative servers
- Perfect for auto-battlers (low input rate, deterministic AI)
- A $20/month VPS handles 1,000+ concurrent users

### Technical Requirements for Deterministic Lockstep
- Fixed-point math (no floating point for game logic)
- Seeded deterministic RNG
- Ordered entity processing (sorted IDs, not hash maps)
- Fixed timestep simulation (independent of frame rate)
- Periodic checksum sync to detect desync

### Backend Stack

| Component | Solution | Cost |
|-----------|----------|------|
| Game relay + matchmaking | Nakama (self-hosted, open source) | $20/mo VPS |
| Player accounts | Nakama built-in | Included |
| Leaderboards | Nakama built-in | Included |
| Database | PostgreSQL (Nakama's default) | Included in VPS |
| Web hosting | Cloudflare Pages (free) | $0 |
| CDN / Assets | Cloudflare (free tier) | $0 |
| Analytics | PostHog (free tier) or Amplitude | $0 |
| Push notifications | Firebase Cloud Messaging | $0 |
| Payment processing | Stripe (web) / Platform IAP (mobile) | 3% / 15-30% |

### Server Cost Projections

| Scale (CCU) | Monthly Cost | Expected Revenue |
|-------------|-------------|-----------------|
| 100 (dev/test) | $10-20 | $0 |
| 1,000 | $20-50 | $3-8K |
| 10,000 | $100-300 | $30-80K |
| 100,000 | $600-1,500 | $150-400K |

---

## 5. Platform Strategy

### Phase 1: Web MVP (Months 1-4)
- **Engine**: Godot 4 (GDScript)
- **Target**: itch.io, own domain
- **Why web first**: Zero friction (share a link), instant updates, no app store fees, validate gameplay

### Phase 2: Web Distribution (Months 4-7)
- Submit to CrazyGames, Poki (millions of monthly players)
- Add battle pass + cosmetic shop (Stripe payments, keep 97%)
- Add rewarded ads (web ad SDK)

### Phase 3: Mobile (Months 7-10)
- Export Godot project to Android + iOS
- Integrate mobile ad SDKs (AdMob)
- Integrate mobile IAP (Google Play Billing, Apple StoreKit)
- Cross-play between web and mobile (same Nakama backend)

### Why Godot 4
| Advantage | Detail |
|-----------|--------|
| Cost | $0 forever. MIT license. No royalties. |
| Web export | Best in class. 5-15MB builds, fast loading. |
| 2D engine | Purpose-built for 2D. Not a 3D engine with 2D bolted on. |
| Learning curve | GDScript is Python-like. 1-2 weeks to be productive. |
| Mobile export | Native Android + iOS from same codebase. |
| Open source | No licensing surprises (unlike Unity's 2023 debacle). |

---

## 6. Monetization Strategy

### Revenue Stack (Priority Order)

| Stream | % of Revenue | Implementation |
|--------|-------------|----------------|
| Season/Battle Pass ($4.99, 8-week cycles) | 30-40% | Free + Premium tracks with cosmetics |
| Direct cosmetic purchases | 20-30% | Building skins, unit skins, effects, emotes |
| Rewarded ads (F2P players only) | 20-30% | "Double rewards" after match, free daily chest |
| Starter/value packs (one-time) | 5-10% | $1.99 incredible-value first purchase |
| Premium currency (convenience only) | 10-15% | Extra deck slots, profile customization |

### What We Sell (Cosmetics Only -- Never Power)
- Building skins ("Dark Fortress" barracks, "Crystal Spire" mage tower)
- Army themes (all units get visual variant)
- Spawn effects (particles when building produces unit)
- Victory/defeat animations
- Board/terrain themes
- Emotes and taunts ($1-3, high volume)
- Profile frames, banners, titles

### Revenue Projections (Conservative)

| Downloads | Est. DAU | Monthly Revenue |
|-----------|----------|----------------|
| 10K | 1-2K | $500-$3K |
| 50K | 5-10K | $3K-$15K |
| 100K | 10-20K | $8K-$40K |
| 500K | 30-75K | $30K-$150K |
| 1M | 50-150K | $75K-$400K |

### Retention Targets

| Metric | Target | Action if Below |
|--------|--------|----------------|
| D1 Retention | >40% | Fix onboarding/tutorial |
| D7 Retention | >20% | Add daily engagement hooks |
| D30 Retention | >10% | Strengthen clan/social systems |
| Payer Conversion | >5% | Improve battle pass value perception |

### Retention Mechanics
- Daily quests (3/day, battle pass XP + small currency)
- First win of the day bonus (2-3x rewards)
- Weekly clan wars
- Ranked seasons (6-8 weeks, rewards at season end)
- New content each season (1-2 buildings/units, new faction every 2-3 seasons)

---

## 7. Budget Estimate (To Web MVP)

| Item | Cost |
|------|------|
| Godot Engine | $0 |
| Art assets (chibi packs) | $500-$2,000 |
| Sound effects + music | $100-$500 |
| Server (Nakama on VPS) | $20/month |
| Domain + Cloudflare | $15/month |
| **Total to launch web MVP** | **~$1,000-$3,000** |

Later costs:
- Custom chibi art: $2,000-$5,000
- Apple Developer Account: $99/year
- Google Play Developer: $25 one-time
- Mobile ad SDK integration: Engineering time only

---

## 8. Competitive Landscape

| Game | Similarity | Our Differentiation |
|------|-----------|---------------------|
| Legion TD 2 | Closest comp (WC3 mod successor) | Mobile-first, cuter art, shorter matches |
| TFT / Auto Chess | Auto-battler genre | Team-based, building placement, shared castle |
| Clash Royale | Real-time PvP, units | No direct control (auto-battler), team-based |
| Minion Masters | Lane-based auto-battler | Multi-player teams, building placement focus |

### Our Unique Position
Castle Fight's core loop (team building placement + auto-combat) has **no direct mobile competitor**. Legion TD 2 is PC-only. We fill a genuine gap.
