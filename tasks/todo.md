# Castle Clash -- Master Task List

## Phase 0: Foundation (Current)
- [x] Deep research on Castle Fight mechanics
- [x] Research multiplayer architecture & server costs
- [x] Analyze mobile vs web platform decision
- [x] Research monetization & profitability strategies
- [x] Design the expert agent team
- [x] Write Game Design Document (GDD)
- [ ] Review & align on GDD with Pauline
- [ ] Set up Godot 4 project skeleton
- [ ] Set up git repository

## Phase 1: Web MVP (Months 1-4)
- [ ] **Core Simulation**
  - [ ] Implement deterministic game loop (fixed-point math, fixed timestep)
  - [ ] Implement grid-based building placement system
  - [ ] Implement wave spawn system (synchronized timer)
  - [ ] Implement unit AI (pathfinding, targeting, auto-combat)
  - [ ] Implement damage type / armor type matrix
  - [ ] Implement resource/income system
  - [ ] Implement castle HP and win condition
- [ ] **Factions (2 at MVP)**
  - [ ] Design & implement The Kingdom faction (balanced/beginner)
  - [ ] Design & implement The Horde faction (aggressive)
- [ ] **Multiplayer**
  - [ ] Set up Nakama server on VPS
  - [ ] Implement WebSocket relay protocol
  - [ ] Implement deterministic lockstep sync
  - [ ] Implement basic matchmaking (1v1 first)
  - [ ] Implement lobby/room system
  - [ ] Implement checksum sync for desync detection
- [ ] **UI/UX**
  - [ ] Main menu screen
  - [ ] Building placement UI (grid overlay, building menu)
  - [ ] HUD (resources, wave timer, castle HP)
  - [ ] End-of-match results screen
  - [ ] Basic tutorial / onboarding
- [ ] **Art (Placeholder -> Polish)**
  - [ ] Define chibi art style guide
  - [ ] Source/create placeholder sprites (8-12 unit types)
  - [ ] Source/create building sprites (8-10 buildings)
  - [ ] Create map/arena tileset
  - [ ] UI art and icons
- [ ] **Audio**
  - [ ] Source placeholder SFX (combat, building, UI)
  - [ ] Source background music (1-2 tracks)
- [ ] **Web Export**
  - [ ] Optimize Godot HTML5 export (<15MB)
  - [ ] Deploy to itch.io
  - [ ] Set up own domain with Cloudflare Pages

## Phase 2: Polish + Web Monetization (Months 4-7)
- [ ] Add 2 more factions (Undead, Wilds)
- [ ] Implement 2v2 and 3v3 team modes
- [ ] Submit to CrazyGames and Poki
- [ ] Implement battle pass system (Season 1)
- [ ] Implement cosmetic shop (Stripe payments)
- [ ] Integrate web ad SDK (rewarded ads)
- [ ] Implement ranked/ladder system
- [ ] Implement clan system
- [ ] Commission custom chibi art
- [ ] Add daily quests and retention hooks

## Phase 3: Mobile (Months 7-10)
- [ ] Export to Android (Godot native)
- [ ] Export to iOS (Godot native)
- [ ] Integrate AdMob (mobile ads)
- [ ] Integrate Google Play Billing + Apple StoreKit
- [ ] Implement cross-play (web + mobile on same Nakama backend)
- [ ] App Store Optimization (ASO)
- [ ] Soft launch in select regions

## Phase 4: Growth (Months 10+)
- [ ] Paid user acquisition (if LTV > CPI)
- [ ] New seasons with content updates
- [ ] Spectator mode
- [ ] Tournament system
- [ ] Geographic server expansion
