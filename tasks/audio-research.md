# Audio Research: Background Music & SFX for Castle Clash

> Medieval fantasy pixel art mobile game (Tiny Swords aesthetic, Kingdom Rush vibes)
> Research date: 2026-04-05

---

## Current State

The project currently uses **procedurally generated audio** via `castle_clash/autoload/sfx.gd` -- a custom synthesis engine that generates waveforms at runtime. There are zero audio files (.ogg/.wav) in the project. Replacing these with real audio assets will dramatically improve audio quality.

---

## MUSIC RECOMMENDATIONS

### 1. Main Menu Theme (Medieval, Warm, Inviting)

#### TOP PICK: "Medieval: King's Feast" by RandomMind
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/medieval-kings-feast
- **Files:** Kings_Feast.mp3 (5.2 MB) + Loop_Kings_Feast.wav (14.2 MB)
- **Why it fits:** Warm tavern/feast atmosphere with upbeat folk character. Users describe it as having "great ambience" -- perfect for a colorful medieval menu screen. Loop version included.
- **Format:** MP3 + WAV (convert WAV to OGG for Godot)

#### ALTERNATIVE: "Medieval: Minstrel Dance" by RandomMind
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/medieval-minstrel-dance
- **Files:** Minstrel_Dance.mp3 (5.5 MB) + Loop_Minstrel_Dance.wav (19.9 MB)
- **Why it fits:** Lute and viola -- classic medieval instruments. Tagged as "fantasy, dance, feast, tavern, RPG." More lively than King's Feast, could work for menu or as a secondary theme.

#### ALTERNATIVE: "Medieval Folk Loop Instrumental Flute Guitar Piano" by melodyayresgriffiths
- **Source:** Pixabay
- **License:** Pixabay Content License (free for commercial use, no attribution required)
- **URL:** https://pixabay.com/music/folk-medieval-folk-loop-instrumental-flute-guitar-piano-148606/
- **Duration:** 0:22 loop
- **Why it fits:** Short, seamless loop with flute/guitar/piano. Very lightweight for mobile. Tagged with "Videogame, Game, Medieval, Folk."

#### ALTERNATIVE: "Medieval: The Old Tower Inn" by RandomMind
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/medieval-the-old-tower-inn
- **Why it fits:** Cozy inn atmosphere, warm and inviting. Same composer as King's Feast so style is consistent.

---

### 2. Battle/Gameplay Music (Energetic, Builds Tension, Loopable)

#### TOP PICK: "Medieval: Battle" by RandomMind
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/medieval-battle
- **Files:** MP3 (3.2 MB) + WAV (27.8 MB)
- **Why it fits:** Tagged "upbeat, enthusiastic, motivated" -- energetic medieval battle music from the same composer as the menu picks. Consistent style across menu and gameplay.

#### ALTERNATIVE: "Battle Theme A" by cynicmusic
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/battle-theme-a
- **Files:** MP3 (3.3 MB)
- **Why it fits:** "Epic strings and horns" -- orchestral battle music widely adopted by indie game devs. Proven in commercial and indie games across multiple platforms.

#### ALTERNATIVE: "Epic Battle BGM Pack Vol.1" by Nokurea
- **Source:** itch.io
- **License:** CC0 (Public Domain)
- **URL:** Search "Epic Battle BGM Pack Vol.1 Nokurea" on itch.io
- **Content:** 2 loop-ready battle tracks
- **Why it fits:** Purpose-built for indie games. CC0 licensed. 5.0/5 rating. Loop-ready means no editing needed.

#### ALTERNATIVE: "Fantasy Music and Drum Loops Pack" by NorthFantasyMusic
- **Source:** OpenGameArt.org
- **License:** CC-BY 4.0 (attribution required: "North Fantasy Music")
- **URL:** https://opengameart.org/content/fantasy-music-and-drum-loops-pack
- **Content:** 15 background tracks + 3 drum loops + 2 mixed tracks (WAV 44.1kHz/16-bit)
- **Why it fits:** Layerable drum loops let you build tension dynamically. Dark fantasy orchestral -- slightly moodier than Tiny Swords aesthetic but the drum loops alone are gold for battle intensity.

---

### 3. Victory Fanfare (Triumphant, Short)

