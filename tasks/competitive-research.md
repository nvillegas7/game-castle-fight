# Competitive Research Report
> Generated 2026-04-05 for Castle Fight-inspired mobile auto-battler

---

## 1. Kingdom Rush -- Battle Screen UI/UX

Kingdom Rush (by Ironhide Game Studio) is the gold standard for tower defense UI on mobile. Here is a detailed breakdown of what makes it work.

### What Is On Screen During Gameplay

- **Fixed tower slots**: Unlike most TD games, Kingdom Rush restricts building to pre-determined spots marked by blank circles near the road. Some slots require clearing debris (extra gold cost). This constraint simplifies decision-making and keeps the battlefield readable.
- **Enemy path**: Clearly defined roads through hand-painted terrain. Enemies follow fixed routes, making it easy for players to predict flow.
- **Lives counter**: Players start with 20 lives (citizens). Lives lost when enemies reach the exit. Star rating: 18-20 lives = 3 stars, 6-17 = 2 stars, 1-5 = 1 star.
- **Gold display**: Top of screen. Gold earned from kills, used for building and upgrades within a level.
- **Wave info (Skull Circle)**: A skull icon on screen serves dual purpose -- tap once to preview what enemies are coming next, tap twice to send the wave early. Sending early grants bonus gold equal to seconds remaining + faster spell recharge. This is a brilliant risk/reward mechanic.
- **Hero abilities**: Placed on the bottom-left of the screen, always accessible.

### Bottom Toolbar / Tower Selection / Upgrade UI

- **Radial context menu**: When you tap a tower slot, options appear in a **circle around the selected spot**, growing outward with animation. This is key -- the UI is attached to the object, not a separate panel.
- **Tower upgrade path**: Once a tower is placed, tapping it shows upgrade options in the same radial menu. A quick description of major upgrades appears to the side, which becomes critical as the game deepens.
- **No permanent bottom toolbar**: The toolbar is the map itself. This maximizes screen real estate.

### Unit Health / Status

- **Health bars**: Small bars above units/heroes. Heroes additionally show level + experience bar.
- **Status indicators**: Visual auras for buff/debuff states (e.g., red aura on enemies buffed by Chieftains).
- **Minimal text**: Relies on visual language, not numbers.

### What Makes It Feel Premium

