# Sprite Asset Pipeline

## How to Add Unit Sprites

1. **Draw** in Aseprite (or any tool) at **48x48px** per frame
2. **Create animations**: idle (3-4 frames), walk (4-6), attack (3-5), death (3-4)
3. **Export** as horizontal strip PNG (e.g., `footman_idle.png`)
4. **Create SpriteFrames** resource in Godot editor:
   - Right-click `assets/sprites/units/` -> New Resource -> SpriteFrames
   - Name it same as unit_type (e.g., `footman.tres`)
   - Add animations named: `idle`, `walk`, `attack`, `cast`, `death`
   - Import sprite strips into each animation
5. **Done** -- SpriteRegistry auto-scans and loads them

## File Structure
```
assets/sprites/
  units/
    footman.tres      <- SpriteFrames resource
    footman_idle.png   <- sprite strip
    footman_walk.png
    footman_attack.png
    archer.tres
    archer_idle.png
    ...
  buildings/
    barracks.png       <- Single texture, will replace _draw()
    archer_range.png
    ...
```

## Unit Types (need sprites for)
Kingdom: footman, archer, priest, knight, catapult
Horde: grunt, axe_thrower, wardrummer, berserker, demolisher

## Animation Names (expected by code)
- `idle` - breathing/bobbing, 3-4 frames, looped
- `walk` - marching, 4-6 frames, looped
- `attack` - weapon swing, 3-5 frames, NOT looped
- `cast` - magic/heal channel, 3-4 frames, NOT looped
- `death` - falling/poof, 3-4 frames, NOT looped

## Style Guide (Kingdom Rush reference)
- Head = 40-50% of total height
- 2px black outline (#1A1A1F) on everything
- 4-6 colors per unit, high saturation
- Facing RIGHT by default (code flips for left)
- Drop shadow not needed (code adds team ring)
