@tool
class_name MDSRoomHazards
extends RefCounted
## Hazards Generate cave places in a room of any style (a cave, a linear room, rooms, outdoor):
## - "spikes": a strip of spikes on a floor, two tiles wide, to jump over,
## - "pit": a hole two tiles deep dug into a floor, spikes at its bottom,
## - "gauntlet": a long floor spiked between stone pillars, crossed on their tops.
## They go on after the room's paths are made, never on a doorstep, a ledge or the ends of a
## corridor or a shaft. Each one is checked: when it would stop a gate or a chamber reaching the
## others and back (walking, jumping and falling, standing on spikes not counted: see
## [method MDSRoomPainter.climb_reach]), it is taken back. Generate cave turns them into
## [MDSHazard] nodes that put the player back on safe ground (see
## [method MDSRoomPainter.generate_cave]).
## [codeblock]
## painter.generate_cave(world, "Grotto", 7, 0, 0, {}, {"cave": {"shape": "skeleton", "hazards": "few"}})
## painter.generate_cave(world, "Keep", 7, 0, 0, {}, {"cave": {"style": "rooms", "hazards": "many", "hazard_kinds": ["spikes", "pit"]}})
## [/codeblock]

# l10n: text
## How many: [id, name].
const LEVELS := [["none", "None"], ["few", "Few"], ["some", "Some"], ["many", "Many"]]
## Hazards for each chamber of a rooms-style room (or each [constant CELLS_PER_PLACE] open cells
## of another style), by level.
const PER_PLACE := {"none": 0.0, "few": 0.6, "some": 1.2, "many": 2.0}
const CELLS_PER_PLACE := 240
# l10n: text
## The kinds: [id, name].
const KINDS := [["spikes", "Spikes"], ["pit", "Spiked pits"], ["gauntlet", "Gauntlets"]]
## How often each kind is tried.
const WEIGHTS := {"spikes": 5, "pit": 3, "gauntlet": 2}
## How far a player jumps across (as [method MDSRoomPainter.climb_reach]'s default).
const JUMP_W := 3
## Cells around a gate's end that stay clear.
const CLEAR := 5

## Whether [param cave] (Generate cave's "cave" fill) asks for hazards.
static func wanted(cave: Dictionary) -> bool:
	return float(PER_PLACE.get(str(cave.get("hazards", "none")), 0.0)) > 0.0

