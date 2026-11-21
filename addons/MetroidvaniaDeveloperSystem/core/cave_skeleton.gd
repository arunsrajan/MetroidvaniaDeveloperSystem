@tool
class_name MDSCaveSkeleton
extends RefCounted
## Caves as a trunk and branches, carved out of solid rock: shafts (the trunks) crossing a few levels of
## horizontal passages (the branches), chambers and halls where they open out, chimneys, loops and pillars.
## Passage heights and shaft widths are drawn from a [MDSCaveProfile] (a lognormal through its passage-width
## quantiles) and swell and pinch along their length; floors are flat with ramps and steps, walls smooth. Where
## [MDSCaveShapes] strokes a letter template at one constant width, this builds each room from a short list of
## structures whose number, lengths and widths are drawn at random, so a seed changes the room's structure, not
## only its edges.
##
## [param cave] as for [method MDSCaveShapes.rock], with [code]shape: "skeleton"[/code] and
## - [code]profile[/code]: a profile dictionary, or the path of its JSON file (none: generic widths, no targets),
## - [code]tries[/code]: rooms made to find one inside the profile's targets (1: the first; the closest is kept),
## - [code]variance[/code]: 0 to 1, how far the draws stray from the typical (default 1),
## - [code]width[/code]: shaft width in tiles (0: from the profile), [code]style[/code]: "linear" (no ledges, the
##   shafts are for wall-climbing) or "cave" (ledges up the shafts, as [method MDSCaveShapes.ladders]; the profile's
##   ledge target is checked on the cave before they are added: they are the player's way up, not its look),
## - [code]version[/code]: reserved for the algorithm's version ([constant VERSION]). A later generator that changes
##   the rooms keeps this one under its number, so a seed written down today still gives today's room.

## The algorithm's version: bump it when a change would alter the room a seed gives, and keep the old branch in [method build].
const VERSION := 1
const DEFAULT_WIDTH := {"p10": 4.0, "p50": 7.0, "p90": 12.0}
## Rock left at the room's edge, cells.
const MARGIN := 2
## How far a floor may wander from its level (ramps and steps), rows.
const BAND := 4


static func wanted(cave: Dictionary) -> bool:
	return str(cave.get("shape", "")) == "skeleton"


## The rock of a skeleton cave in [param inside] (a room's cells, in its box [param lo] to [param hi]): every cell
## of the box but the cave's, as [method MDSCaveShapes.rock] returns it.
static func rock(inside: Dictionary, lo: Vector2i, hi: Vector2i, cave: Dictionary, rng: RandomNumberGenerator, tall := 4, step := 4) -> Dictionary:
	var size := hi - lo + Vector2i.ONE
	var w := size.x
	var h := size.y
	var profile := MDSCaveProfile.from_value(cave.get("profile", {}))
	var tries := clampi(int(cave.get("tries", 1)), 1, 64)
	var variance := clampf(float(cave.get("variance", 1.0)), 0.0, 1.0)
	var width := int(cave.get("width", 0))
	var parts: Dictionary = cave.get("parts", {})
	var best: Dictionary = {}
	var best_d := INF
	for t in tries:
		var sub := RandomNumberGenerator.new()
		sub.seed = rng.randi()
		var room := build(w, h, profile, sub, tall, variance, width)
		room.air = _inside_only(room.air, w, h, lo, inside, parts)
		var d := 0.0
		if not profile.is_empty():
			d = profile.distance(MDSCaveStats.measure(room.air, w, h, inside.size()))
		if d < best_d:
			best = room
			best_d = d
		if d <= 0.0:
			break
	var air: PackedByteArray = best.air
	var solid: Dictionary = {}
	for y in h:
		for x in w:
			if air[y * w + x] == 0:
				solid[lo + Vector2i(x, y)] = true
	if str(cave.get("style", "cave")) != "linear":
		var cells: Dictionary = {}
		for y in h:
			for x in w:
				if air[y * w + x] == 1:
					cells[lo + Vector2i(x, y)] = true
		var ups: Array = []
		for u: Array in best.uprights:
			ups.append([u[0] + lo, u[1] + lo, u[2]])
		for c in MDSCaveShapes.ladders(cells, ups, step):
			solid[c] = true
	return solid


