@tool
class_name MDSOpenLayouts
extends RefCounted
## Rooms that aren't caves, for Generate cave's "outdoor" and "arena" styles (see
## [constant MDSCaveShapes.STYLES]):
## - **Outdoor**: an open world's surface. Open sky above rolling ground (hills, slopes, the odd
##   pit to jump), floating ledges to climb, no ceiling, and its sides open where another room
##   goes on beside it. The ground follows the world's columns, so rooms side by side meet at the
##   same height, and their edges meet halfway between rooms of different heights.
## - **Arena**: a fight room. A flat floor, walls and a ceiling, and platforms in tiers, the
##   same on both sides.
## Generate cave then opens the gates and joins them as for any cave (see
## [method MDSRoomPainter.generate_cave]).
## [codeblock]
## painter.generate_cave(world, "Plains_01", 7, 0, 0, {}, {"cave": {"style": "outdoor"}})
## [/codeblock]

## Rows of the room's height the ground stands at, from its top.
const GROUND := 0.72
## How far the hills rise and fall, a share of the room's height.
const HILLS := 0.14

## The rock of an outdoor room (cells of the room's Terrain layer): the ground under the sky,
## floating ledges. [param inside]: the room's cells, in its box [param lo] to [param hi];
## [param origin]: the room's place in the world, in cells (world column = cell.x + origin.x);
## [param sides]: which edges another room goes on beyond ({"left": [rows open], "right": ...},
## see [method open_sides]); [param gates]: [{cell, side}] (the ground drops away under a gate
## in the floor, and meets a side gate at its doorstep); [param tall]: the player's height,
## [param reach]: how high it climbs (tiles). [param area_seed] shapes the hills (one per area,
## so rooms of an area meet), [param rng] the rest.
static func outdoor(inside: Dictionary, lo: Vector2i, hi: Vector2i, origin: Vector2i, sides: Dictionary, gates: Array, rng: RandomNumberGenerator, area_seed: int, tall := 4, reach := 6, neighbours: Dictionary = {}) -> Dictionary:
	var solid: Dictionary = {}
	var height := hi.y - lo.y + 1
	var hills := FastNoiseLite.new()
	hills.seed = area_seed
	hills.frequency = 0.035
	hills.fractal_octaves = 2
	# A room's own, gentler: gone at the edges another room meets.
	var own := FastNoiseLite.new()
	own.seed = rng.randi()
	own.frequency = 0.08
	var top_limit := lo.y + tall + 3
	var bottom_limit := hi.y - 2
	var base := float(lo.y) + height * GROUND
	var surface: Dictionary = {}
	for x in range(lo.x, hi.x + 1):
		var wx := x + origin.x
		var t := float(x - lo.x) / maxf(1.0, hi.x - lo.x)
		# Toward an edge with a room beyond, the ground heads for where the two rooms' grounds
		# meet: halfway between them, the same from both sides.
		var y := base
		for side in ["left", "right"]:
			if not neighbours.has(side):
				continue
			var k := t if side == "right" else 1.0 - t
			var pull := smoothstep(0.55, 1.0, k)
			y = lerpf(y, (base + float(neighbours[side])) * 0.5, pull)
		var fade := 1.0
		for side in ["left", "right"]:
			if neighbours.has(side):
				fade = minf(fade, (1.0 - t) * 6.0 if side == "right" else t * 6.0)
		y += hills.get_noise_1d(wx) * height * HILLS + own.get_noise_1d(wx) * height * 0.05 * clampf(fade, 0.0, 1.0)
		surface[x] = clampi(roundi(y), top_limit, bottom_limit)
	# Side gates: the ground meets their doorstep.
	for g: Dictionary in gates:
		var side := str(g.side)
		if side != "left" and side != "right":
			continue
		var c: Vector2i = g.cell
		var step := c.y + 2
		var x0 := c.x
		var dir := 1 if side == "left" else -1
		for k in 14:
			var x := x0 + dir * k
			if not surface.has(x):
				break
			var w := smoothstep(0.0, 1.0, k / 13.0)
			surface[x] = roundi(lerpf(step, surface[x], w))
	# No step up higher than the player climbs; gentle slopes.
	for x in range(lo.x + 1, hi.x + 1):
		surface[x] = clampi(surface[x], surface[x - 1] - 2, surface[x - 1] + 3)
	for x in range(hi.x - 1, lo.x - 1, -1):
		surface[x] = clampi(surface[x], surface[x + 1] - 2, surface[x + 1] + 3)
	# The odd pit to jump: not near the edges or the gates, shallow enough to climb out of.
	var pits := (hi.x - lo.x) / 40
	for i in pits:
		var w := rng.randi_range(3, 5)
		var x0 := rng.randi_range(lo.x + 10, maxi(lo.x + 10, hi.x - 10 - w))
		var near_gate := gates.any(func(g: Dictionary) -> bool: return absi(g.cell.x - x0) < 10)
		if near_gate:
			continue
		var depth := mini(reach - 1, bottom_limit - surface[x0])
		for x in range(x0, x0 + w):
			surface[x] = mini(surface[x] + depth, bottom_limit)
	for x in range(lo.x, hi.x + 1):
		for y in range(surface[x], hi.y + 1):
			solid[Vector2i(x, y)] = true
	# A gate in the floor: the ground drops away under it.
	for g: Dictionary in gates:
		if str(g.side) != "bot":
			continue
		var c: Vector2i = g.cell
		for x in range(c.x - 2, c.x + 2):
			for y in range(int(surface.get(x, hi.y)) - 1, hi.y + 1):
				solid.erase(Vector2i(x, y))
	# Floating ledges, a jump above the ground, and more above them in a tall room.
	var ledges := maxi(1, (hi.x - lo.x) / 22)
	for i in ledges:
		var w := rng.randi_range(4, 7)
		var x0 := rng.randi_range(lo.x + 3, maxi(lo.x + 3, hi.x - 3 - w))
		var ground := hi.y
		for x in range(x0, x0 + w):
			ground = mini(ground, int(surface.get(x, hi.y)))
		var y := ground - rng.randi_range(maxi(tall + 1, reach - 2), reach)
		while y > top_limit:
			if _clear(solid, x0 - 1, x0 + w, y - tall - 1, y + tall):
				for x in range(x0, x0 + w):
					solid[Vector2i(x, y)] = true
			y -= reach
			x0 = clampi(x0 + rng.randi_range(-6, 6), lo.x + 3, maxi(lo.x + 3, hi.x - 3 - w))
			if rng.randf() < 0.5:
				break
	_edges(solid, inside, lo, hi, sides, false)
	return solid

