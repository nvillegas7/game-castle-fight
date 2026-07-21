## Pure card-face layout math for the full (vertical) building card — no node
## or autoload dependencies, so it is unit-testable headless
## (tests/test_card_layout.gd), same pattern as combat_tuning.gd.
##
## BUG-30 contract: the name renders BELOW the icon and INSIDE the card.
##   name top   (first baseline - ascent)  >= icon bottom + NAME_GAP
##   name bottom (last baseline + descent) <= h - BOTTOM_MARGIN
## The pre-fix code anchored draw_string's y — which is a BASELINE — at
## icon_bottom + 4, so the ~13px ascent rendered ACROSS the icon; and in the
## 2-row 90px layout a 44px icon + two 18px lines (106px total) ran off the
## card bottom ("Gryphon Roost" clipped mid-glyph). Fit order here: drop to
## one ellipsized line first, then shrink the icon; the name never moves up
## into the icon and never crosses the card bottom.
class_name CardLayout

const ICON_TOP: float = 22.0
const NAME_GAP: float = 4.0
const LINE_STEP: float = 18.0
# 6px: glyph descent + antialiasing tail must clear the pixel detector's
# bottom-3-capture-rows zone (4.3 design px at the 0.7x capture scale) —
# 3px left descender tips grazing it (measured 2026-07-21, 1-4 px/card).
const BOTTOM_MARGIN: float = 6.0


## w/h: card size. tex_w/tex_h: icon texture size (0 = no icon).
## want_lines: wrapped name line count (1-2). ascent/descent: font metrics px.
## Returns:
##   icon: Rect2 (zero-size if no icon)
##   lines: int — line count that fits (may be < want_lines)
##   baselines: Array[float] — draw_string y per name line
##   type_y: float — baseline for the type word, or -1.0 if it doesn't fit
##     (the tall 1-row card reserves its stats row at h-6, see below)
static func layout(w: float, h: float, tex_w: float, tex_h: float,
		want_lines: int, ascent: float, descent: float) -> Dictionary:
	var lines: int = clampi(want_lines, 1, 2)
	var icon_bottom: float = 24.0
	var iw: float = 0.0
	var ih: float = 0.0
	if tex_w > 0.0 and tex_h > 0.0:
		var icon_size: float = minf(w * 0.52, 44.0)
		var icon_scale: float = icon_size / maxf(tex_w, tex_h)
		iw = tex_w * icon_scale
		ih = tex_h * icon_scale

	var name_bottom_max: float = h - BOTTOM_MARGIN
	var block: float = ascent + (lines - 1) * LINE_STEP + descent
	if ih > 0.0 and ICON_TOP + ih + NAME_GAP + block > name_bottom_max and lines == 2:
		lines = 1
		block = ascent + descent
	if ih > 0.0 and ICON_TOP + ih + NAME_GAP + block > name_bottom_max:
		# Even one line is tight — shrink the icon to make room.
		var ih_fit: float = maxf(name_bottom_max - block - NAME_GAP - ICON_TOP, 8.0)
		iw = iw * ih_fit / ih
		ih = ih_fit
	if ih > 0.0:
		icon_bottom = ICON_TOP + ih

	var baselines: Array = []
	var first_baseline: float = icon_bottom + NAME_GAP + ascent
	for li in lines:
		baselines.append(first_baseline + li * LINE_STEP)

	# Type word goes below the name; the tall 1-row card (h >= 110) draws a
	# stats line at baseline h-6, so reserve that row.
	var type_bottom_max: float = (h - 24.0) if h >= 110.0 else name_bottom_max
	var type_y: float = float(baselines[lines - 1]) + LINE_STEP
	if type_y + descent > type_bottom_max:
		type_y = -1.0

	return {
		"icon": Rect2((w - iw) * 0.5, ICON_TOP, iw, ih),
		"lines": lines,
		"baselines": baselines,
		"type_y": type_y,
	}