## One room of [param w] x [param h] cells: {air (w * h bytes, 1 = open), uprights ([from, to, width], local cells)}.
@warning_ignore("integer_division")
static func build(w: int, h: int, profile: MDSCaveProfile, rng: RandomNumberGenerator, tall: int, variance: float, width_override := 0) -> Dictionary:
	var air := PackedByteArray()
	air.resize(w * h)
	var uprights: Array = []
	var min_h := tall + 1
	var wq := profile.quantiles("passage.width", DEFAULT_WIDTH)
	var p10 := maxf(float(wq.get("p10", 4.0)), 2.0)
	var p50 := maxf(float(wq.get("p50", 7.0)), p10 + 0.1)
	var p90 := maxf(float(wq.get("p90", 12.0)), p50 + 0.1)
	var mu := log(p50)
	var sigma := (log(p90) - log(p10)) / (2.0 * 1.2816) * (0.35 + 0.65 * variance)
	var g := exp(rng.randfn(0.04, 0.18 * variance))
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.05

	# Levels: the floors of the horizontal passages, lowest (0) first.
	var n_levels := clampi(roundi((float(h) - 12.0) / rng.randf_range(20.0, 30.0)), 1, 6)
	if n_levels > 1 and rng.randf() < 0.25 * variance:
		n_levels -= 1
	# Rock under the lowest floor, less in a short room (a screen tall has no rows to spare).
	var bottom := h - 1 - rng.randi_range(mini(5, maxi(3, h / 8)), mini(8, maxi(4, h / 5)))
	# How far a floor may wander from its level: less in a short room, where a ramp would eat the passage.
	var band := clampi(h / 10, 2, BAND)
	var spacing := float(bottom - 12) / float(n_levels)
	var floors := PackedInt32Array()
	for k in n_levels:
		floors.append(bottom - roundi(float(k) * spacing) + (rng.randi_range(-2, 2) if k > 0 else 0))
	# Each level's tallest passage: room for a slab of rock between it and the level above, floors wandering included.
	var caps := PackedInt32Array()
	var heights := PackedInt32Array()
	for k in n_levels:
		var cap := (floors[k] - floors[k + 1] - 2 * band - 4) if k + 1 < n_levels else (floors[k] - band - 4)
		cap = maxi(cap, min_h)
		caps.append(cap)
		heights.append(clampi(roundi(exp(rng.randfn(mu, sigma)) * g), min_h, cap))
	# Now and then one level is a hall: as tall as it can be, wide, with pillars.
	var hall := -1
	if rng.randf() < 0.30 * (0.3 + 0.7 * variance):
		var k := rng.randi_range(0, n_levels - 1)
		if caps[k] >= 12:
			hall = k
			heights[k] = maxi(min_h, roundi(float(caps[k]) * rng.randf_range(0.7, 0.95)))

	# Shafts: the trunk crosses every level, the others some of them; a twin makes a loop.
	var n_shafts := clampi(roundi(float(w) / rng.randf_range(55.0, 85.0)), 1, 3)
	if rng.randf() < 0.25 * variance:
		n_shafts = mini(n_shafts + 1, 4)
	var sx := PackedInt32Array()
	var sw := PackedInt32Array()
	var s_lo := PackedInt32Array()
	var s_hi := PackedInt32Array()
	for j in n_shafts:
		var cx := (float(j) + 0.5) / float(n_shafts) * float(w) + rng.randf_range(-0.10, 0.10) * float(w)
		sx.append(clampi(roundi(cx), 10, w - 11))
		var wd := width_override
		if wd <= 0:
			wd = roundi(exp(rng.randfn(mu - 0.1, sigma * 0.8)) * g)
		sw.append(clampi(wd, min_h, 16))
		var a := 0
		var b := n_levels - 1
		if j > 0 and n_levels > 1:
			a = rng.randi_range(0, n_levels - 1)
			b = rng.randi_range(0, n_levels - 1)
			if a > b:
				var swap := a
				a = b
				b = swap
			if a == b:
				if b < n_levels - 1:
					b += 1
				else:
					a -= 1
		s_lo.append(a)
		s_hi.append(b)
	if n_levels >= 2 and rng.randf() < 0.15 + 0.30 * variance:
		var tx := clampi(sx[0] + rng.randi_range(18, 36) * (1 if rng.randf() < 0.5 else -1), 10, w - 11)
		if absi(tx - sx[0]) >= 14:
			var k := rng.randi_range(0, n_levels - 2)
			sx.append(tx)
			sw.append(clampi(roundi(float(sw[0]) * 0.85), min_h, 16))
			s_lo.append(k)
			s_hi.append(k + 1)

	# Each level reaches from the shafts that cross it, out to the edge, part of the way, or not at all.
	var xa := PackedInt32Array()
	var xb := PackedInt32Array()
	for k in n_levels:
		var lo_x := w
		var hi_x := -1
		for j in sx.size():
			if s_lo[j] <= k and k <= s_hi[j]:
				lo_x = mini(lo_x, sx[j] - sw[j] / 2)
				hi_x = maxi(hi_x, sx[j] + sw[j] / 2)
		xa.append(_reach(rng, lo_x, -1, w))
		xb.append(_reach(rng, hi_x, 1, w))
		if k == hall and rng.randf() < 0.8:
			xa[k] = MARGIN + rng.randi_range(0, 10)
			xb[k] = w - 1 - MARGIN - rng.randi_range(0, 10)
	# A level is at least two-fifths of the room wide.
	var min_len := roundi(0.4 * float(w))
	for k in n_levels:
		var lack := min_len - (xb[k] - xa[k])
		if lack > 0:
			xa[k] = maxi(MARGIN, xa[k] - lack / 2)
			xb[k] = mini(w - 1 - MARGIN, xb[k] + lack - lack / 2)

	# The passages: floors flat but for ramps and steps, ceilings that swell, pinch and bump.
	var floor_rows: Array = []
	for k in n_levels:
		var fr := PackedInt32Array()
		fr.resize(w)
		fr.fill(-1)
		var base := floors[k]
		var f := base
		var x0 := xa[k]
		var x1 := xb[k]
		var swell := _swells(rng, x1 - x0 + 1, nz, rng.randf_range(0.0, 400.0), rng.randf_range(0.18, 0.45), 1.0 / 24.0)
		var ramp := 0
		var ramp_dir := 0
		for x in range(x0, x1 + 1):
			if ramp > 0:
				ramp -= 1
				if ramp % 3 == 0:
					f += ramp_dir
			elif rng.randf() < 0.014 * (0.5 + variance):
				ramp = rng.randi_range(3, 18)
				ramp_dir = 1 if rng.randf() < 0.5 else -1
			f = clampi(f, base - band, base + band)
			var hh := float(heights[k]) * swell[x - x0]
			var d_left := (x - x0) if x0 > MARGIN else 99
			var d_right := (x1 - x) if x1 < w - 1 - MARGIN else 99
			var to_end := mini(d_left, d_right)
			if to_end < 5:
				hh *= lerpf(0.55, 1.0, float(to_end) / 5.0)
			var rows := clampi(roundi(hh), min_h, caps[k])
			for y in range(f - rows + 1, f + 1):
				_dig(air, w, h, x, y)
			fr[x] = f
		floor_rows.append(fr)

	# The shafts, from the ceiling of the highest level they join to the floor of the lowest; on a single level a
	# chimney up from its ceiling instead. Some lean or curve.
	for j in sx.size():
		var y_top := floors[s_hi[j]] - heights[s_hi[j]] + 1
		var y_bot := floors[s_lo[j]]
		if s_hi[j] == s_lo[j]:
			y_top = maxi(y_top - rng.randi_range(6, 24), MARGIN + 2)
		var lean := 1.4 if rng.randf() < 0.6 else rng.randf_range(2.5, 6.0)
		var off := rng.randf_range(0.0, 400.0)
		var narrow := _swells(rng, y_bot - y_top + 1, nz, off + 33.0, 0.18, 1.0 / 40.0)
		for y in range(y_top, y_bot + 1):
			var cx := float(sx[j]) + lean * nz.get_noise_1d(float(y) * 0.5 + off)
			var half := maxf(float(sw[j]) * 0.5 * narrow[y - y_top], float(min_h) * 0.5)
			for x in range(roundi(cx - half), roundi(cx + half) + 1):
				_dig(air, w, h, x, y)
		uprights.append([Vector2i(sx[j], y_top), Vector2i(sx[j], y_bot), sw[j]])

	# Chambers: flat-floored domes where a passage opens out, often at its end.
	var n_ch := roundi(float(w * h) / 5500.0 * rng.randf_range(0.4, 1.6))
	for c in n_ch:
		var k := rng.randi_range(0, n_levels - 1)
		if xb[k] - xa[k] < 14:
			continue
		var rx := clampi(roundi(exp(rng.randfn(log(10.0), 0.3)) * g), 7, 22)
		var cx := rng.randi_range(xa[k] + 6, xb[k] - 6)
		if rng.randf() < 0.5:
			cx = clampi(xa[k] + roundi(float(rx) * 0.6) if rng.randf() < 0.5 else xb[k] - roundi(float(rx) * 0.6), xa[k] + 3, xb[k] - 3)
		var f: int = floor_rows[k][cx]
		if f < 0:
			continue
		var ry := clampi(roundi(float(rx) * rng.randf_range(0.5, 0.9)), min_h + 1, caps[k])
		var off := rng.randf_range(0.0, 400.0)
		for x in range(cx - rx, cx + rx + 1):
			var t := float(x - cx) / float(rx)
			var hh := float(ry) * sqrt(maxf(0.0, 1.0 - t * t)) * (1.0 + 0.15 * nz.get_noise_1d(float(x) * 1.7 + off))
			for y in range(f - roundi(hh) + 1, f + 1):
				_dig(air, w, h, x, y)

	# Chimneys: dead-end shafts up from a ceiling.
	for s in rng.randi_range(0, 2):
		var k := rng.randi_range(0, n_levels - 1)
		if xb[k] - xa[k] < 10:
			continue
		var x := rng.randi_range(xa[k] + 4, xb[k] - 4)
		var f: int = floor_rows[k][x]
		if f < 0:
			continue
		var ceil_y := f - heights[k] + 1
		var limit := (floors[k + 1] + band + 6) if k + 1 < n_levels else (MARGIN + 2)
		var y_top := maxi(ceil_y - rng.randi_range(5, 20), limit)
		var wd := clampi(roundi(float(sw[0]) * rng.randf_range(0.5, 0.9)), min_h, 10)
		var off := rng.randf_range(0.0, 400.0)
		for y in range(y_top, ceil_y + 2):
			var half := float(wd) * 0.5 * (1.0 + 0.1 * nz.get_noise_1d(float(y) * 0.8 + off))
			for xx in range(roundi(float(x) - half), roundi(float(x) + half) + 1):
				_dig(air, w, h, xx, y)

	# Pillars in the hall: rock rising from its floor, some to the ceiling (islands).
	if hall >= 0:
		for p in rng.randi_range(2, 5):
			var px := rng.randi_range(xa[hall] + 6, maxi(xa[hall] + 6, xb[hall] - 6))
			var pf: int = floor_rows[hall][px]
			if pf < 0:
				continue
			var pw := rng.randi_range(3, 7)
			var ph := roundi(float(heights[hall]) * rng.randf_range(0.35, 1.1))
			for y in range(pf - ph + 1, pf + 1):
				var t := float(pf - y) / float(maxi(ph, 1))
				var half := float(pw) * 0.5 * lerpf(1.0, 0.55, t)
				for x in range(roundi(float(px) - half), roundi(float(px) + half) + 1):
					if x >= MARGIN and x <= w - 1 - MARGIN and y >= MARGIN and y <= h - 1 - MARGIN:
						air[y * w + x] = 0

	air = _smooth(air, w, h, 1)
	return {"air": _largest(air, w, h), "uprights": uprights}