## The rock of an arena (see [method outdoor] for the parameters): a flat floor three tiles
## thick, walls and a ceiling two thick, and platforms in tiers a jump apart, mirrored about the
## middle, with room under each for the player.
static func arena(inside: Dictionary, lo: Vector2i, hi: Vector2i, sides: Dictionary, gates: Array, rng: RandomNumberGenerator, tall := 4, reach := 6) -> Dictionary:
	var solid: Dictionary = {}
	var floor_y := hi.y - 2
	for x in range(lo.x, hi.x + 1):
		for y in range(floor_y, hi.y + 1):
			solid[Vector2i(x, y)] = true
	var width := hi.x - lo.x + 1
	var mid := (lo.x + hi.x) / 2.0
	var y := floor_y - maxi(tall + 1, reach - 1)
	var tier := 0
	while y > lo.y + tall + 3:
		var w := rng.randi_range(4, 7)
		# Out from the middle, farther each tier: a staircase up both sides.
		var off := width * (0.32 if tier % 2 == 0 else 0.12) + rng.randi_range(-2, 2)
		for s in [-1, 1]:
			var x0 := roundi(mid + s * off - w / 2.0)
			for x in range(x0, x0 + w):
				if x > lo.x + 2 and x < hi.x - 2:
					solid[Vector2i(x, y)] = true
		y -= maxi(tall + 1, reach - 1)
		tier += 1
	# A high one in the middle (for a boss to stand on, or the player to fight from).
	if tier >= 2 and rng.randf() < 0.7:
		var w := rng.randi_range(5, 8)
		var top := y + maxi(tall + 1, reach - 1)
		for x in range(roundi(mid - w / 2.0), roundi(mid + w / 2.0)):
			if _clear(solid, x, x, top - tall - 1, top - 1):
				solid[Vector2i(x, top)] = true
	_edges(solid, inside, lo, hi, sides, true)
	return solid