#### TOP PICK: "Lively Meadow (Victory Fanfare and Song)" by Matthew Pablo
- **Source:** OpenGameArt.org
- **License:** CC-BY 3.0 (attribute: "Matthew Pablo")
- **URL:** https://opengameart.org/content/lively-meadow-victory-fanfare-and-song
- **Files:** Fanfare alone + Song alone + Combined loopable version (MP3)
- **Why it fits:** Tagged "happy, cute, catchy, cheerful, joyous" -- **perfect match for Tiny Swords' colorful aesthetic**. Includes both short fanfare and looping summary screen track. The "cute" and "cheerful" tags are exactly the tone needed.

#### ALTERNATIVE: "Victory Fanfare Short" by cynicmusic
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/victory-fanfare-short
- **Files:** WAV (2.1 MB)
- **Why it fits:** CC0 (no attribution needed), "several bar victory fanfare for RPG, boss win." More epic/cinematic than Lively Meadow.

#### ALTERNATIVE: Kenney Music Jingles (Win jingles)
- **Source:** Kenney.nl / OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://kenney.nl/assets/music-jingles or https://opengameart.org/content/85-short-music-jingles
- **Content:** 85 OGG files -- 17 jingles x 5 instruments. Includes "Win" and "Lose" variations.
- **Why it fits:** Covers both victory AND defeat in one pack. Very lightweight (1.1 MB total). Multiple instrument options to audition.

---

### 4. Defeat Music (Somber, Short)

#### TOP PICK: "Sad Game Over" by Emma_MA
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/sad-game-over
- **Files:** WAV (3.4 MB)
- **Why it fits:** "Short sad electric piano piece suitable for a game over/death screen." Users report strong emotional impact. CC0 licensed.

#### ALTERNATIVE: Kenney Music Jingles (Lose jingles)
- **Source:** Kenney.nl
- **License:** CC0 (Public Domain)
- **URL:** https://kenney.nl/assets/music-jingles
- **Content:** "Lose" jingles across 5 instruments within the 85-jingle pack
- **Why it fits:** Same pack as the victory jingles -- keeps audio style consistent. Extremely lightweight.

---

## SFX RECOMMENDATIONS

### 1. UI Sounds (Button Click, Card Select, Tab Switch, Menu Transition)

#### TOP PICK: Kenney "UI Audio"
- **Source:** Kenney.nl
- **License:** CC0 (Public Domain)
- **URL:** https://kenney.nl/assets/ui-audio
- **Content:** 50 UI sounds (buttons, switches, clicks)
- **Why it fits:** Industry-standard game UI sounds. CC0. Kenney assets are widely used in indie games and Godot projects specifically.

#### COMPLEMENT: "Interface SFX Pack 1" by ObsydianX
- **Source:** itch.io
- **License:** CC0 (Public Domain)
- **URL:** https://obsydianx.itch.io/interface-sfx-pack-1
- **Content:** 200+ interface sounds in WAV and OGG formats
- **Categories:** Confirm Tones, Back Tones, Cursor Tones, Error Tones (6 styles with 7+ patterns each)
- **Why it fits:** PSX-era RPG aesthetic matches pixel art games. Massive variety to find the right feel. Already in OGG format for Godot.

#### COMPLEMENT: "RPG Essentials SFX - Free!" by Leohpaz
- **Source:** itch.io
- **License:** Free for commercial use (no redistribution)
- **URL:** https://leohpaz.itch.io/rpg-essentials-sfx-free
- **Content:** 48 SFX including UI (hover, confirm, decline, equip, buy/sell, pause)
- **Why it fits:** UI sounds specifically designed for RPG context. Also includes magic and battle sounds (see below).

---

### 2. Battle Sounds (Sword Clash, Arrow Fire, Spell Cast, Unit Death, Heal)

#### TOP PICK: "Free Fantasy 200 SFX Pack" by TomMusic
- **Source:** itch.io
- **License:** Royalty-free, commercial use OK, credit appreciated but not required
- **URL:** https://tommusic.itch.io/free-fantasy-200-sfx-pack
- **Content:** 200+ SFX in OGG and WAV formats
- **Categories:** 20+ bow/sword SFX, 20+ spell SFX with variations, footsteps (50+), doors/chests/gates, ambient loops
- **Why it fits:** **Single pack covers most battle needs.** OGG + WAV formats are Godot-native. Comprehensive medieval fantasy SFX in one download.

#### COMPLEMENT: "20 Sword Sound Effects" by StarNinjas
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes
- **Content:** 10 sword attacks + 10 sword clashes (also work as shield blocks)
- **Why it fits:** Real metal sounds (knives + Audacity editing). CC0. Dedicated sword pack for more variety on melee combat.