## Multipliers along [param n] cells of a passage or shaft: gentle swells from noise, small bumps, and a few
## wider bulges and narrow pinches (cosine windows), all around 1.
static func _swells(rng: RandomNumberGenerator, n: int, nz: FastNoiseLite, off: float, amp: float, events_per_cell: float) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(maxi(n, 1))
	for i in n:
		m[i] = 1.0 + amp * nz.get_noise_1d(float(i) + off) + 0.12 * nz.get_noise_1d(float(i) * 3.1 + off + 91.0)
	for e in roundi(float(n) * events_per_cell * rng.randf_range(0.5, 1.5)):
		var c := rng.randi_range(0, n - 1)
		var half := rng.randi_range(4, 12)
		var f := rng.randf_range(1.6, 2.6) if rng.randf() < 0.55 else rng.randf_range(0.0, 0.55)
		for i in range(maxi(0, c - half), mini(n, c + half + 1)):
			var t := 0.5 + 0.5 * cos(PI * float(i - c) / float(half))
			m[i] *= lerpf(1.0, f, t)
	return m


## How far a level runs on from [param x] in direction [param dir]: to the room's edge, part of the way, or not.
static func _reach(rng: RandomNumberGenerator, x: int, dir: int, w: int) -> int:
	var p := rng.randf()
	if p < 0.40:
		return MARGIN if dir < 0 else w - 1 - MARGIN
	if p < 0.85:
		return clampi(x + dir * rng.randi_range(5, maxi(6, roundi(0.6 * float(w)))), MARGIN, w - 1 - MARGIN)
	return clampi(x, MARGIN, w - 1 - MARGIN)


