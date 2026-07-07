# Tiny Swords UI Asset Usage Manifest

> Most Tiny Swords UI assets are multi-tile atlases with TRANSPARENT GAP ROWS/COLS between tiles — they are NOT standard 9-patch textures. Using `NinePatchRect` with `patch_margin = corner_size` stretches or tiles those gaps and produces visible artifacts.
>
> **Default rule**: if you're using one of the assets below for a panel/bar/frame and it has a 3×3 or N-piece structure, use `SpriteRegistry.make_tiled_panel_9(tex, regions, size)` — never naïve `NinePatchRect`.

## Atlas structure table

| Asset | Size | Structure | Gap behavior | Correct usage |
| --- | --- | --- | --- | --- |
| `BigBar_Base.png` | 320×64 | 3 opaque pieces: left cap x=40..63 + mid rivet x=128..191 + right cap x=256..279. y=9..59. | ~60px transparent gaps between pieces | Cap + tiled middle + cap via `AtlasTexture` + `STRETCH_TILE`. Fill drawn on top. |
| `BigBar_Fill.png` | 64×64 | Single contiguous strip, red with 3D shading, y=20..43 | None | Safe to use as `NinePatchRect` OR tile via `STRETCH_TILE` |
| `SpecialPaper.png` | 320×320 | 3×3 tile atlas. Corners ornamental gold, edges gold line, center dark panel. Rows y=20..63 / 128..191 / 256..298. Cols x=9..63 / 128..191 / 256..310. | Transparent rows/cols at y=64..127, 192..255; x=64..127, 192..255 | `make_tiled_panel_9(tex, SPECIAL_PAPER_REGIONS, size)` |
| `RegularPaper.png` | 320×320 | Same 3×3 pattern as SpecialPaper. Simpler brown parchment border. Rows y=20..63 / 128..191 / 256..300. Cols x=12..63 / 128..191 / 256..307. | Same gap pattern | `make_tiled_panel_9(tex, REGULAR_PAPER_REGIONS, size)` |
| `ribbon_blue.png`, `ribbon_red.png`, `ribbon_yellow.png`, etc. | varies | Single continuous ribbon with pointed ends and flat middle | None | `NinePatchRect` with `patch_margin_left/right ≈ pointed-tip width` (typically 97/98) and top/bottom=0 |
| `Banner.png` | varies | Single banner with pointed bottom | None | `NinePatchRect`, margins clip the pointed tip |
| `Icon_01..12.png` | small | Single-icon sprites | None | Use as `Texture2D` directly |
| `Avatars_01..20.png` | 72×72ish | Single portrait | None | Direct `Texture2D` |
| `BigBlueButton_Regular.png`, `BigRedButton_Regular.png` | varies | 3×3 atlas pattern (similar to paper) | Similar transparent gaps | Prefer `StyleBoxFlat` for buttons (cleaner); if atlas needed, use tile-compositor |

## Proper use pattern (multi-tile atlases)

```gdscript
# WRONG — produces broken/gapped output on multi-tile atlases:
var np := NinePatchRect.new()
np.texture = tex
np.patch_margin_left = 64 # etc — gap rows get stretched/tiled as visible artifacts

# RIGHT — uses the helper that stitches the 9 tiles with AtlasTexture crops:
var panel := SpriteRegistry.make_tiled_panel_9(
    tex,
    SpriteRegistry.SPECIAL_PAPER_REGIONS,   # or REGULAR_PAPER_REGIONS, or a custom dict
    Vector2(600, 90)                         # target display size
)
panel.position = Vector2(60, 1050)
add_child(panel)
```

The helper produces a `Control` container with 4 corner `TextureRect`s (fixed size) + 4 edge `TextureRect`s (tiled) + 1 center `TextureRect` (tiled). Every tile renders at its native pixel density; no transparent gap ever reaches the output.

## Historical bugs caused by ignoring this

- **BUG-43** (2026-04-18) — `BigBar_Base` rendered as 3 floating planks across 4 QA rounds. Root cause: tried to use as stretched NinePatch. Fixed by cap + `STRETCH_TILE` middle + cap.
- **BUG-44** (2026-04-18) — `RegularPaper` tip strip showed 4 thin horizontal lines. Root cause: NinePatch with margin=28 included transparent gap rows. Fixed by StyleBoxFlat replacement (before helper existed).
- **BUG-44 round 2** — `SpecialPaper` tip strip had transparent center with disconnected ornamental corners. Root cause: NinePatch stretch of gap rows/cols produces transparent center. Fixed by `make_tiled_panel_9` helper.

## When adding a new asset

Before using any Tiny Swords UI PNG in code:
1. Inspect its alpha channel (`python3 -c "from PIL import Image; img=Image.open('path.png'); print(img.getbbox()); a=img.split()[-1]; ..."`)
2. If any ROW or COLUMN inside the bbox is fully transparent → it's a multi-tile atlas → use `make_tiled_panel_9`.
3. If the full bbox is opaque → safe for NinePatchRect (set patch margins to the corner/cap width).
4. Add the asset to the table above.