## Which edges of room [param id] another room goes on beyond, on its layer: {"left": rows,
## "right": rows, "top": columns} (cells of the room's Terrain layer, open there). [param cell]:
## the size of a cell (px), [param lo] and [param hi] the room's box in cells.
static func open_sides(world: MDSWorld, id: String, lo: Vector2i, hi: Vector2i, cell: Vector2) -> Dictionary:
	var out := {"left": [], "right": [], "top": []}
	var origin := world.get_origin(id)
	var layer := world.get_room_layer(id)
	var at := func(c: Vector2i) -> bool:
		var other := world.room_at(origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell, layer)
		return not other.is_empty() and other != id
	for y in range(lo.y, hi.y + 1):
		if at.call(Vector2i(lo.x - 1, y)):
			out.left.append(y)
		if at.call(Vector2i(hi.x + 1, y)):
			out.right.append(y)
	for x in range(lo.x, hi.x + 1):
		if at.call(Vector2i(x, lo.y - 1)):
			out.top.append(x)
	return out

## Where the ground of the rooms beyond room [param id]'s sides stands (world rows, in cells:
## at [constant GROUND] of each's height): {"left": row, "right": row}, for the sides another
## room is beyond (see [method open_sides]).
static func neighbour_ground(world: MDSWorld, id: String, sides: Dictionary, lo: Vector2i, hi: Vector2i, cell: Vector2) -> Dictionary:
	var out: Dictionary = {}
	var origin := world.get_origin(id)
	var layer := world.get_room_layer(id)
	for side in ["left", "right"]:
		var rows: Array = sides.get(side, [])
		if rows.is_empty():
			continue
		var x := lo.x - 1 if side == "left" else hi.x + 1
		var other := world.room_at(origin + (Vector2(x, rows[rows.size() / 2]) + Vector2(0.5, 0.5)) * cell, layer)
		if other.is_empty():
			continue
		var b := world.get_room_bounds(other)
		# In this room's rows.
		out[side] = (b.position.y - origin.y) / cell.y + b.size.y / cell.y * GROUND
	return out

## The room's edges: rock outside its shape, walls (two thick) on the sides no room goes on
## beyond, and with [param ceiling] a ceiling where none is above. [param sides] see
## [method open_sides].
static func _edges(solid: Dictionary, inside: Dictionary, lo: Vector2i, hi: Vector2i, sides: Dictionary, ceiling: bool) -> void:
	var left: Array = sides.get("left", [])
	var right: Array = sides.get("right", [])
	var top: Array = sides.get("top", [])
	for y in range(lo.y, hi.y + 1):
		for k in 2:
			if not left.has(y):
				solid[Vector2i(lo.x + k, y)] = true
			if not right.has(y):
				solid[Vector2i(hi.x - k, y)] = true
	if ceiling:
		for x in range(lo.x, hi.x + 1):
			if not top.has(x):
				solid[Vector2i(x, lo.y)] = true
				solid[Vector2i(x, lo.y + 1)] = true
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if not inside.has(Vector2i(x, y)):
				solid[Vector2i(x, y)] = true

## Whether no rock is in columns [param x0] to [param x1], rows [param y0] to [param y1].
static func _clear(solid: Dictionary, x0: int, x1: int, y0: int, y1: int) -> bool:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if solid.has(Vector2i(x, y)):
				return false
	return true
