# Castle Clash -- Master Task List

## Phase 0: Foundation
- [x] Deep research on Castle Fight mechanics
- [x] Research multiplayer architecture & server costs
- [x] Analyze mobile vs web platform decision
- [x] Research monetization & profitability strategies
- [x] Design the expert agent team
- [x] Write Game Design Document (GDD)
- [x] Set up Godot 4 project skeleton
- [x] Set up git repository

## Phase 1: Web MVP (Months 1-4)
- [x] **Core Simulation**
  - [x] Deterministic game loop (fixed-point math, fixed timestep)
  - [x] Grid-based building placement + sell buildings
  - [x] Wave spawn system (synchronized timer)
  - [x] Unit AI (targeting, auto-combat, healing, castle damage)
  - [x] Damage type / armor type matrix (4x4)
  - [x] Resource/income system
  - [x] Castle HP and win condition
- [x] **Factions (2 at MVP)**
  - [x] The Kingdom (5 buildings: Barracks, Archer Range, Priest Temple, Knight Hall, Siege Workshop)
  - [x] The Horde (5 buildings: War Camp, Axe Range, War Drums, Berserker Pit, Demolisher Works)
- [x] **Multiplayer**
  - [x] Nakama server setup (Docker Compose)
  - [x] Nakama Godot addon integration
  - [x] NetworkManager with auth, matchmaking, relay, lockstep
  - [x] GameManager lockstep tick waiting + checksum desync detection
  - [x] Offline mode preserved for local dev
  - [ ] Test with 2 browser tabs against local Nakama
  - [ ] Deploy Nakama to VPS for public play
- [x] **UI/UX**
  - [x] Main menu with faction selection
  - [x] Building placement UI (grid overlay, ghost preview)
  - [x] HUD (gold, wave timer, castle HP)
  - [x] End-of-match results screen (victory/defeat + restart)
  - [x] Unit health bars (green/yellow/red)
  - [x] Sell buildings (right-click)
  - [x] Simple AI opponent
  - [x] Castle HP bars on castle areas
  - [x] Wave announcement text
  - [x] Building tier indicators + unit name labels
  - [x] Play Online button with connection status
  - [ ] Basic tutorial / onboarding
- [ ] **Art (Placeholder -> Polish)**
  - [ ] Define chibi art style guide
  - [ ] Source/create placeholder sprites
  - [ ] Create map/arena tileset
- [ ] **Audio**
  - [ ] Source placeholder SFX
  - [ ] Source background music
- [x] **Web Export**
  - [x] Godot HTML5 export (37MB total, ~12MB gzipped)
  - [ ] Deploy to itch.io
  - [ ] Set up domain with Cloudflare Pages

## Phase 2: Polish + Web Monetization (Months 4-7)
- [ ] Add 2 more factions (Undead, Wilds)
- [ ] Implement 2v2 and 3v3 team modes
- [ ] Submit to CrazyGames and Poki
- [ ] Implement battle pass system
- [ ] Implement cosmetic shop
- [ ] Implement ranked/ladder system
- [ ] Implement clan system
- [ ] Commission custom chibi art
- [ ] Add daily quests and retention hooks

## Phase 3: Mobile (Months 7-10)
- [ ] Export to Android + iOS
- [ ] Integrate mobile ads + IAP
- [ ] Cross-play (web + mobile same backend)
- [ ] App Store Optimization

## Phase 4: Growth (Months 10+)
- [ ] Paid user acquisition
- [ ] New seasons with content
- [ ] Spectator mode + tournaments