- **Hand-drawn art style**: Cell-shaded, cartoon aesthetic with a mid-90s Warcraft vibe. No pure blacks -- colors are slightly muted with a touch of grey in the gamma.
- **Light/shadow technique**: Basic shadows without gradients, simulating volume using 3+ tones of the same color. Carefully placed shapes for textures (spikes for grass, broad grey with notches for steel).
- **Smooth animations**: No lag or stuttering even during heavy waves. Smooth tower attack animations, projectile trails, death effects.
- **Environmental detail**: Lush hand-painted backgrounds with decorative elements that make each map feel alive.
- **Particle effects on towers**: Advanced upgrades add visual flair (e.g., leaf emitters on Ranger's Hideout).
- **Juice on interactions**: Tower menus grow outward with animation. Satisfying visual feedback on every tap.

### Color Palette and Visual Hierarchy

- **Muted earth tones** for terrain (greens, browns, greys) so units and UI pop.
- **Bright accents** for interactive elements and important UI (gold, abilities).
- **No pure blacks**: Everything has warmth, preventing harsh visual contrast.
- **Legible fonts**: At-a-glance readability, avoids cursive during gameplay. Decorative fonts reserved for menus/titles only.
- **Circular button design**: Perfect for thumbs on mobile -- not too small, highly tappable.

### Key Takeaways for Our Game

1. **Attach UI to game objects** (radial menus on buildings, not bottom panels) -- saves screen space.
2. **Preview incoming threats** -- a wave preview mechanic adds tactical depth.
3. **Muted backgrounds, bright interactables** -- clear visual hierarchy.
4. **Hand-drawn feel** matters more than polygon count on mobile.
5. **Smooth animation on every interaction** is what separates premium from placeholder.

**Sources:**
- [Kingdom Rush UI Analysis -- Emily Miles](https://emilym.space/thumbelina-hurts-mobile-ui-blog/2018/6/26/kingdom-rush-a-tower-defense-trilogy-with-ui-design-approaching-perfection-and-entertainment-worth-missing-bedtime-for)
- [UI Analysis of Tower Defence Games -- Josh Bauer](https://joshbauer94.wordpress.com/2014/11/08/user-interface-analysis-of-tower-defence-games/)
- [Kingdom Rush Color Scheme -- SchemeColor](https://www.schemecolor.com/kingdom-rush-frontiers.php)
- [Kingdom Rush Art Style -- Ironhide Forums](https://forums.ironhidegames.com/viewtopic.php?f=5&t=158)
- [Kingdom Rush Campaign Design -- Game Developer](https://www.gamedeveloper.com/design/kingdom-rush---the-wonderful-campaign-level-design)
- [Kingdom Rush on Steam](https://store.steampowered.com/app/246420/Kingdom_Rush___Tower_Defense/)
- [Kingdom Rush Wiki](https://kingdomrushtd.fandom.com/wiki/Kingdom_Rush)

---

## 2. Clash Royale -- Menu Screen UI/UX

Clash Royale (by Supercell) is the benchmark for mobile competitive game menus. Every element is intentionally designed for thumb reach, visual clarity, and emotional engagement.

### Main Screen Layout

- **Battle button**: CENTER of the screen, large and yellow (the highest-priority color). Impossible to miss. This is the single most important action and it dominates visual weight.
- **Card deck**: Displayed below the battle button area. Your active 8-card deck is always visible on the home screen.
- **Trophy count**: Displayed prominently, shows your rank/progression at a glance.
- **Chest slots**: 4 chest slots visible on the main screen. After winning, chests fill these slots. They unlock on timers, creating anticipation loops and return visits.
- **Arena banner**: The current arena (league) is displayed as a decorative banner, giving a sense of place and progression.
- **Player info**: Name, level, clan badge in the top area.

### Tab Bar Structure

- **Bottom navigation bar**: Shortcuts for switching between screens. One tap to reach any section.
- **Social Tab** (recent addition): Centralizes chat, friendly battles, and friends list in one place.
- **Cards Tab**: Browse your collection, upgrade cards with gold, request from clan.
- **Shop Tab**: Daily deals, gem purchases, special offers.
- **Game Mode Switcher**: To the right of the Battle button. Lets you switch between Trophy Road, Challenges, Events, and special modes without navigating away.

### Progression Visualization

- **Trophy Road**: Linear progression path stretching to 12,000 trophies across 28 arenas. Each milestone unlocks rewards (gold, gems, cards, chests, cosmetics). Visual representation of "where you are" vs "where you're going."
- **Arena system**: Named arenas with unique visual themes. Reaching a new arena feels like a genuine milestone.
- **Card levels**: Each card shows its level and upgrade progress. When you have enough cards + gold to upgrade, a green highlight appears.
- **Chest unlock timers**: Create a "I need to come back" loop.

### Color Scheme and Visual Weight

- **Yellow** = Primary CTA (Enter Battle, Request Cards, Use Card, Invite Friend). These buttons often have animated highlight effects.
- **Green** = Secondary actions (Donate, Buy, Upgrade Card). Indicates "positive action available."
- **Red** = Notifications, alerts, urgent attention needed.
- **Blue** = Background color, less important UI elements. The dominant canvas color that lets everything else pop.
- **Gold/Orange** = Premium currency and special offers.

### What Makes the Menu Feel Polished (vs. Placeholder)

1. **Objects as buttons**: Rather than labeled buttons, interactive items ARE the buttons. Tapping a chest opens it. Tapping a card shows its info. The UI assumes player intelligence.
2. **One-handed reach**: ALL key elements are within the lower 50% of the screen, reachable with one thumb while holding the phone.
3. **One tap to anything**: Every section is one tap away from every other section. No deep navigation hierarchies.
4. **Reward anticipation everywhere**: Chest timers, upgrade availability indicators, daily deals with countdown timers. The menu itself is a game.
5. **Clean information density**: Lots of data (trophies, card levels, gold, gems, clan info, chests) but never feels cluttered because of strict visual hierarchy.
6. **Smooth transitions**: Every screen change is animated, not a hard cut.
7. **Social proof**: Clan activity, friend battles, leaderboards are surfaced in the main flow.

### Key Takeaways for Our Game

1. **Battle button must be unmissable** -- center screen, highest visual weight.
2. **Use color hierarchy religiously**: Yellow = do this now, Green = do this when ready, Red = look here, Blue = background.
3. **Show progression on the home screen** -- trophy count, arena banner, upgrade availability.
4. **Chest/reward slots create return visits** -- even a simple "you earned this, come back to open it" works.
5. **Every section one tap away** -- flat navigation, not nested menus.
6. **One-handed, lower-screen interaction** for mobile.

**Sources:**
- [UX in Clash Royale -- The Rookies](https://discover.therookies.co/2020/02/24/game-design-ux-best-practices-detailed-breakdown-of-clash-royale/)
- [Clash Royale UI Lessons -- Techi](https://www.techi.com/clash-royale-ui-lessons-online-casino-app-design/)
- [Clash Royale UX -- Karim Muhtar](https://karimmuhtar.com/ux-design/clash-royale/)
- [Clash Royale UX -- Maciej Gornicki](https://www.gornicki.me/blog/90l/ux-in-clash-royale-part-1)
- [Clash Royale UI -- Interface In Game](https://interfaceingame.com/games/clash-royale/)
- [Clash Royale -- Game UI Database](https://www.gameuidatabase.com/gameData.php?id=1299)
- [Clash Royale Trophy Road -- Supercell](https://supercell.com/en/games/clashroyale/blog/release-notes/new-update-feature-enter-the-trophy-road/)
- [Clash Royale Q1 2026 UI Overhaul -- Prism News](https://www.prismnews.com/hobbies/mobile-gaming/clash-royale-update-arrives-late-february-with-ui-overhaul-and-free-hero)
- [10 Design Principles of Clash Royale -- Steemit](https://steemit.com/game/@clasre/breaking-down-designs-is-clash-royale-the-most-perfect-mobile-f2p-game-yet)
- [Clash Royale UI -- LinkedIn (Zo Burton)](https://www.linkedin.com/pulse/how-great-uiux-put-clash-royale-top-grossing-charts-zo-burton)

---

## 3. Fort Guardian

### What Is It

- **Genre**: Roguelike tower defense with merge mechanics
- **Platforms**: iOS (App Store) and Android (Google Play)
- **Developer**: Xiaomo (published by Voodoo)
- **Status**: Active but early/rough (currently around v0.13)

### Key Gameplay Mechanics

1. **Merge system**: Core loop is merging facilities, traps, and turrets. Combine lower-tier defenses into stronger versions. Limited space means placement decisions matter.
2. **Roguelike runs**: Every playthrough is different with dynamic challenges and random elements. Fail and start over with new options.
3. **Skill selection**: Between waves, choose from powerful skills to enhance defenses. Finding the right combinations is the meta-game.
4. **Endless enemy waves**: Increasingly difficult enemies, each with unique abilities. Forces adaptation.
5. **Progression unlocks**: New facilities, merge upgrades, and defense levels unlock over time.

### What Makes It Unique vs Other Castle Defense Games

- The **merge mechanic** differentiates it from pure placement TD games. It's less "where do I put towers" and more "what do I combine."
- The **roguelike replayability** gives it more session variance than scripted TD campaigns.
- It tries to bridge casual merge games (like Merge Dragons) with defense gameplay.

### Notable UI/UX Features

- Simple, mobile-first merge-and-place interface.
- However, the execution is rough: user reviews cite frequent crashes, no save system, no speed-up button for long waves, and ads that break gameplay. Defenses sometimes don't fire even when enemies are in range.

### How Does It Compare to Castle Fight

Fort Guardian is fundamentally different from Castle Fight:
- **Single player** (not PvP tug-of-war)
- **Direct control** (you place and merge defenses, not build-and-watch)
- **No opponent to counter** (waves are scripted, not player-created)
- **No economy/income management**

The merge mechanic could be an interesting inspiration for building upgrades, but the core gameplay loop is not comparable to Castle Fight's strategic PvP.

**Sources:**
- [Fort Guardian -- App Store](https://apps.apple.com/us/app/fort-guardian/id6736848868)
- [Fort Guardian -- Google Play](https://play.google.com/store/apps/details?id=com.xiaomo.bag&hl=en)
- [Fort Guardian -- Game Solver](https://game-solver.com/fort-guardian/)
- [Fort Guardian -- Qoo-App](https://m-apps.qoo-app.com/en-US/app/133778)

---

## 4. WC3 Castle Fight -- Strategic Depth

Castle Fight has been played for 15+ years because its strategic depth goes far beyond "build units and watch." Here is a comprehensive breakdown.

### Core Strategic Decisions

1. **Race selection**: 12-14 races (Human, Naga, Undead, Night Elf, Nature, Orc, Elf, North/Ice, Chaos, Corrupted, Mech, Elemental, Pandaren Empire). Each race has completely different unit rosters, special buildings, and play styles.
2. **Economy vs. army timing**: Do you invest in Treasure Boxes (income buildings that boost gold/sec by a %) to snowball economically, or rush cheap barracks units to pressure early?
3. **Unit composition**: Which combination of buildings to construct, given what the opponent is building.
4. **When to tech up vs. when to mass**: Cheap T1 units in volume vs. expensive T2/T3 units with special abilities.
5. **Adapt or commit**: Scouting what your opponent builds and deciding whether to pivot or double down.

### Unit Countering (Rock-Paper-Scissors)

Castle Fight uses Warcraft III's attack/armor type matrix:

| Attack Type | vs Light Armor | vs Medium Armor | vs Heavy Armor |
|---|---|---|---|
| **Normal** | Poor | Great | Decent |
| **Pierce** | Great | Poor | Decent |
| **Siege** | Decent | Decent | Great |

- **Normal damage** excels against Medium armor
- **Pierce damage** excels against Light armor  
- **Siege damage** excels against Heavy armor
- Units are effective or ineffective vs other kinds of units -- **producing the right unit balance is the key to winning**
- You cannot micro units. Everything is macro and strategy.

### Income Management Strategies

- **Income ticks every 10 seconds** (gold automatically granted).
- **Treasure Boxes**: Special buildings that boost income by a percentage. Building them early compounds over time but delays your army.
- **"Farming" / "Boxing"**: Advanced strategy coined by Korean players -- trapping enemy units in a box in your own base so they remain stationary and don't fight. This lets your units flow freely to the enemy castle while their units are stuck.
- **Building destruction penalty**: If enemies destroy your buildings, your income drops. Protecting buildings is not just about army production -- it is economic defense.
- **Early barracks rush**: Building barracks at 100 gold is the most cost-effective early play. Building special buildings first slows your income race.

### Building Placement Strategy

- **Build behind the castle**: Position buildings in the back area, behind the castle, as this is the least likely spot for enemy units to reach and destroy.
- **Build on allies' side**: In team games, coordinate building zones on the same half of the map as your allies.
- **Wall/maze building**: Not in original WC3 version but present in some variants and directly relevant to our game. Creating a longer path for enemy units gives your spawned units more time to deal damage.
- **Protect Treasure Boxes**: Since losing buildings cuts income, keep income buildings far from enemy pathing.

### Three Building Types

1. **Unit Spawn Buildings**: Periodically produce units that auto-march to the enemy castle. The bread and butter.
2. **Towers**: Stationary defenses that fire at attacking units in your base. Protect your buildings.
3. **Special Buildings**: Cast active or passive spells. Cost lumber + gold. Often define how a race plays. Identified by having a mana bar. Examples: buffs to your units, debuffs to enemies, AOE damage, healing auras.

### What Makes It Replayable for 15+ Years

1. **Race diversity**: 12+ completely distinct races means hundreds of matchup permutations.
2. **Opponent-dependent strategy**: Every game requires reading and reacting to what the other player builds. No "one best build."
3. **Draft mode** (Definitive Edition): Buildings are drafted in 5 rounds, choosing from packs. Forces adaptation and prevents rote play.
4. **Perk system** (Definitive Edition): After building drafts, each player picks a perk with both an upside and a downside. Adds another layer of customization.
5. **Team dynamics**: 2v2, 3v3, and beyond. Coordinating races and strategies with allies.
6. **Game modes**: Unique Races (-ur: each race picked only once per round), Domination (-dom: 50% bonus income for lane dominance), No Artillery, No Treasure Boxes, Fog of War, etc.
7. **The farming/boxing metagame**: Advanced techniques that separate novice from expert play.
8. **Snowball vs. comeback dynamics**: Income compounds, but a well-timed counter-build can reverse momentum.
9. **W3Champions ranked play**: Competitive ladder keeps hardcore players engaged.

### Features That Add Depth Beyond Basic Auto-Battler

- **Special building spells** (active abilities you must time and target)
- **Lumber as a secondary resource** for special buildings (forces resource allocation decisions)
- **Building destruction = income loss** (defense is economic, not just military)
- **Treasure Box income scaling** (compound interest mechanic)
- **Race-specific building synergies** (certain buildings buff others' units)
- **Three attack types + three armor types** (6-element counter matrix, not simple strong/weak)
- **No unit control** -- pure macro strategy, no micro skill masking bad decisions

**Sources:**
- [Castle Fight Definitive Edition](https://castlefight.cfd/)
- [Castle Fight -- How to Build Guide](https://castlefight.cfd/guides/how-to-play)
- [Castle Fight Strategy: Farming Guide](http://footmenfrenzy.blogspot.com/2009/06/castle-fight-strategies-guide-to_13.html)
- [Castle Fight Strategy: Human Guide](http://footmenfrenzy.blogspot.com/2009/06/castle-fight-strategies-guide-to-human.html)
- [Castle Fight Strategy: Massive AOE](http://footmenfrenzy.blogspot.com/2009/06/castle-fight-strategies-guide-to_16.html)
- [Castle Fight Strategy: Banshee Guide](http://footmenfrenzy.blogspot.com/2009/06/castle-fight-strategies-guide-to.html)
- [Castle Fight Game Modes](http://footmenfrenzy.blogspot.com/2009/05/castle-fight-game-modes-and-chat.html)
- [Castle Fight 1.30 -- Hive Workshop](https://www.hiveworkshop.com/threads/castle-fight-1-30.241772/)
- [Castle Fight Forever -- Hive Workshop](https://www.hiveworkshop.com/threads/castle-fight-forever.337055/)
- [WC3 Armor and Weapon Types -- Battle.net](https://classic.battle.net/war3/basics/armorandweapontypes.shtml)
- [Castle Fight -- Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=1757281740)
- [Castle Fight -- Warcraft 3 Wiki](https://gaming-tools.com/warcraft-3/castle-fight/)
- [Castle Fight Modes/Mechanisms -- uCoz](https://castlefight.ucoz.com/publ/mechanisms/modes/2-1-0-5)

---

## 5. Game Name Brainstorming

### Names to AVOID (Taken by Existing Games)

| Name | Why It Is Taken |
|---|---|
| Castle Clash | IGG's MMORTS (very popular, millions of downloads) |
| Clash of Clans | Supercell |
| Clash Royale | Supercell |
| Castle Siege | NexGame Studios mobile RPG + Amazon Appstore title |
| Tower War | SayGames LTD (Tactical Conquest) + multiple others |
| Wall Wars | Existing tower defense game (wall-wars.com) |
| Siege Castles | PHZ Games (iOS + Android) |
| Stronghold Clash | Existing App Store game (stickman defense) |
| Stronghold Kingdoms | Firefly Studios |
| Rise of Castles | Existing mobile game |
| Lords & Castles | Existing strategy game |
| Warkeep | Existing side-scrolling TD with keep-building |
| Rampart | Classic 1990 Atari arcade game + 2024 Steam remake |
| Bastion | Supergiant Games' acclaimed RPG |
| Fortress Warfare | Existing Steam game |
| Fort Guardian | Xiaomo/Voodoo (the game in Section 3) |
| Castle Guardian | Existing Steam game |
| Throne: Kingdom at War | Plarium's mobile game |
| March of Empires | Existing strategy game |

### Candidate Names (Verified Not Taken)

Each name below was searched and returned NO existing game with that exact name.

| # | Name | Vibe | Why It Works |
|---|---|---|---|
| 1 | **Siege Sworn** | Epic oath + warfare | Evokes commitment to battle. "Sworn" is unique in the space. No exact match found (SWORN exists but is a different genre entirely). |
| 2 | **Rampart Rivals** | Competitive wall-building | Directly references ramparts (castle walls) + rivalry. No game found with this exact name. |
| 3 | **Fief Fight** | Punchy alliteration | "Fief" = medieval land grant. Short, memorable, alliterative. No match found. |
| 4 | **Bulwark Brawl** | Defensive strength + action | "Bulwark" = strong defense. No game with this exact title (Bulwark: Falconeer Chronicles exists but different). |
| 5 | **Banner March** | Army on the move | Evokes medieval banners and marching armies. No match found. |
| 6 | **Ironkeep** | Single-word fortress | Strong, memorable, evokes iron castles. No match found. |
| 7 | **Fort Strife** | Conflict + fortification | Short, punchy, clear genre signal. No match found. |
| 8 | **Siege Forge** | Building + warfare | "Forge" your siege strategy. No match found. |
| 9 | **Castle Fray** | Classic + combat | "Fray" = a battle/brawl. Direct, easy to remember. No match found. |
| 10 | **Keep Wars** | Competitive castle defense | "Keep" = castle tower. Plural "Wars" signals ongoing conflict. No match found. |
| 11 | **Palisade Wars** | Wall-building warfare | "Palisade" = wooden defensive wall. Very on-brand for maze-building. No match found. |
| 12 | **Wardkeep** | Single-word compound | "Ward" (protect) + "Keep" (castle tower). Unique compound. No match found. |
| 13 | **Battlement Brawl** | Alliterative, specific | "Battlements" = castle wall top with gaps. Very medieval. No match found. |
| 14 | **Siege Grounds** | Place of battle | Where sieges happen. Clean and evocative. No match found. |
| 15 | **Fortress Rivals** | Competitive defense | Clear genre signal, competitive framing. No match found. |
| 16 | **Fief Siege** | Medieval land + warfare | Combines feudal terminology with action. No match found. |

### Top 5 Recommendations (Ranked)

1. **Siege Sworn** -- Most unique, most epic-sounding, easy to search. Two syllables each, rolls off the tongue. Works as a brand.
2. **Rampart Rivals** -- Perfectly describes the game (build ramparts, fight rivals). Alliterative. Clear genre.
3. **Fief Fight** -- Shortest, most memorable, strong alliteration. Could be the "punchy indie" name.
4. **Ironkeep** -- Single compound word. Strong brand potential. Easy to type and search. Works across cultures.
5. **Castle Fray** -- "Castle" is clear genre. "Fray" is unique vs all the "Clash"/"War"/"Siege" games. Short, clean.

### Naming Considerations

- Avoid "Clash" entirely (Clash of Clans, Castle Clash, Clash Royale dominate that keyword).
- Avoid "Royale" (owned by Supercell in the gaming mind).
- "Siege" is common but not oversaturated when paired uniquely.
- Single compound words (Ironkeep, Wardkeep) are strong for app store searchability.
- Alliteration (Fief Fight, Bulwark Brawl, Battlement Brawl) is memorable.
- Test names by saying them aloud: "Hey, have you played ___?" If it sounds natural, it works.

**Sources:**
- [Castle Clash -- Google Play (IGG)](https://play.google.com/store/apps/details?id=com.igg.castleclash)
- [Tower War: Tactical Conquest -- App Store](https://apps.apple.com/us/app/tower-war-tactical-conquest/id1579356887)
- [Wall Wars](https://www.wall-wars.com/)
- [Stronghold Clash -- App Store](https://apps.apple.com/us/app/stronghold-clash/id6596768009)
- [Siege Castles -- Google Play](https://play.google.com/store/apps/details?id=fi.phz.siegecastles&hl=en_US)
- [SWORN (different game) -- Steam](https://store.steampowered.com/app/1763250/SWORN/)
- [Warkeep -- ModDB](https://www.moddb.com/games/warkeep)
- [Bulwark: Falconeer Chronicles -- Steam](https://store.steampowered.com/app/290100/Bulwark_Falconeer_Chronicles/)
- [Rampart Classic -- Play Online](https://playclassic.games/games/strategy-dos-games-online/play-rampart-online/)
- [Fort Guardian -- Google Play](https://play.google.com/store/apps/details?id=com.xiaomo.bag&hl=en)
- [Best Medieval Mobile Games -- Pocket Gamer](https://www.pocketgamer.com/best-games/medieval-mobile-games/)
- [Top Castle Games 2025 -- Plarium](https://plarium.com/en/blog/top-castle-games/)