static func _dig(air: PackedByteArray, w: int, h: int, x: int, y: int) -> void:
	if x >= MARGIN and x <= w - 1 - MARGIN and y >= MARGIN and y <= h - 1 - MARGIN:
		air[y * w + x] = 1


## Rounds corners and drops one-cell specks: a cell goes open with five or more open neighbours of eight, closed
## with three or fewer.
static func _smooth(air: PackedByteArray, w: int, h: int, passes: int) -> PackedByteArray:
	var cur := air
	for p in passes:
		var nxt := cur.duplicate()
		for y in range(MARGIN, h - MARGIN):
			for x in range(MARGIN, w - MARGIN):
				var n := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx != 0 or dy != 0:
							n += cur[(y + dy) * w + x + dx]
				if n >= 5:
					nxt[y * w + x] = 1
				elif n <= 3:
					nxt[y * w + x] = 0
		cur = nxt
	return cur


## The biggest connected piece of each old room of a merged room ([param parts]: cell -> the part it is in), the rest dropped.
@warning_ignore("integer_division")
static func _largest_per_part(air: PackedByteArray, w: int, h: int, lo: Vector2i, parts: Dictionary) -> PackedByteArray:
	var n := w * h
	var label := PackedInt32Array()
	label.resize(n)
	var sizes: Array = [0]
	var part_of_label: Array = [-1]
	var next := 0
	var stack := PackedInt32Array()
	for i in n:
		if air[i] == 1 and label[i] == 0:
			next += 1
			var size := 0
			stack.clear()
			stack.append(i)
			label[i] = next
			while not stack.is_empty():
				var c: int = stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				size += 1
				var cx := c % w
				var cy := c / w
				if cx > 0 and air[c - 1] == 1 and label[c - 1] == 0:
					label[c - 1] = next
					stack.append(c - 1)
				if cx < w - 1 and air[c + 1] == 1 and label[c + 1] == 0:
					label[c + 1] = next
					stack.append(c + 1)
				if cy > 0 and air[c - w] == 1 and label[c - w] == 0:
					label[c - w] = next
					stack.append(c - w)
				if cy < h - 1 and air[c + w] == 1 and label[c + w] == 0:
					label[c + w] = next
					stack.append(c + w)
			sizes.append(size)
			part_of_label.append(int(parts.get(lo + Vector2i(i % w, i / w), -1)))
	var best: Dictionary = {}
	for l in range(1, next + 1):
		var part: int = part_of_label[l]
		if not best.has(part) or int(sizes[l]) > int(sizes[best[part]]):
			best[part] = l
	var keep: Dictionary = {}
	for part in best:
		keep[best[part]] = true
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		if label[i] != 0 and keep.has(label[i]):
			out[i] = 1
	return out


