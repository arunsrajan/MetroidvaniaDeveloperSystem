@tool
class_name MDSCaveStats
extends RefCounted
## Shape statistics of a cave, the measurable half of an [MDSCaveProfile]: how open it is, how much floor and how
## many ledges per area, how thick its passages are and how much that varies. [param air] holds [code]w * h[/code]
## bytes, row by row, 1 = open and 0 = rock; one cell is one tile. [param area] is the number of cells of the room
## when they aren't all of the box (an L, T or curved room); 0 means all of them. The statistics that need a thinned
## skeleton (tunnel segments, width spread) aren't here.

## The keys [method measure] returns.
const KEYS := ["air_frac", "floor_per_100u2", "ledges_per_100u2", "thickness_p10", "thickness_p50", "thickness_p90", "thickness_spread"]


@warning_ignore("integer_division")
static func measure(air: PackedByteArray, w: int, h: int, area := 0) -> Dictionary:
	var n := w * h
	# The densities are per cell of the room: [param area] when it isn't the whole box.
	var total := maxf(1.0, float(area) if area > 0 else float(n))
	var open := 0
	for i in n:
		open += air[i]
	# Length of the run of open cells through each open cell, down its column and along its row.
	var vr := PackedInt32Array()
	vr.resize(n)
	var hr := PackedInt32Array()
	hr.resize(n)
	for x in w:
		var y := 0
		while y < h:
			if air[y * w + x] == 1:
				var s := y
				while y < h and air[y * w + x] == 1:
					y += 1
				for k in range(s, y):
					vr[k * w + x] = y - s
			else:
				y += 1
	for y in h:
		var x := 0
		while x < w:
			if air[y * w + x] == 1:
				var s := x
				while x < w and air[y * w + x] == 1:
					x += 1
				for k in range(s, x):
					hr[y * w + k] = x - s
			else:
				x += 1
	var thick := PackedInt32Array()
	for i in n:
		if air[i] == 1:
			thick.append(mini(vr[i], hr[i]))
	thick.sort()
	# Floors: an open cell with rock directly below. Thin ones (a slab of 2 or less below) make ledges when
	# they join, 8-connected, into a run 2 to 12 cells wide.
	var floors := 0
	var thin := PackedByteArray()
	thin.resize(n)
	for x in w:
		var y := 0
		while y < h:
			if air[y * w + x] == 0:
				var s := y
				while y < h and air[y * w + x] == 0:
					y += 1
				if s > 0:
					floors += 1
					if y - s <= 2:
						thin[(s - 1) * w + x] = 1
			else:
				y += 1
	var seen := PackedByteArray()
	seen.resize(n)
	var ledges := 0
	var stack := PackedInt32Array()
	for i in n:
		if thin[i] == 1 and seen[i] == 0:
			seen[i] = 1
			stack.clear()
			stack.append(i)
			var minx := w
			var maxx := -1
			while not stack.is_empty():
				var c: int = stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				var cx := c % w
				var cy := c / w
				minx = mini(minx, cx)
				maxx = maxi(maxx, cx)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := cx + dx
						var ny := cy + dy
						if (dx != 0 or dy != 0) and nx >= 0 and nx < w and ny >= 0 and ny < h:
							var j := ny * w + nx
							if thin[j] == 1 and seen[j] == 0:
								seen[j] = 1
								stack.append(j)
			var ext := maxx - minx + 1
			if ext >= 2 and ext <= 12:
				ledges += 1
	var t10 := _percentile(thick, 0.1)
	var t50 := _percentile(thick, 0.5)
	return {
		"air_frac": float(open) / total,
		"floor_per_100u2": float(floors) / total * 100.0,
		"ledges_per_100u2": float(ledges) / total * 100.0,
		"thickness_p10": t10,
		"thickness_p50": t50,
		"thickness_p90": _percentile(thick, 0.9),
		# How varied the passages' thickness is: a cheap stand-in for the skeleton's width spread.
		"thickness_spread": t50 / maxf(t10, 1.0),
	}


## Linear-interpolated percentile ([param q] 0 to 1) of an ascending array, like numpy's default.
static func _percentile(sorted: PackedInt32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	var pos := q * float(sorted.size() - 1)
	var a := int(floor(pos))
	var b := int(ceil(pos))
	return lerpf(float(sorted[a]), float(sorted[b]), pos - float(a))
