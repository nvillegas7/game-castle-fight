# Screen Parity Audit — full findings (wf_878bcc29, 2026-07-10)

Raw output of the 5 audit agents. Referenced by `tasks/plan-screen-parity.md`.
Persisted here because the workflow journal lives in /tmp (purged ~3 days).
Findings are pixel-measured; coords are CAPTURE space (504x896 = 0.7x design; x1.43 → design px).

## Loading + Battle tab — grade D+

### [HIGH] cohesion — `scripts/ui/main_menu.gd:2062`
**Issue:** All 3 volume sliders are raw Godot-default controls: neutral gray track RGB(121,118,116) at capture y=125/164/203, near-white circular grabber RGB(210,209,208) only 9px tall in capture, ~5px track. Pure grays violate the Tiny Swords palette and are the single loudest 'programmer art' cue on the Settings tab.

**Fix:** In _add_volume_slider (scripts/ui/main_menu.gd:2062-2070), theme the HSlider with the existing bar assets: slider.add_theme_stylebox_override("slider", StyleBoxTexture from res://assets/sprites/ui/ninepatch/bigbar_base.png), add_theme_stylebox_override("grabber_area"/"grabber_area_highlight", StyleBoxTexture from bigbar_fill.png), and add_theme_icon_override("grabber"/"grabber_highlight", preload res://assets/sprites/ui/TinyRoundBlueButton.png scaled to ~48px). These assets already exist in assets/sprites/ui/.

### [HIGH] hierarchy — `scripts/ui/main_menu.gd:1852`
**Issue:** Both tabs are mostly empty dark-brown void: Social content ends at capture y=295 with the tab bar at y=812 — 64% of the content area is bare RGB(39,29,20); Settings ends at y=398 (51% void). Kingdom Rush screens fill or vertically center their content; these read as unfinished stubs.

**Fix:** In _build_social_tab (main_menu.gd:1852) and _build_settings_tab (:1967), set vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL and vbox.alignment = BoxContainer.ALIGNMENT_CENTER so content centers vertically, and add a NinePatchRect backdrop (res://assets/sprites/ui/ninepatch/regularpaper.png, patch margins 64) behind the vbox spanning the content area so the tab reads as a designed parchment screen instead of a void.

### [HIGH] cohesion — `scripts/ui/main_menu.gd:1873`
**Issue:** MATCH RECORD and FRIENDS cards are flat cold-navy StyleBoxFlat panels (measured card bg RGB(29,42,69), border slate-blue) — programmer-gray boxes in a cold hue outside the Tiny Swords warm wood/paper range. The themed 9-patch library (ninepatch/regularpaper.png, woodtable.png, ribbon_*.png) exists and is already used by the Battle tab (main_menu.gd:1134), so these two tabs break cross-tab consistency.

**Fix:** Replace the _make_style navy panels at main_menu.gd:1873 and :1910 with NinePatchRect nodes using res://assets/sprites/ui/ninepatch/regularpaper.png (patch margins ~64), switch body text to dark brown Color(0.25,0.16,0.08) on the cream paper, and render each card title on a SmallRibbons/ribbon_blue.png strip like the Battle tab ribbon pattern (_apply_texture_bg at :1135).

### [MED] hig — `scripts/ui/main_menu.gd:2042`
**Issue:** Touch targets under the 80px-design minimum: slider grabber is ~13px design tall (9px capture) inside a 40px-design row (main_menu.gd:2042), and both Settings buttons are 400x50 design (measured 35px capture height, y=296-331 for Reset) — 50px < 80px design / 56px capture minimum.

**Fix:** Set row.custom_minimum_size = Vector2(0, 80) at main_menu.gd:2042, give the themed grabber icon a ~48-56px texture so the effective slider hit area reaches 80px, and change both button custom_minimum_size to Vector2(400, 80) at main_menu.gd:2006 and :2015.

### [MED] hig — `scripts/ui/main_menu.gd:2013`
**Issue:** The destructive 'Reset All Progress' is the visual primary of the Settings tab: brightest saturated element (fill RGB(111,32,20), text luminance max 715) while the only other button is disabled gray-brown. Apple HIG: destructive actions must not be the most prominent action; there is effectively no positive primary action on this screen.

**Fix:** At main_menu.gd:2013-2018, restyle reset as a low-emphasis outline button (transparent fill, 2px muted red border Color(0.6,0.25,0.15), red text) and move it below the credits block; keep the existing _reset_confirm flow. If Replay Tutorial stays disabled, remove it or restyle as a paper-toned secondary so the tab has a sane emphasis order.

### [MED] hierarchy — `scripts/ui/main_menu.gd:1908`
**Issue:** Social empty-state/placeholder quality is stub-tier: FRIENDS card is one 15px text line ('Coming soon...') with no illustration or CTA, and MATCH RECORD crams 5 stats into two 15px text lines (capture y=141/158). Kingdom Rush-quality screens illustrate empty states and give stats iconized rows.

**Fix:** In _build_social_tab: render MATCH RECORD as three mini stat-cards (Wins/Losses/Trophies) with icons from assets/sprites/ui/Icon_XX.png following the end_screen.gd stat-card pattern (insert after main_menu.gd:1893); in the FRIENDS card (after :1936) add a row of 3-4 desaturated Avatars_XX.png TextureRects plus a disabled themed 'Invite Friends' button so the placeholder looks designed.

### [MED] hierarchy — `scripts/ui/main_menu.gd:1994`
**Issue:** Settings has no section grouping: sliders, two buttons, and credits sit in one flat VBox separated only by near-invisible 2px ColorRect dividers (capture rows 237-238, RGB(75,56,27) vs bg RGB(39,29,20) — barely 1.4px after scaling). No 'Audio' / 'Game' / 'About' structure.

**Fix:** Wrap each group in a titled paper panel: an 'AUDIO' panel containing the 3 slider rows, a 'GAME' panel with the buttons, and an 'ABOUT' panel with credits — each a NinePatchRect (ninepatch/regularpaper.png) with a small ribbon header label; delete the ColorRect dividers at main_menu.gd:1994-1998 and :2022-2026.

### [LOW] cohesion — `scripts/ui/main_menu.gd:1865`
**Issue:** Cross-tab title inconsistency: 'SOCIAL' is font_size 24 with a 12px top spacer (main_menu.gd:1859,1865) while 'SETTINGS' is 28 with a 20px spacer (:1975,:1982) — measured ~17px vs ~20px cap-height in capture.

**Fix:** Unify both to font_size 28 and 20px spacer, ideally via a shared _add_tab_title(vbox, text) helper used by both _build_social_tab and _build_settings_tab.

### [LOW] readability — `scripts/ui/main_menu.gd:2032`
**Issue:** Sub-baseline font sizes: credits at font_size 13 (renders ~9px in capture, smallest text on screen) and slider percentage labels at 14 — both below the global 16px Pixel Operator Bold baseline. Contrast itself is fine (credits 10.9:1) so this is size-only.

**Fix:** Raise credits font_size 13 -> 16 at main_menu.gd:2032 and pct label font_size 14 -> 16 at main_menu.gd:2076 to match the global baseline; widen pct custom_minimum_size to 60 so '100%' still fits.

**Strengths to preserve:**
- Text contrast is strong everywhere: match-record stats 6.8:1 vs card bg, credits 10.9:1 vs background, gold accent labels RGB(255,217,76) clearly legible — do not darken these colors when re-theming.
- No cropped or floating assets on either tab: nothing is cut by screen edges or panel bounds, and the pct labels end at capture x=473 with safe margin from the panel edge at x~496.
- Card style is internally consistent — Social's record/friends cards deliberately match the Army tab unit-card style (same _make_style params), so re-theming should change all of them together, not just these two.
- Settings slider rows have a clean, consistent layout rhythm (label 180px column, expanding slider, right-aligned live-updating percentage) — keep this structure when swapping in themed slider skins.
- Destructive action color semantics are correct (red = danger, and a confirm flow via _reset_confirm exists) — only its prominence needs reduction, not its color language.
- The warm dark-brown background RGB(39,29,20) matches the wood-frame header and tab bar, so the base palette direction is right; the tabs need content density, not a palette swap.

## Shop + Army tabs — grade C+

### [HIGH] hig — `scripts/ui/end_screen.gd:37`
**Issue:** End screen does not take over (backlog 3.5): under the 40% overlay the in-match HUD (timer 'Time 8:59' + YOU/FOE HP bars, capture y=0-30), gold bar ('10g (+20/5s)', y=698-718), and the entire two-row card hand (y=722-896, ~20% of screen; card costs and 'LOCKED Need: Priest Temple' text fully legible) all bleed through and compete with the results panel. KR victory screens keep the battlefield visible but remove all in-game chrome.

**Fix:** At the top of _on_match_ended() (after visible = true), hide the sibling UI: `for n_name in ["HUD", "GoldBarBg", "CardHand"]: var n = get_parent().get_node_or_null(NodePath(n_name)); if n: n.visible = false`. Keep the 40% Overlay so the arena itself stays visible per T-100. Scene reload on restart/menu restores them automatically.

### [HIGH] readability — `scripts/ui/end_screen.gd:116`
**Issue:** 'VICTORY!' title fails large-text contrast: fill (255,235,77) vs ribbon body (161,151,66) = 2.46:1 (needs 3:1), and the outline (168,95,12) is only 1.63:1 vs the ribbon so it doesn't rescue it. Root cause: ribbon.modulate.a = 0.85 blends the Tiny Swords yellow ribbon into a muddy olive against the dark backdrop, and the outline color (0.6, 0.35, 0.05) is too light.

**Fix:** In _on_match_ended: set ribbon.modulate.a = 1.0 (line 116) to restore the asset's true parchment color; change result_label font_outline_color from Color(0.6, 0.35, 0.05) to Color(0.22, 0.11, 0.02) and outline_size from 5 to 6 (lines 124-125) — dark outline vs ribbon is ~5.6:1, fill vs outline ~7:1. Also change font_size 46 to 48 (line 126) for an integer 3x scale of the 16px pixel font.

### [HIGH] hig — `scenes/game/game_arena.tscn:397`
**Issue:** All three buttons are far below the 80px-design touch-target minimum: PLAY AGAIN measures 30px capture (~43px design), MAIN MENU 29px (~41px), Share Result 26px (~37px). Scene sets custom_minimum_size (0,48) and share button hardcodes (180,40).

**Fix:** In game_arena.tscn set RestartButton custom_minimum_size to Vector2(0, 96) and MenuButton to Vector2(0, 80) (lines ~397 and ~401); in _add_share_button change share_btn.custom_minimum_size to Vector2(260, 80) and font_size 14 to 16 (end_screen.gd:317-318). Alternatively enforce in _style_end_button: btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, 80.0).

### [MED] cohesion — `scripts/ui/end_screen.gd:80`
**Issue:** Panel style is mixed: the title ribbon is a real Tiny Swords 9-patch, but the results backdrop is a flat near-black StyleBoxFlat (bg 36,26,14 at 0.96 alpha) spanning ~490x560 design px — a dark programmer-gray-style void by KR standards — and both buttons and all stat cards are flat StyleBoxFlat boxes. Themed assets (regularpaper.png, woodtable.png, bigbluebutton_regular/pressed.png, bigredbutton_*.png) exist in assets/sprites/ui/ninepatch/ and are unused here.

**Fix:** Replace the backdrop Panel (end_screen.gd:78-93) with a NinePatchRect using res://assets/sprites/ui/ninepatch/woodtable.png (texture_filter NEAREST, patch margins per texture) so the panel reads as warm Tiny Swords wood; in _style_end_button (end_screen.gd:513-537) swap StyleBoxFlat for StyleBoxTexture with bigbluebutton_regular.png / bigbluebutton_pressed.png (yellow-modulated for the primary), keeping the font overrides. Stat card StyleBoxFlat rows may stay but lighten bg toward parchment, e.g. Color(0.36, 0.28, 0.17, 0.9).

### [MED] readability — `scripts/ui/end_screen.gd:589`
**Issue:** Stat card text is 13px design = ~9px at capture scale — a non-native size for the 16px pixel font, producing mushy glyphs ('8 enemies | 8 lost' barely resolves); the Record line (StatsLabel) is also 13px at 0.8 alpha. Contrast itself is fine (7.2:1 key, 7.9:1 value) but the size is below comfortable mobile body text.

**Fix:** Set key_lbl and val_lbl font_size overrides from 13 to 16 (end_screen.gd:589 and 626) and card custom_minimum_size from (0,32) to (0,44) (end_screen.gd:573); in game_arena.tscn StatsLabel change theme_override_font_sizes/font_size from 13 to 16 and font alpha from 0.8 to 1.0 (line ~389).

### [MED] hierarchy — `scripts/ui/end_screen.gd:490`
**Issue:** Victory celebration is far below KR quality: confetti is 20 one-shot ColorRects of 4-8px design (3-6px capture) that despawn within 2.5s — in the capture they read as frozen dust specks over the stat cards (e.g. capture px (403,368), (466,325), (330,417)), i.e. visual noise rather than celebration, and the screen is static moments after appearing.

**Fix:** In _spawn_confetti (end_screen.gd:477-509): raise particle size to rng.randf_range(8, 16), count to 40, restrict palette to warm golds/creams + local faction accent (drop the neon blue 0.4,0.6,1.0), and loop waves while the screen is visible (after cleanup_tw interval, tween_callback(_spawn_confetti) guarded by `if visible`). Keep z_index 100 but spawn from above the panel top so particles fall past the ribbon, not across stat text.

### [LOW] cohesion — `scripts/ui/end_screen.gd:447`
**Issue:** Star row is procedural anti-aliased vector polygons (_StarSlot._draw with draw_colored_polygon + smooth polyline outline) sitting amid pixel art — edges are smooth while everything else is chunky-pixel, a subtle style mismatch vs KR's ornate sprite stars.

**Fix:** Render stars from a small pre-made pixel-art star texture instead: draw once to a 32x32 Image in a tools/ script (or crop one from the Tiny Swords UI icons), load via Sprite2D with TEXTURE_FILTER_NEAREST at 3x scale in _StarSlot, keeping the existing pop/flash tweens on the sprite's scale.

**Strengths to preserve:**
- Clear single primary action: gold PLAY AGAIN visually dominates the dark MAIN MENU and subdued Share Result — the color hierarchy is correct, only the sizes need scaling up
- KR-style structure is already right: 3-star pop row above a Tiny Swords ribbon title, stat rows, trophy count-up with rank, then actions — do not reorder this vertical flow
- Stat card key/value contrast is strong (7.2:1 gold keys, 7.9:1 cream values on brown) with a pleasant staggered slide-in reveal
- Warm brown/gold palette throughout the panel — no raw Godot grays or neon inside the results block
- Layout math is solid: backdrop (design x≈96-623, y≈286-918) is centered with even margins, nothing cropped or floating, ribbon tails and stars sit fully inside the panel
- Star rating logic tied to castle HP remaining plus dim-slot outlines is a genuine KR-style touch worth keeping

## Social + Settings tabs — grade C-

### [HIGH] hierarchy — `scripts/ui/main_menu.gd:1777`
**Issue:** Army tab shows spawner BUILDINGS instead of unit sprites (backlog 3.6 confirmed): 'Footman [Melee]' row displays a blue-roofed barracks, 'Priest [Caster]' a church (icon bbox ~x14-104, y118-199 capture). The tab is titled UNIT ROSTER but no units appear anywhere; players must mentally map house art to soldiers. Combined with the 3-line stat dump this is what makes rows read as a building spreadsheet.

**Fix:** In _add_unit_card, replace `SpriteRegistry.get_building_sprite(bd.id, team)` with the unit's idle frame: `var frames := SpriteRegistry.get_unit_sprites(ud.id, 0 if is_kingdom else 1); if frames: var f := frames.get_frame_texture(&"idle", 0)`. Tiny Swords frames are 192x192 with the character only ~60px in the center, so crop to content before display: `var img := f.get_image(); var r := img.get_used_rect(); var at := AtlasTexture.new(); at.atlas = f; at.region = r` and assign `at` to the TextureRect (keep TEXTURE_FILTER_NEAREST and the 88px box). Optionally keep the building as a small 32px corner badge for build-cost context.

### [HIGH] readability — `scripts/ui/main_menu.gd:533`
**Issue:** Shop grid cells have no visible affordance or selected state. Unselected cell bg Color(0.18,0.15,0.1,0.7) blended over the (39,29,20) page computes to (44,35,24) — Δ≈6 RGB, invisible; the 1px 40%-alpha border disappears at 0.7x capture (sampled cell edge rows read exactly page bg 39,29,20). Pixel scan of the whole grid area (y215-640) finds ZERO gold-border pixels outside the yellow-avatar artwork itself, so the 'currently selected' 3px gold border is not rendering visibly either — avatars float in a void with no tap or selection feedback.

**Fix:** In _build_shop_tab cell styling (lines 533-543): raise unselected bg to Color(0.27,0.21,0.13,1.0) with border Color(0.55,0.42,0.22,0.9) width 2 (or better, StyleBoxTexture from assets/sprites/ui/ninepatch/slots.png). Add `style.set_content_margin_all(8)` on BOTH states so the expand_icon=true icon cannot paint over the 3px selected border. Add a hover/pressed stylebox. Then add a pixel detector for the selected cell's gold ring in tests/test_screen_layout.gd.

### [HIGH] hig — `scripts/ui/main_menu.gd:491`
**Issue:** Shop tab has zero price/buy affordances: no gold balance anywhere on the tab, no cost badges, no Owned/Equipped labels, no confirm step — tapping any avatar silently equips it. A tab labeled 'Shop' that sells nothing breaks expectation (Kingdom Rush/Clash Royale shops always show currency balance + per-item price plates) and the screen has no clear primary action.

**Fix:** In _build_shop_tab: (a) add a gold-balance chip at the panel top-right (reuse the trophy-chip pattern from the header, coin icon + PlayerData gold); (b) give each cell a footer strip — 'Equipped' on the current avatar, 'Free'/cost on others — as a small Label over a StyleBoxFlat chip (or ribbon_dark.png ninepatch) anchored to the cell bottom; (c) make the Daily Pick frames show a price/'Free today' tag so the featured section has purpose. If avatars stay free, retitle the tab section 'Avatars' and reserve Shop for future paid items.

### [MED] palette — `scripts/ui/main_menu.gd:1198`
**Issue:** Both tabs sit on a near-black brown void: shop page bg samples (39,29,20), army inter-card gaps (23,17,12) — well below the Tiny Swords warm wood/cream range and reading as unlit programmer background. The tab backdrop is a flat StyleBoxFlat Panel built at :1198-1199 while purpose-made Tiny Swords 9-patches (woodtable.png, regularpaper.png) sit unused in assets/sprites/ui/ninepatch/.

**Fix:** In the 'Coming soon panels' loop (lines 1194-1203), replace the flat Panel with a NinePatchRect: `var np := NinePatchRect.new(); np.texture = _load_texture("res://assets/sprites/ui/ninepatch/woodtable.png"); np.patch_margin_left/right/top/bottom = 24; np.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)` so Shop/Army/Social/Settings all get the warm wood-table backdrop in one change.

### [MED] cohesion — `scripts/ui/main_menu.gd:1755`
**Issue:** Army unit cards are flat rounded StyleBoxFlat navy boxes (measured 29,42,69 with 2px blue border, corner radius 10) — programmer-gray-style construction that clashes with the warm brown page, wood tab bar, and Tiny Swords kit. Cool navy appears nowhere else on either tab.

**Fix:** In _add_unit_card (lines 1754-1757): minimal fix — swap card bg to warm dark wood `Color(0.22,0.16,0.10,0.92)` with border `Color(0.55,0.42,0.22,0.8)` to match the header/tab-bar family, keeping Kingdom blue only as a 6px left-edge accent strip (small Panel child). Fuller fix — StyleBoxTexture from regularpaper.png with content margins 12 and dark-brown text recolor.

### [MED] readability — `scripts/ui/main_menu.gd:1808`
**Issue:** Army rows read as a spreadsheet: three dense abbreviation lines ('HP:100 DMG:10 SPD:2 RNG:1 ARM:3', 'Physical atk | Light armor', 'Skill: Shield Wall') at 15px design = ~10.5px capture (measured line height ~11px). All-caps colon-separated tokens are data-dump formatting; Kingdom Rush uses icons/short words. ROLE_COLORS is defined at :1688 but never used in the card — role is rendered as bracket text '[Melee]' inside the name string.

**Fix:** In _add_unit_card: merge lines 1807-1817 into one 16px line with middot separators ('HP 100 · DMG 10 · SPD 2 · RNG 1 · ARM 3'); drop ' [%s]' from name_lbl (line 1798) and instead add a small role chip — Label with StyleBoxFlat bg ROLE_COLORS[role_idx] (alpha 0.35, corner 6, content margins 6x2) placed in an HBox next to the name; render 'Physical / Light' as two similar chips instead of a text line.

### [LOW] hig — `scripts/ui/main_menu.gd:508`
**Issue:** Shop avatar grid is horizontally off-center: measured content spans x29-431 in the 504px capture — 22px gap on the left vs 66px on the right of the panel. Cause: 5 cols x 112px + 4 x 12px separation = 608px grid left-aligned inside the 660px-wide ScrollContainer placed at x=30.

**Fix:** Center the grid: change line 508-509 to `scroll.position = Vector2(56, 210); scroll.size = Vector2(608, 705)` (56 = (720-608)/2), or wrap the GridContainer in a CenterContainer with size_flags_horizontal = SIZE_EXPAND_FILL inside the scroll.

### [LOW] cohesion — `scripts/ui/main_menu.gd:1742`
**Issue:** Army tier headers ('TIER 1 — Basic Units') are bare 16px gold labels floating on the void between cards (measured text bbox y103-119, h=17px capture) — no panel/ribbon, weakest-styled elements on the screen despite being section landmarks. The Battle tab already establishes a ribbon language (ribbon_yellow.png at :1134).

**Fix:** In _build_army_tab (lines 1742-1749): wrap each tier header in a NinePatchRect using assets/sprites/ui/ninepatch/ribbon_dark.png (custom_minimum_size Vector2(320, 40), patch margins ~30 L/R) with the Label centered inside, matching the Battle tab's ribbon treatment.

### [LOW] cropped — `scripts/ui/main_menu.gd:1750`
**Issue:** Bottom army card is clipped flush against the tab bar: card navy visible to y=810, tab-bar border at y=812 (capture), with the Ballista card cut mid-stats and its '110g' price half-cropped. Normal scroll clipping, but there is no trailing spacer, so even fully scrolled the last card sits flush with zero breathing room.

**Fix:** In _build_army_tab, after the building loop (line 1750), append a trailing spacer: `var tail := Control.new(); tail.custom_minimum_size = Vector2(0, 24); vbox.add_child(tail)` (mirror of the existing top spacer at :1712-1714). Same fix applies to _build_social_tab's vbox.

**Strengths to preserve:**
- Text contrast is strong everywhere measured: army stat text 11.4:1, type line 8.5:1, skill line 9.9:1 against the navy card — no contrast failures, keep the dark-outline gold/cream typography
- Clear visual hierarchy inside army cards: 22px unit name + 22px right-aligned gold cost vs 15px detail lines — the name/cost pairing reads at a glance and should survive any restyle
- Tier grouping (TIER 1/2/3 headers sorted by tier) gives the roster a progression narrative — keep the grouping logic at main_menu.gd:1729-1750
- Shop touch targets meet HIG: 112px avatar buttons and 105px daily-pick frames in design space (>=80px requirement), with comfortable 12px grid separation
- Daily Pick featured panel is a good merchandising structure (deterministic day-seed rotation, centered 3-up row) — keep the mechanic, just add price/selected affordances
- No cropped or floating sprites on the shop tab; avatar art renders crisp with NEAREST filtering and nothing bleeds off panel bounds
- Consistent header (avatar + Commander + trophy chip) and bottom tab bar across both tabs, with a clearly readable selected-tab gold highlight

## Game HUD — grade C+

### [HIGH] readability — `scenes/ui/main_menu.tscn:692`
**Issue:** Inactive bottom-tab labels are nearly invisible: brightest label pixel (90,80,56) vs tab panel bg (38,28,15) = 2.1:1 contrast (needs 4.5:1). Measured at capture y=873 across Shop/Army/Social/Settings. Cause: font_color Color(0.7,0.65,0.55,0.7) (70% alpha) + font_size 13 (renders ~9px at capture scale) + icon modulate alpha 0.5. Navigation is the most-used surface on the screen and it reads as empty brown boxes.

**Fix:** In main_menu.tscn Tab0 label (line 692-693) and the duplicated Tab1-Tab4 label blocks: set theme_override_colors/font_color = Color(0.93,0.87,0.72,1.0), add font_outline_color = Color(0.1,0.07,0.03,1) with outline_size = 2, raise font_size 13 -> 16. Set Icon modulate (line 680 and siblings) from Color(1,1,1,0.5) to Color(1,1,1,0.85). This lifts label contrast to ~8:1 while the active-tab gold ring still differentiates selection.

### [HIGH] hierarchy — `scripts/ui/main_menu.gd:104`
**Issue:** Two competing CTAs on the battle tab (backlog 3.2): the yellow BATTLE ribbon (440x85 design px, y=795-880) and PLAY ONLINE (1v1) (320x70 design, y=1070-1140) both start a match. The ribbon is biggest/brightest but the online path is a dim dark-wood bar floating on green with no visual relationship to the ribbon — capture shows two disconnected buttons 130px apart. Kingdom Rush/Clash Royale have exactly ONE giant primary battle button.

**Fix:** In scripts/ui/main_menu.gd:104-117, make BATTLE the single primary CTA and demote online: either (a) move online into the existing game-mode selector as a '1v1 Online' mode so BATTLE launches whatever mode is selected, or (b) restyle online_btn as a compact secondary chip (ninepatch/ribbon_blue.png via the existing _apply_texture_bg helper at line 1077) anchored 24px directly below the ribbon (offset_top 900, offset_bottom 986) so it reads as a subordinate option of the same cluster, not a rival CTA.

### [HIGH] palette — `scripts/ui/main_menu.gd:690`
**Issue:** Main menu 'sky' is a flat green ColorRect Color(0.25,0.44,0.20) covering the whole frame — measured (52,92,42) at capture (100,150), (400,200), (30,400). White clouds render as dim blobs on a green wall, and the loading->menu transition flashes from blue-sky gradient to green wall. loading_screen.gd's own comment (lines 322-329) documents this exact defect as the reason the loading screen got a gradient — the fix was never ported to the menu.

**Fix:** In scripts/ui/main_menu.gd:689-694 replace the flat ColorRect with the same GradientTexture2D sky used in loading_screen.gd:330-352 (zenith blue 0.45,0.66,0.90 -> horizon haze 0.71,0.84,0.94 -> meadow feather -> deep green), with the blue-to-green transition placed just above the logo (~offset 0.30 given the tagline sits at y=130-260). Keeps both first-impression screens on one palette and makes the clouds read as clouds.

### [MED] cropped — `scripts/ui/loading_screen.gd:564`
**Issue:** The plateau island floats as a hard-cut slab on BOTH screens: edgescan at menu capture y=600 shows teal (29,109,125) jumping to grass (105,141,77) in a single pixel at x=66 (mirror at x=438) — no cliff-side tiles, no outline, no foam on the island's left/right ends (foam only runs along the bottom). The water itself is a full-width flat teal stripe (y=570-712 capture) with hard top and bottom edges against green, reading as a banner stripe rather than water. Both screens share the composition (loading_screen.gd _build_plateau, ported copy in main_menu.gd).

**Fix:** In loading_screen.gd:564-570 and main_menu.gd:871-874, use the Tilemap_color1 side-edge variants for the outer columns — col 0 gets the left-edge tiles (atlas x=320 at y=0/128/256) and col 10 the right-edge tiles (x=512) instead of interior x=384 (the 2026-04-22 'extra border' complaint was about using them on EVERY column; on the two end columns that baked-in side cliff is exactly the outline the island needs). Then wrap the foam line around the corners: add one extra foam blob per side at island_x - 24 and island_x + cols*ts - 96, rotated 90deg or reused as-is. For the water band's hard bottom edge, extend water.size.y so the plane runs behind the tip strip / PLAY ONLINE zone instead of terminating at a visible seam (design y=1014).

### [MED] hig — `scripts/ui/main_menu.gd:112`
**Issue:** PLAY ONLINE (1v1) touch target is 320x70 design px (offsets -160..160 / 980..1050; measured 46px tall in capture, y=750-796) — under the 80px design-space minimum for tappable controls. It is also the smallest, darkest element on the screen despite being the multiplayer entry point.

**Fix:** In scripts/ui/main_menu.gd:110-113 change online_btn offsets to offset_top = 972.0, offset_bottom = 1058.0 (86px tall) — or fold into the finding-2 restyle where the secondary chip keeps >=80px height. Keep the TouchArea child full-rect so the whole visual is tappable.

### [MED] cohesion — `scenes/ui/main_menu.tscn:622`
**Issue:** Header and tab bar are raw programmer boxes while the rest of the screen uses Tiny Swords art: HeaderBg is a flat ColorRect(0.12,0.1,0.08,0.9) (tscn:38-45), TabBarBg a flat ColorRect(0.14,0.11,0.08) (tscn:622-629), each tab a flat ColorRect(0.15,0.12,0.1,0.8) (tscn:658-665) — no wood texture, no bevel, corner treatment inconsistent with the ribbon/wood buttons. Also the '1500 Trophies' stat icon is icon_army (a shield, tscn:83) tinted gold — it reads as an army stat, not trophies.

**Fix:** Replace HeaderBg and TabBarBg ColorRects with NinePatchRects using assets/sprites/ui/ninepatch/woodtable.png (same _apply_texture_bg pattern main_menu.gd:1077 already uses for buttons); give each tab cell a subtle inset wood slot via ninepatch/slots.png instead of the per-tab ColorRect. Swap TrophyIcon texture to a trophy/laurel from the Icon_01..Icon_12 set (Icon_02 or Icon_07 — inspect with PIL first per lessons) keeping the gold modulate.

### [LOW] readability — `scripts/ui/main_menu.gd:1144`
**Issue:** BATTLE label is near-white (209,205,193) on the tan ribbon body (153,148,67) = ~2.0:1; legibility is carried entirely by the dark outline. At 28px+ it stays readable but looks washed against the yellow ribbon compared to Tiny Swords reference ribbons which use dark text.

**Fix:** In scripts/ui/main_menu.gd:1138-1148 switch the BATTLE label to dark brown Color(0.25,0.13,0.02) with a light 1px cream outline (Tiny Swords ribbon convention, ~7:1 vs tan), or keep white and raise outline_size to 5 so the effective glyph edge contrast dominates.

**Strengths to preserve:**
- Loading-screen sky gradient (blue zenith -> haze -> meadow) with drifting parallax clouds — do not regress when porting it to the menu
- Logo + knights vignette anchored above the castle with symmetric tree groves — composition is balanced and nothing is cropped at the viewport edges
- Wooden progress bar architecture (BigBar_Base caps + tiled rivet + red fill cropped to the trough) plus shine sweep — reads as genuine Tiny Swords kit
- Tip strip readability: cream text on dark wood measures 12.3:1 contrast with rotating gameplay tips
- Header text contrast is solid (Commander 8.7:1, trophy count 7.9:1, gold-on-dark palette)
- Active tab emphasis: +12px raise, gold ring, icon bounce — selection state is instantly clear (only the INACTIVE states fail)
- BATTLE ribbon uses the real ribbon_yellow 9-patch with pulse + shine sweep — the primary CTA has proper game-art treatment
- Tagline (28px, 3px dark outline) measures 4.28:1 on the green field — passes large-text contrast

## End screen — grade C+

### [HIGH] readability — `scripts/ui/hud.gd:101 (and BAR_W/BAR_H at hud.gd:13-14)`
**Issue:** Castle HP pill text is illegible — the single most important readout on screen. Labels render at font_size 12 with outline_size 3 on the 16px-native Pixel Operator Bold: 12/16 = 0.75x downscale corrupts glyphs and the 3px outline is thicker than the resulting strokes. In game_002.png the YOU pill (capture x285-386, y9-23, fill height only 12px) reads 'YOU 5888', and in game_011.png 'FOE 8' is a smudge. Numerals cannot be distinguished (5000 vs 9888). Also white-on-green fill contrast is 2.28:1 (measured (248,243,225) on (76,184,81)).

**Fix:** In scripts/ui/hud.gd: set label font_size to 16 (integer multiple of the pixel font) and outline_size to 2 at line 101-104; enlarge the pills to make room — BAR_W 150→176, BAR_H 22→32 at lines 13-14 (32px design = 22px capture, giving ~11px glyph height). Keep the dark trough behind the text (already good).

### [HIGH] readability — `scripts/ui/hud.gd:33-34; scenes/game/game_arena.tscn GoldBarLabel; scripts/ui/card_hand.gd:311,314,356,371-375,386,404,424-429`
**Issue:** Non-integer pixel-font sizes corrupt every HUD chrome label. Theme default is Pixel Operator Bold 16px; the HUD overrides to 18px (wave/gold labels), 18px (GoldBarLabel), and 12/13/14px (card_hand draw_string, castle-wrath button). 18/16 = 1.125x scaling makes 'Time 0:15' read as 'Tima 0:15' (capture x108-160, y8-22) and the gold bar '(+20/5s)' render as '<=20/5s>' (capture x160-215, y703-717). 'LOCKED' at 14px renders as 'LOCKCD' (locked card, capture x230-282, y833-843).

**Fix:** Quantize all HUD font sizes to 16 or 32: hud.gd:33-34 change add_theme_font_size_override("font_size", 18) → 16 (or drop the override so the theme's 16 applies); game_arena.tscn GoldBarLabel theme_override_font_sizes/font_size = 18 → 16; card_hand.gd replace all draw_string size-12/14 args with 16 (card is 84-88px wide, 16px fits with the existing _fit_text/_wrap_two_lines machinery); game_arena.gd:1005 castle-wrath font_size 13 → 16.

### [HIGH] hig — `scripts/game/game_arena.gd:1097 (ability), game_arena.gd:982 (castle wrath)`
**Issue:** Ability buttons are 64x38 design px (=45x27 capture) — under half the 88px target mandated by backlog 3.4 and below Apple's 44pt floor; these are combat-critical, time-sensitive taps. The Castle Wrath button is 150x52 (height 52 < 88). Neither appears in these captures (no special buildings built), but the sizes are hardcoded.

**Fix:** game_arena.gd:1097-1098 change _AbilityButton custom_minimum_size/size from Vector2(64, 38) to Vector2(88, 88) (square, icon + mana ring like Kingdom Rush hero powers); game_arena.gd:982 Castle Wrath custom_minimum_size Vector2(150, 52) → Vector2(150, 88) and move position (game_arena.gd:983) up to keep clear of GoldBarBg at y=990.

### [HIGH] hierarchy — `scripts/game/game_arena.gd:1312 (fill deletion) and :810 (_update_gold_bar)`
**Issue:** Gold bar is text-only — the elixir-style fill + cheapest-card marker specced in backlog 3.3 is absent. The scene's GoldBarFill/GoldBarTrack nodes are actively deleted at runtime (game_arena.gd:1312-1315) and card_hand.get_cheapest_cost() (T-050, card_hand.gd:134) has zero callers. Players must read tiny corrupted text ('20g <=20/5s>', yellow (255,230,89) on mottled red ribbon = 2.99-3.78:1 contrast) to know if they can afford anything; Clash Royale/Kingdom Rush communicate this with a glanceable meter.

**Fix:** Rebuild the fill inside the gold ribbon using existing assets: assets/sprites/ui/assembled/bigbar_base.png + bigbar_fill.png as StyleBoxTexture/NinePatchRect (e.g. x=ribbon_inset+140..720-ribbon_inset, h=24) in the ribbon-styling block at game_arena.gd:1317-1340; in _update_gold_bar (game_arena.gd:810) set fill ratio = clamp(gold / max(cheapest*2, 100)) and draw a 2px cream marker line at card_hand.get_cheapest_cost() position; keep '%dg' text left of the bar at font_size 16.

### [MED] cohesion — `scripts/ui/card_hand.gd:233-259 (_create_styles)`
**Issue:** Building cards are flat programmer-style StyleBoxFlat rounded rects (bg (89,71,46), 2px border, 10px corner radius) while the tray beneath them is a textured Tiny Swords wood table with metal corner brackets — the cards read as placeholder UI sitting on production furniture. Measured card at capture x37-98, y742-810: uniform flat fill, no texture, unlike every panel in Kingdom Rush's build bar.

**Fix:** In card_hand.gd _create_styles (line 233), replace the three StyleBoxFlat card styles with StyleBoxTexture instances built from res://assets/sprites/ui/assembled/slots.png or regularpaper.png (set texture_margin to the 9-patch insets, draw_style_box already takes any StyleBox at line 286). Keep the gold pulse border for selection by layering the existing selected StyleBoxFlat border on top.

### [MED] cohesion — `scripts/ui/hud.gd:72-95 (_make_hp_bar), hud.gd:58 (en_x margin)`
**Issue:** Castle HP pills are flat vector capsules (StyleBoxFlat, 4-5px corner radius, pure saturated green (76,184,81) / red (209,71,56)) floating on the hand-painted pixel ribbon — two rendering languages in one 48px strip. The FOE pill also ends 8px from the screen edge (en_x = 720-8-150, capture x498/504) and its right half sits on the ribbon's darker folded tail, reading as an overlap accident (capture x460-490, y9-23).

**Fix:** In hud.gd _make_hp_bar (line 72), swap the trough/fill StyleBoxFlat for StyleBoxTexture using assets/sprites/ui/assembled/bigbar_base.png / bigbar_fill.png (tint fill green/red via modulate with Tiny Swords banner colors, e.g. blue faction (58,124,165) / red (166,72,54)); in _build_hp_bars (line 58) increase the right margin from 8.0 to 24.0 so the pill clears the ribbon tail fold and screen edge.

### [MED] palette — `scenes/game/game_arena.tscn:172-180 (HUDBg color)`
**Issue:** HUDBg ColorRect Color(0.12, 0.08, 0.04, 0.92) renders as a near-black (34,32,23) full-width slab behind the top ribbon — visible above/below the ribbon tails and at both top corners (capture x0-30 and x475-503, y0-33 sampled uniformly (34,32,23)). This is exactly the 'near-black void' the palette rule bans, and it makes the top strip look unfinished next to the teal water.

**Fix:** Either make HUDBg fully transparent and let the ribbon carry the strip (ribbon already spans FULL_RECT), or set it to the tray's warm dark wood (0.24, 0.17, 0.10, 0.95) so the corners read as wood beam, in game_arena.tscn HUDBg color property (line ~180); alternatively override it in the ribbon-styling block at game_arena.gd:1361-1377.

### [MED] hig — `scripts/ui/card_hand.gd:12-14`
**Issue:** Card touch targets are 84px wide (CARD_W) with a 4px gap — under the 88px minimum from backlog 3.4. Measured in capture: cards ~59-61px wide (=84-87 design) in two rows of 7. Adjacent-card mis-taps are likely at this size+gap on a phone.

**Fix:** card_hand.gd:12-14 set CARD_W = 88.0 and CARD_GAP = 6.0 — fits: 7 cards x 88 + 6 gaps x 6 = 652 <= available_w 672 (720 - 2x24 pad). Card height already ~97px design in the 2-row layout, which passes.

### [MED] cohesion — `scripts/ui/card_hand.gd:362-376 (_draw_full locked branch)`
**Issue:** Locked-card treatment is a 55% black overlay + red 'LOCKED' text (which renders corrupted as 'LOCKCD' at 14px, capture x230-282 y833-843) — backlog 3.3 specs grayscale icon + padlock instead. Three locked cards show near-black voids in the tray (icon under 0.5 gray tint + 0.55 black overlay is mud), and 'Need: Siege Works..' ellipsizes.

**Fix:** In card_hand.gd:362-376: drop the 'LOCKED' string; render the icon grayscale (draw_texture_rect tint Color(0.6,0.6,0.6) with a desaturating CanvasItem shader or pre-grayed duplicate), lighten the overlay to Color(0,0,0,0.35), and draw a 20px padlock glyph centered (simple 2-rect + arc draw, or a small PNG in assets/sprites/ui/) above the 'Need: <building>' line at font_size 16.

### [LOW] readability — `scripts/ui/card_hand.gd:396 (type_col tower), :402 (spawner)`
**Issue:** 'Tower' type label color (0.8, 0.5, 0.45) = (204,127,115) on the card's inner panel (115,97,71) measures 1.94:1 (2.9:1 vs outer bg) — far below the 4.5:1 body-text floor; 'Guard Tower / Tower' is the least legible card caption in the tray (capture x282-344, y795-805).

**Fix:** card_hand.gd:396 change the tower type_col to Color(1.0, 0.72, 0.62) (=(255,184,158), ~4.6:1 vs inner panel), and bump Spawner green (line 402) to Color(0.65, 0.85, 0.58) for margin (currently 4.17:1).

### [LOW] readability — `scripts/ui/card_hand.gd:431-434 (tier stars)`
**Issue:** Tier indicators are plain 3px-radius gold circles at the card's top-right (capture: two ~4px dots on Lancer Barracks/Siege Workshop at y~747) — at capture scale they read as stray noise pixels, not tier stars; no dark outline separates them from the card border.

**Fix:** card_hand.gd:431-434: draw 5px-radius circles with a 1px dark rim (draw_circle radius 6 in Color(0.3,0.2,0.05) underneath radius 5 gold), or replace with a tiny 12px star texture; space at 14px intervals so tiers I-III stay distinct.

**Strengths to preserve:**
- Full-width Tiny Swords red ribbon 9-patches on both the top HUD bar and the gold bar (game_arena.gd:1288-1376) — pointed ends render uncropped, tiling is clean, and they instantly theme the chrome; keep this system.
- Card tray wood table (ninepatch/woodtable.png with corner brackets, game_arena.gd:1343-1360) reads as genuine Tiny Swords furniture and frames the hand well — the strongest cohesion element on screen.
- Gold cost badges: dark text on bright gold when affordable, bright gold on dark when disabled (card_hand.gd:335-356) — both states are high-contrast and read at capture scale ('50g', '150g' all legible).
- Battlefield framing is production-clean: no cropped sprites at arena edges, tree-line groves sit fully on grass, water border is native Tiny Swords teal (71,171,169) — do not disturb the terrain layer while fixing HUD.
- HP pill architecture (dark trough + tweened fill + green=you/red=foe coding, hud.gd:56-152) is the right design — only the skin (flat StyleBox) and the 12px text need replacing, not the structure.
- Card text overflow machinery (_fit_text/_wrap_two_lines, 12px floor, two-line names) prevents any clipped or overlapping labels in the tray — every card name fits its panel.