#### COMPLEMENT: "Medieval Sound Effects - Weapon Textures" by Ben Jaszczak & Brian Nelson
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/medieval-sound-effects-weapon-textures
- **Content:** 46 weapon sounds -- arrows, axes, crossbows, daggers, spears, longbows, recurve bows
- **Why it fits:** Real weapon recordings. Covers the full range of medieval weapon types matching Castle Clash unit types (archer, axe thrower, knight, etc.).

#### COMPLEMENT: "80 CC0 RPG SFX" by rubberduck
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/80-cc0-rpg-sfx
- **Content:** 80 SFX -- Blade (3), Creature sounds (22: die/hurt/roar), Spell (9: regular + fire), Items (21: coins/gem), Chain, Metal, Wood
- **Why it fits:** CC0 one-stop-shop for RPG combat. Covers swords, spells, death sounds, AND coin/item sounds. Tiny 1.8 MB download.

#### FOR HEALING: "RPG Essentials SFX - Free!" by Leohpaz (listed above)
- Includes: healing, attack buff, defense buff, revive -- all relevant for the Priest unit's heal ability

---

### 3. Building Placement (Construction Sounds)

#### TOP PICK: "100 CC0 Metal and Wood SFX" by rubberduck
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/100-cc0-metal-and-wood-sfx
- **Content:** 100 sounds -- hammer strikes, wood breaking/cracking, door sounds, metal impacts, springs, tools
- **Why it fits:** Hammer + wood sounds are perfect for building placement. CC0. Small 2 MB download.

#### COMPLEMENT: Kenney "Impact Sounds"
- **Source:** Kenney.nl
- **License:** CC0 (Public Domain)
- **URL:** https://kenney.nl/assets/impact-sounds
- **Content:** 130 impact/foley sounds
- **Why it fits:** Wood/thud impacts for building placement feedback. Can layer with construction sounds.

---

### 4. Gold/Coin Collect

#### TOP PICK: "12 Coin Sound Effects" by StarNinjas
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/12-coin-sound-effects
- **Content:** 12 real coin sounds (coins rumbled in hand)
- **Why it fits:** Authentic metal coin sounds. CC0. Multiple variations to randomize for natural feel. Same creator as the sword pack (consistent quality).

#### ALTERNATIVE: "Coins Sound Effects Library" by Little Robot Sound Factory
- **Source:** OpenGameArt.org
- **License:** CC-BY 3.0 (attribute: "Little Robot Sound Factory")
- **URL:** https://opengameart.org/content/coins-sound-effects-library
- **Content:** 151 sounds -- 56 single coin, 46 few coins, 23 several coins, 14 pouring coins, 7 single gem, 2 few gems (MP3 + WAV)
- **Why it fits:** Massive variety for different gold amounts. Gem sounds for potential future loot. Professional quality.

#### ALSO COVERED BY: "80 CC0 RPG SFX" by rubberduck (includes coin/gem sounds)

---

### 5. Castle Damage (Impact, Rumble)

#### TOP PICK: Kenney "Impact Sounds"
- **Source:** Kenney.nl
- **License:** CC0 (Public Domain)
- **URL:** https://kenney.nl/assets/impact-sounds
- **Content:** 130 impact sounds
- **Why it fits:** Heavy impacts for castle damage. Layer multiple impacts for destruction feel. CC0.

#### COMPLEMENT: "100 CC0 SFX #2" by rubberduck
- **Source:** OpenGameArt.org
- **License:** CC0 (Public Domain)
- **URL:** https://opengameart.org/content/100-cc0-sfx-2
- **Content:** 100 SFX including hits, metal hits, stone sounds, thunder, wood hits, construction loops
- **Why it fits:** Stone impact sounds for castle walls. Thunder for dramatic castle damage. CC0.

---

### 6. Wave Horn/Announcement

#### TOP PICK: "Battle Horn" by Porphyr
- **Source:** Freesound.org
- **License:** CC-BY 4.0 (attribute: "Porphyr")
- **URL:** https://freesound.org/people/Porphyr/sounds/188815/
- **Format:** WAV, 12 seconds, 48kHz/24-bit stereo
- **Why it fits:** Processed battle horn described as "sinister" -- a callsign before medieval/fantasy battle. Trim to 2-3 seconds for a wave announcement.

#### ALTERNATIVE: Use the procedural war horn already in sfx.gd
- The current `play_wave()` function generates a passable war horn. Could keep this and upgrade later.

---

### 7. Ambient Battle Atmosphere

