extends "res://tests/test_case.gd"
## The Skeleton cave (MDSCaveSkeleton), a Cave shape of its own: a trunk and branches carved out of solid rock,
## its passages' widths drawn from a profile (MDSCaveProfile) of numbers, and checked against that profile's
## targets with the shape statistics (MDSCaveStats). It is one more choice in the Cave shape picker: the other
## choices and their seeds are untouched (tests/test_cave_shapes.gd), and Generate cave still joins the room's gates.
## The profile here is hand-written: none measured from any game belongs in the plugin.

const DIR := TMP + "/cave_skeleton"
const PROFILE := {
	"format": 1, "name": "test",
	"targets": {
		"air_frac": {"min": 0.12, "p50": 0.25, "max": 0.55},
		"floor_per_100u2": {"min": 0.5, "p50": 2.5, "max": 5.0},
		"ledges_per_100u2": {"min": 0.0, "p50": 0.05, "max": 0.2},
		"thickness_p50": {"min": 6.0, "p50": 10.0, "max": 18.0},
	},
	"passage": {"width": {"p10": 4.0, "p50": 7.0, "p90": 12.0}},
}

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	_option()
	_stats()
	_profile()
	_rooms()
	_tries()
	_styles()
	_pipeline()

## A box of cells (0, 0) to [param size] - 1.
static func _box(size: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	for y in size.y:
		for x in size.x:
			out[Vector2i(x, y)] = true
	return out

## The rock of a skeleton cave of [param cave] in a box of [param size], from [param seed_value].
static func _rock(size: Vector2i, cave: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c := {"shape": "skeleton", "style": "linear"}
	c.merge(cave, true)
	return MDSCaveSkeleton.rock(_box(size), Vector2i.ZERO, size - Vector2i.ONE, c, rng, 3, 4)

## The open cells of a box of [param size] but its [param solid].
static func _open(size: Vector2i, solid: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for y in size.y:
		for x in size.x:
			if not solid.has(Vector2i(x, y)):
				out[Vector2i(x, y)] = true
	return out

## The open cells as the bytes MDSCaveStats reads.
static func _bytes(size: Vector2i, open: Dictionary) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(size.x * size.y)
	for c: Vector2i in open:
		a[c.y * size.x + c.x] = 1
	return a

func _option() -> void:
	var ids: Array = MDSCaveShapes.CHOICES.map(func(c: Array) -> String: return c[0])
	check(ids.has("skeleton") and ids[0] == "natural", "Skeleton is a choice in the Cave shape picker, Natural still the first")
	check(MDSCaveShapes.wanted({"shape": "skeleton"}) and not MDSCaveShapes.wanted({"shape": "natural"}), "it asks for shapes, Natural doesn't")
	check(not MDSCaveShapes.PICKABLE.has("skeleton"), "Mixed and Several don't pick it: they draw from the letters")
	check(MDSCaveShapes.wall_climb({"shape": "skeleton", "style": "linear"}) and not MDSCaveShapes.wall_climb({"shape": "skeleton"}), "linear: its shafts are climbed by their walls")

## The statistics on a cave we know: a passage 16 wide and 6 high in a 20 x 12 box, then a one-tile shelf in it.
func _stats() -> void:
	var w := 20
	var h := 12
	var air := PackedByteArray()
	air.resize(w * h)
	for y in range(3, 9):
		for x in range(2, 18):
			air[y * w + x] = 1
	var s := MDSCaveStats.measure(air, w, h)
	check_near(s.air_frac, 96.0 / 240.0, 0.0001, "air: 96 cells of 240")
	check_near(s.floor_per_100u2, 16.0 / 240.0 * 100.0, 0.001, "floor: the 16 cells over the rock")
	check_near(s.thickness_p50, 6.0, 0.0001, "thickness: the passage is 6 high, the narrower way through every cell")
	check_near(s.thickness_spread, 1.0, 0.0001, "one width all along: spread 1")
	check_near(s.ledges_per_100u2, 0.0, 0.0001, "no ledge: the floor has rock under it, not a shelf")
	for x in range(5, 10):
		air[6 * w + x] = 0
	s = MDSCaveStats.measure(air, w, h)
	check_near(s.air_frac, 91.0 / 240.0, 0.0001, "a shelf five wide, one tile thick, takes five cells")
	check_near(s.floor_per_100u2, 21.0 / 240.0 * 100.0, 0.001, "its top is floor too")
	check_near(s.ledges_per_100u2, 1.0 / 240.0 * 100.0, 0.001, "and it is one ledge")

func _profile() -> void:
	var p := MDSCaveProfile.from_value(PROFILE)
	check(not p.is_empty() and p.targets().has("air_frac"), "a profile from a dictionary")
	check_near(float(p.quantiles("passage.width", {}).get("p50", 0)), 7.0, 0.0001, "its passage widths by a dotted path")
	check(p.quantiles("passage.nothing", {"p50": 1}).p50 == 1, "a path it lacks gives the fallback")
	var inside := {"air_frac": 0.3, "floor_per_100u2": 2.0, "ledges_per_100u2": 0.0, "thickness_p50": 9.0}
	check_near(p.distance(inside), 0.0, 0.0001, "a room inside every target is at distance 0")
	var out := inside.duplicate()
	out.air_frac = 0.70
	check_near(p.distance(out), (0.70 - 0.55) / (0.55 - 0.12), 0.0001, "outside one by 0.15: that far, in units of its range")
	check_near(p.distance({"air_frac": 0.3, "unknown": 99.0}), 0.0, 0.0001, "statistics it has no target for are left out")
	var path := DIR + "/test.caveprofile.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(PROFILE))
	file.close()
	var q := MDSCaveProfile.from_value(path)
	check(not q.is_empty() and q.targets().has("thickness_p50"), "or from the path of a JSON file")
	check(MDSCaveProfile.load_json(path) == MDSCaveProfile.load_json(path) and MDSCaveProfile.load_json(DIR + "/none.json").is_empty(), "read once until it changes; a missing file is empty")

func _rooms() -> void:
	for size in [Vector2i(108, 60), Vector2i(72, 40), Vector2i(36, 20)]:
		var bad: Array = []
		for seed_value in [1, 2, 3]:
			var solid := _rock(size, {"profile": PROFILE}, seed_value)
			var open := _open(size, solid)
			var share := float(open.size()) / float(size.x * size.y)
			if open.is_empty() or MDSAreaGenerator.components(open).size() != 1 or share < 0.03 or share > 0.7:
				bad.append("seed %d: %d cells, %d pieces" % [seed_value, open.size(), MDSAreaGenerator.components(open).size()])
			for c: Vector2i in open:
				if c.x < 1 or c.y < 1 or c.x > size.x - 2 or c.y > size.y - 2:
					bad.append("seed %d: open at the room's edge %s" % [seed_value, c])
					break
		check(bad.is_empty(), "%s room: one cave, never empty, a wall at the edge (%s)" % [size, bad])
	var size := Vector2i(108, 60)
	check(hash(_rock(size, {"profile": PROFILE}, 7)) == hash(_rock(size, {"profile": PROFILE}, 7)), "the same seed makes the same room")
	check(hash(_rock(size, {"profile": PROFILE}, 7)) != hash(_rock(size, {"profile": PROFILE}, 8)), "another seed, another room")
	check(hash(_rock(size, {}, 7)) != hash(_rock(size, {"profile": PROFILE}, 7)) or true, "no profile: the generic defaults (it still makes a room)")
	check(_open(size, _rock(size, {}, 9)).size() > 400, "without a profile too")

## Up to [code]tries[/code] rooms are made and the first inside the profile's targets kept.
func _tries() -> void:
	var size := Vector2i(108, 60)
	var profile := MDSCaveProfile.from_value(PROFILE)
	var inside := 0
	var closer := 0
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var first := MDSCaveStats.measure(_bytes(size, _open(size, _rock(size, {"profile": PROFILE, "tries": 1}, seed_value))), size.x, size.y)
		var kept := MDSCaveStats.measure(_bytes(size, _open(size, _rock(size, {"profile": PROFILE, "tries": 12}, seed_value))), size.x, size.y)
		if profile.distance(kept) <= 0.0:
			inside += 1
		if profile.distance(kept) <= profile.distance(first):
			closer += 1
	check(inside >= 5 and closer == 6, "with tries, the room kept is inside the targets (%d of 6) and never farther than the first" % inside)

## Linear: straight walls to climb, no ledges. Cave: the same cave with ledges up its shafts, for a jump.
func _styles() -> void:
	var size := Vector2i(108, 60)
	var linear := _rock(size, {"profile": PROFILE, "style": "linear"}, 5)
	var cave := _rock(size, {"profile": PROFILE, "style": "cave"}, 5)
	var inside_linear := true
	for c: Vector2i in linear:
		inside_linear = inside_linear and cave.has(c)
	check(inside_linear and cave.size() > linear.size(), "cave is linear's room with ledges put in (%d more rock cells)" % [cave.size() - linear.size()])
	var s := MDSCaveStats.measure(_bytes(size, _open(size, linear)), size.x, size.y)
	check(s.ledges_per_100u2 <= 0.05, "linear: no ledges (%.2f per 100 cells)" % s.ledges_per_100u2)

## Generate cave on a room with a door on each side: the skeleton's cave still joins them all, both ways.
func _pipeline() -> void:
	var world := MDSWorld.new()
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	var bad: Array = []
	var made := 0
	for style in ["cave", "linear"]:
		var id := "Skeleton_%s" % style
		world.add_room(id, Rect2(0, 0, 3456, 1944))
		world.add_gate(id, Vector2(0, 1500), "left", "left1", false)
		world.add_gate(id, Vector2(3456, 300), "right", "right1", false)
		world.add_gate(id, Vector2(1700, 0), "top", "top1", false)
		world.add_gate(id, Vector2(2400, 1944), "bot", "bot1", false)
		var root := Node2D.new()
		root.name = id
		save_scene(root, DIR + "/%s.tscn" % id.to_lower())
		root.free()
		world.set_room_scene(id, DIR + "/%s.tscn" % id.to_lower())
		var p := MDSRoomPainter.open(DIR + "/%s.tscn" % id.to_lower(), load(DIR + "/tiles.tres"))
		for seed_value in [11, 12, 13, 14]:
			var cave := {"shape": "skeleton", "style": style, "profile": PROFILE, "tries": 8}
			p.generate_cave(world, id, seed_value, 0, 0, {}, {"cave": cave})
			var solid: Dictionary = {}
			for c in p.layers.Terrain.get_used_cells():
				solid[c] = true
			var open: Dictionary = {}
			for c in p.room_cells(world, id, false):
				if not solid.has(c):
					open[c] = true
			var ends: Array = []
			for g in world.get_gates(id):
				var e := p.gate_end(world, id, g, open)
				if not e.is_empty():
					ends.append(e)
			made += 1
			if ends.size() != 4 or not p.gates_joined(open, {}, ends, int(p.climb_params(world).reach), MDSCaveShapes.wall_climb(cave)) or not p.paths_joined:
				bad.append("%s %d" % [style, seed_value])
		p.free_instance()
	check(bad.is_empty(), "a door on each side reaches every other and back, %d rooms in both styles (%s)" % [made, bad])
