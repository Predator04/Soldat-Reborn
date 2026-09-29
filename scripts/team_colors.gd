extends RefCounted
## Team colours in one place (v1.23). Settings → Video "Colour-blind friendly
## teams" swaps the red team to orange (blue / orange reads for the common
## red-green colour blindness types). Soldiers pick theirs up when they spawn.

static func blue(bright := false) -> Color:
	return Color(0.4, 0.6, 1.0) if bright else Color(0.35, 0.55, 1.0)


static func red(bright := false) -> Color:
	if Settings.colorblind:
		return Color(1.0, 0.68, 0.18) if bright else Color(0.95, 0.58, 0.1)
	return Color(0.95, 0.35, 0.3) if bright else Color(0.85, 0.3, 0.25)


## 1 = blue, 2 = red; anything else gets `other`.
static func for_team(t: int, bright := false, other := Color(0.6, 0.6, 0.6)) -> Color:
	if t == 1:
		return blue(bright)
	if t == 2:
		return red(bright)
	return other