#### TOP PICK: "Ambient battle noise: swords and shouting" by pfranzen
- **Source:** Freesound.org
- **License:** CC-BY 4.0 (attribute: "pfranzen")
- **URL:** https://freesound.org/people/pfranzen/sounds/192072/
- **Format:** MP3, 4:43 duration
- **Why it fits:** "Ambient battle noise of medieval warfare: angry men shouting and clanging swords together." Perfect background layer during gameplay. Long duration means seamless looping.

#### COMPLEMENT: TomMusic "Free Fantasy 200 SFX Pack" (listed above)
- Includes 20+ loopable background ambience with day/night and weather variations

---

## MEGA-PACKS (Best Value -- Cover Multiple Needs)

These packs cover many categories at once and should be downloaded first:

| Pack | Source | License | Sounds | Covers |
|------|--------|---------|--------|--------|
| **Kenney RPG Audio** | kenney.nl | CC0 | 50 | Weapons, footsteps, foley |
| **Kenney UI Audio** | kenney.nl | CC0 | 50 | All UI sounds |
| **Kenney Impact Sounds** | kenney.nl | CC0 | 130 | Building place, castle damage |
| **Kenney Music Jingles** | kenney.nl | CC0 | 85 | Victory + defeat jingles |
| **80 CC0 RPG SFX** (rubberduck) | OpenGameArt | CC0 | 80 | Swords, spells, creatures, coins |
| **Free Fantasy 200 SFX** (TomMusic) | itch.io | Royalty-free | 200+ | Swords, bows, spells, ambience |
| **RPG Essentials SFX** (Leohpaz) | itch.io | Free commercial | 48 | UI, magic, battle, healing |

---

## RECOMMENDED DOWNLOAD PRIORITY

### Phase 1: Core Audio (Do First)
1. **Kenney UI Audio** -- immediate UI improvement (CC0)
2. **Kenney Music Jingles** -- victory + defeat jingles (CC0)
3. **80 CC0 RPG SFX** by rubberduck -- swords, spells, coins, creatures (CC0)
4. **RandomMind medieval music** -- King's Feast (menu) + Battle (gameplay) (CC0)

### Phase 2: Polish
5. **Free Fantasy 200 SFX Pack** by TomMusic -- fill remaining gaps
6. **Interface SFX Pack 1** by ObsydianX -- more UI variety (CC0)
7. **12 Coin Sound Effects** by StarNinjas -- better coin sounds (CC0)
8. **Lively Meadow** by Matthew Pablo -- cheerful victory fanfare (CC-BY)
9. **Sad Game Over** by Emma_MA -- defeat screen (CC0)

### Phase 3: Atmosphere
10. **Ambient battle noise** by pfranzen -- battle atmosphere (CC-BY)
11. **Battle Horn** by Porphyr -- wave announcement (CC-BY)
12. **100 CC0 Metal and Wood SFX** by rubberduck -- building placement
13. **Kenney Impact Sounds** -- castle damage impacts (CC0)

---

## ATTRIBUTION REQUIREMENTS

Assets requiring attribution (CC-BY):
- "Lively Meadow" -- credit Matthew Pablo
- "Fantasy Music and Drum Loops Pack" -- credit North Fantasy Music
- "Coins Sound Effects Library" -- credit Little Robot Sound Factory
- "Battle Horn" (Freesound) -- credit Porphyr
- "Ambient battle noise" (Freesound) -- credit pfranzen
- "Medieval Weapon Textures" -- credit Ben Jaszczak & Brian Nelson

All other recommended assets are **CC0 (no attribution required)**.

Consider adding a credits/attribution screen in the game settings to cover CC-BY requirements.

---

## GODOT INTEGRATION NOTES

- **Music:** Import as `.ogg` (OGG Vorbis) for streaming. Set import mode to "Stream" for music tracks.
- **SFX:** Import as `.wav` for low-latency playback, or `.ogg` for smaller file size on mobile.
- **The existing `sfx.gd` AudioStreamGenerator system** can coexist with file-based audio. Swap functions one at a time.
- **AudioBus setup:** Create separate buses for Music, SFX, and UI sounds for independent volume control.
- **Mobile optimization:** OGG files are ~10x smaller than WAV. Target total audio budget of 5-15 MB for mobile.

---

## TOTAL ESTIMATED SIZE

If using OGG for everything:
- Music (4 tracks): ~8-12 MB
- SFX (all packs): ~5-10 MB
- **Total: ~13-22 MB** (acceptable for mobile)