## The kinds [param cave] asks for (all of them when it names none).
static func kinds_of(cave: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for k in cave.get("hazard_kinds", []):
		if WEIGHTS.has(str(k)) and not out.has(str(k)):
			out.append(str(k))
	if out.is_empty():
		for k: Array in KINDS:
			out.append(k[0])
	return out

## Places the hazards [param cave] asks for in a room: [param solid] (its rock, changed in place:
## pits dug, pillars raised), [param inside] (its cells). [param anchors]: standing cells that
## must stay joined (a rooms-style room's chambers; none: some are picked across the room),
## [param ends]: the gates' ends ([method MDSRoomPainter.gate_end]), [param keep]: cells hazards
## stay off, [param places]: the chambers (0: from the room's size). Returns the hazards:
## [{kind, cells (the standing cells spiked, one row)}].
@warning_ignore("integer_division")
static func place(solid: Dictionary, inside: Dictionary, anchors: Array, ends: Array, keep: Dictionary, cave: Dictionary, rng: RandomNumberGenerator, reach: int, tall: int, places := 0, wall_climb := false) -> Array:
	var placed: Array = []
	var per := float(PER_PLACE.get(str(cave.get("hazards", "none")), 0.0))
	if per <= 0.0:
		return placed
	var open := _open(solid, inside)
	if open.is_empty():
		return placed
	var land := MDSRoomPainter.land_map(open)
	var marks := _anchors(open, land, anchors, ends, reach, wall_climb)
	if marks.is_empty():
		return placed
	if places <= 0:
		places = maxi(1, open.size() / CELLS_PER_PLACE)
	var want := roundi(per * places)
	var clear := keep.duplicate()
	for e: Dictionary in ends:
		_around(clear, e.cell, CLEAR)
		if e.has("mouth"):
			_around(clear, e.mouth, CLEAR)
	var kinds := kinds_of(cave)
	var deadly: Dictionary = {}
	var tries := 0
	while placed.size() < want and tries < want * 6:
		tries += 1
		var kind := _pick(kinds, rng)
		var h := _try(kind, solid, inside, open, clear, deadly, rng, tall)
		if h.is_empty():
			continue
		for c: Vector2i in h.cells:
			deadly[c] = true
		open = _open(solid, inside)
		land = MDSRoomPainter.land_map(open)
		# An anchor under the hazard moves beside it, on the same floor.
		var moved := moved_anchors(marks, deadly, open, solid)
		if not moved.is_empty() and joined(open, land, moved, ends, reach, deadly, wall_climb):
			marks = moved
			placed.append({"kind": kind, "cells": h.cells})
			for c: Vector2i in h.cells:
				_around(clear, c, 1)
		else:
			# It would cut a path: taken back.
			for c: Vector2i in h.cells:
				deadly.erase(c)
			for c: Vector2i in h.raised:
				solid.erase(c)
			for c: Vector2i in h.dug:
				solid[c] = true
			open = _open(solid, inside)
			land = MDSRoomPainter.land_map(open)
	return placed

## Whether every anchor (standing cells) and gate end in [param open] reaches the first anchor and
## is reached from it, [param deadly] standing cells not counted as ground.
static func joined(open: Dictionary, land: Dictionary, anchors: Array, ends: Array, reach: int, deadly: Dictionary = {}, wall_climb := false) -> bool:
	if anchors.is_empty() or not open.has(anchors[0]):
		return false
	var home: Vector2i = land[anchors[0]]
	if deadly.has(home):
		return false
	var from0 := MDSRoomPainter.climb_reach(open, anchors[0], reach, JUMP_W, land, wall_climb, deadly)
	var goal := {home: true}
	for a: Vector2i in anchors:
		if not open.has(a) or not from0.has(land[a]):
			return false
	for e: Dictionary in ends:
		if not MDSRoomPainter._arrives(from0, e, open, land, reach, wall_climb):
			return false
	for i in range(1, anchors.size()):
		if not MDSRoomPainter.climb_reach(open, anchors[i], reach, JUMP_W, land, wall_climb, deadly, goal).has(home):
			return false
	for e: Dictionary in ends:
		if open.has(e.cell) and not MDSRoomPainter.climb_reach(open, e.cell, reach, JUMP_W, land, wall_climb, deadly, goal).has(home):
			return false
	return true

## [param marks] with those [param deadly] moved to the nearest safe standing cell of their row
## (within eight cells); empty when one has none.
static func moved_anchors(marks: Array, deadly: Dictionary, open: Dictionary, solid: Dictionary) -> Array:
	var out: Array = []
	for m: Vector2i in marks:
		if not deadly.has(m) and open.has(m):
			out.append(m)
			continue
		var found := false
		for d in range(1, 9):
			for c: Vector2i in [m + Vector2i(-d, 0), m + Vector2i(d, 0)]:
				if not found and open.has(c) and solid.has(c + Vector2i.DOWN) and not deadly.has(c):
					out.append(c)
					found = true
		if not found:
			return []
	return out

static func _open(solid: Dictionary, inside: Dictionary) -> Dictionary:
	var open: Dictionary = {}
	for c in inside:
		if not solid.has(c):
			open[c] = true
	return open

static func _around(out: Dictionary, c: Vector2i, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			out[c + Vector2i(dx, dy)] = true

## The standing cells to keep joined: [param anchors] (where they still stand and are joined
## now), or some spread across the room, picked among those the first gate (or the room's first
## floor) reaches and is reached back from.
@warning_ignore("integer_division")
static func _anchors(open: Dictionary, land: Dictionary, anchors: Array, ends: Array, reach: int, wall_climb: bool) -> Array:
	var cells: Array = []
	for a: Vector2i in anchors:
		if open.has(a):
			cells.append(land[a])
	var start: Vector2i
	if not cells.is_empty():
		start = cells[0]
	else:
		var from := Vector2i.ZERO
		var found := false
		for e: Dictionary in ends:
			if open.has(e.cell):
				from = e.cell
				found = true
				break
		if not found:
			var keys := open.keys()
			keys.sort()
			if keys.is_empty():
				return []
			from = keys[keys.size() / 2]
		start = land[from]
	var from_start := MDSRoomPainter.climb_reach(open, start, reach, JUMP_W, land, wall_climb)
	var out: Array = [start]
	var goal := {start: true}
	if cells.is_empty():
		# Farthest-first across the floors the start reaches, up to six.
		var floors := from_start.keys()
		floors.sort()
		while out.size() < 6 and not floors.is_empty():
			var best: Vector2i = floors[0]
			var best_d := -1
			for f: Vector2i in floors:
				var d := 1 << 30
				for o: Vector2i in out:
					d = mini(d, absi(f.x - o.x) + absi(f.y - o.y))
				if d > best_d:
					best_d = d
					best = f
			if best_d < 8:
				break
			floors.erase(best)
			cells.append(best)
			out.append(best)
		out = [start]
	for c: Vector2i in cells:
		if c != start and from_start.has(c) and MDSRoomPainter.climb_reach(open, c, reach, JUMP_W, land, wall_climb, {}, goal).has(start):
			out.append(c)
	return out

static func _pick(kinds: PackedStringArray, rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in kinds:
		total += int(WEIGHTS[k])
	var r := rng.randi_range(1, maxi(1, total))
	for k in kinds:
		r -= int(WEIGHTS[k])
		if r <= 0:
			return k
	return kinds[0]

## Runs of standing cells (open, rock under them) along floors, left to right, at least
## [param min_len] long, none in [param clear] or already spiked.
static func _runs(open: Dictionary, solid: Dictionary, clear: Dictionary, deadly: Dictionary, min_len: int) -> Array:
	var stands: Array = []
	for c: Vector2i in open:
		if solid.has(c + Vector2i.DOWN) and not clear.has(c) and not clear.has(c + Vector2i.DOWN) and not deadly.has(c):
			stands.append(c)
	stands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var runs: Array = []
	var run: Array = []
	for c: Vector2i in stands:
		if not run.is_empty() and (c.y != run[-1].y or c.x != run[-1].x + 1):
			if run.size() >= min_len:
				runs.append(run)
			run = []
		run.append(c)
	if run.size() >= min_len:
		runs.append(run)
	return runs

## One hazard of [param kind] tried somewhere: {cells (standing cells spiked), dug (rock taken
## out), raised (rock added)}, applied to [param solid]; empty when there is no room for it.
static func _try(kind: String, solid: Dictionary, inside: Dictionary, open: Dictionary, clear: Dictionary, deadly: Dictionary, rng: RandomNumberGenerator, tall: int) -> Dictionary:
	match kind:
		"spikes":
			var runs := _runs(open, solid, clear, deadly, 6)
			if runs.is_empty():
				return {}
			var run: Array = runs[rng.randi_range(0, runs.size() - 1)]
			var n := JUMP_W - 1
			var i := rng.randi_range(1, run.size() - 1 - n)
			return {"cells": run.slice(i, i + n), "dug": [], "raised": []}
		"pit":
			var runs := _runs(open, solid, clear, deadly, 7)
			if runs.is_empty():
				return {}
			var run: Array = runs[rng.randi_range(0, runs.size() - 1)]
			var n := JUMP_W - 1
			var i := rng.randi_range(2, run.size() - 2 - n)
			var dug: Array = []
			var cells: Array = []
			for k in n:
				var c: Vector2i = run[i + k]
				for d in [1, 2]:
					var below := c + Vector2i(0, d)
					if not solid.has(below) or not inside.has(below):
						return {}
					dug.append(below)
				# Rock under the pit and beside it, so it holds.
				if not solid.has(c + Vector2i(0, 3)):
					return {}
				cells.append(c + Vector2i(0, 2))
			for d in [1, 2]:
				if not solid.has(run[i] + Vector2i(-1, d)) or not solid.has(run[i + n - 1] + Vector2i(1, d)):
					return {}
			for c: Vector2i in dug:
				solid.erase(c)
			return {"cells": cells, "dug": dug, "raised": []}
		"gauntlet":
			var runs := _runs(open, solid, clear, deadly, 10)
			if runs.is_empty():
				return {}
			var run: Array = runs[0]
			for r: Array in runs:
				if r.size() > run.size() or (r.size() == run.size() and rng.randf() < 0.5):
					run = r
			var y: int = run[0].y
			var x0: int = run[1].x
			var x1: int = run[-2].x
			# Room above it to jump from the pillars' tops.
			for x in range(x0, x1 + 1):
				for yy in range(y - tall - 1, y):
					if not open.has(Vector2i(x, yy)):
						return {}
			var raised: Array = []
			var tops: Dictionary = {}
			var x := x0 + rng.randi_range(1, 2)
			var last := x0 - 1
			while x + 1 < x1:
				for bx in [x, x + 1]:
					raised.append(Vector2i(bx, y))
					raised.append(Vector2i(bx, y - 1))
					tops[bx] = true
				last = x + 1
				x += 4
			if raised.is_empty():
				return {}
			# The spikes end within a jump of the last pillar.
			x1 = mini(x1, last + 2)
			var cells: Array = []
			for cx in range(x0, x1 + 1):
				if not tops.has(cx):
					cells.append(Vector2i(cx, y))
			for c: Vector2i in raised:
				solid[c] = true
			return {"cells": cells, "dug": [], "raised": raised}
	return {}

## The cells of [param cells] in runs along their rows, left to right ([Vector2i] arrays), so one
## [MDSHazard] covers each.
static func strips(cells: Array) -> Array:
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for c: Vector2i in sorted:
		if not out.is_empty() and out[-1][-1].y == c.y and out[-1][-1].x == c.x - 1:
			out[-1].append(c)
		else:
			out.append([c])
	return out