## Only the cells inside the room, and not at its edge, in its biggest connected piece (a merged room: walls where
## its old rooms met, and the biggest piece of each of them).
static func _inside_only(air: PackedByteArray, w: int, h: int, lo: Vector2i, inside: Dictionary, parts: Dictionary = {}) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			if air[y * w + x] == 0:
				continue
			var c := lo + Vector2i(x, y)
			if inside.has(c) and inside.has(c + Vector2i.LEFT) and inside.has(c + Vector2i.RIGHT) and inside.has(c + Vector2i.UP) and inside.has(c + Vector2i.DOWN):
				out[y * w + x] = 1
	if parts.is_empty():
		return _largest(out, w, h)
	# A cell next to a cell of another part is rock: a wall two cells thick where the rooms met.
	for c: Vector2i in parts:
		var part: int = parts[c]
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if int(parts.get(c + d, part)) != part:
				var local := c - lo
				if local.x >= 0 and local.y >= 0 and local.x < w and local.y < h:
					out[local.y * w + local.x] = 0
				break
	return _largest_per_part(out, w, h, lo, parts)


@warning_ignore("integer_division")
static func _largest(air: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var n := w * h
	var label := PackedInt32Array()
	label.resize(n)
	var best_id := 0
	var best_size := 0
	var next := 0
	var stack := PackedInt32Array()
	for i in n:
		if air[i] == 1 and label[i] == 0:
			next += 1
			var size := 0
			stack.clear()
			stack.append(i)
			label[i] = next
			while not stack.is_empty():
				var c: int = stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				size += 1
				var cx := c % w
				var cy := c / w
				if cx > 0 and air[c - 1] == 1 and label[c - 1] == 0:
					label[c - 1] = next
					stack.append(c - 1)
				if cx < w - 1 and air[c + 1] == 1 and label[c + 1] == 0:
					label[c + 1] = next
					stack.append(c + 1)
				if cy > 0 and air[c - w] == 1 and label[c - w] == 0:
					label[c - w] = next
					stack.append(c - w)
				if cy < h - 1 and air[c + w] == 1 and label[c + w] == 0:
					label[c + w] = next
					stack.append(c + w)
			if size > best_size:
				best_size = size
				best_id = next
	var out := PackedByteArray()
	out.resize(n)
	if best_id != 0:
		for i in n:
			if label[i] == best_id:
				out[i] = 1
	return out
