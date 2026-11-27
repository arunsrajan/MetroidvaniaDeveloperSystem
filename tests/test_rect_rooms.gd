extends "res://tests/test_case.gd"
## Generate cave's "rooms" style (MDSRectRooms) and the hazards placed in a room of any style
## (MDSRoomHazards).
##
## Rooms: straight-walled chambers split out of the box, every chamber and gate reaching every
## other and back, room to stand in each, the same seed giving the same room, nothing carved
## outside an L-shaped room's shape. Hazards: spikes, pits and gauntlets that never cut a path,
## turned into MDSHazard nodes that a new generation replaces (those placed by hand stay).

const DIR := TMP + "/rect_rooms"
const TALL := 4
const STEP := 3
const REACH := 5

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	MDSTilesetFactory.get_or_create(DIR + "/tiles.tres")
	_layouts()
	_l_shape()
	_hazards()
	_in_rooms()
	await _room_view()

func _box(w: int, h: int) -> Dictionary:
	var out: Dictionary = {}
	for y in h:
		for x in w:
			out[Vector2i(x, y)] = true
	return out

func _open(solid: Dictionary, inside: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for c in inside:
		if not solid.has(c):
			out[c] = true
	return out

func _gates(w: int, h: int, rng: RandomNumberGenerator) -> Array:
	return [{"cell": Vector2i(0, rng.randi_range(h / 3, h - 5)), "side": "left"}, {"cell": Vector2i(w - 1, rng.randi_range(h / 3, h - 5)), "side": "right"}]

## Many sizes and seeds: joined, chambers you can stand in, the same twice.
func _layouts() -> void:
	var sizes := [Vector2i(48, 24), Vector2i(64, 32), Vector2i(80, 40), Vector2i(40, 56), Vector2i(96, 28)]
	var made := 0
	var joined := 0
	var roomy := 0
	var chambers := 0
	var t0 := Time.get_ticks_msec()
	for s in 20:
		var size: Vector2i = sizes[s % sizes.size()]
		var inside := _box(size.x, size.y)
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + s
		var gates := _gates(size.x, size.y, rng)
		var room := MDSRectRooms.build(inside, Vector2i.ZERO, size - Vector2i.ONE, {"style": "rooms"}, gates, rng, TALL, STEP, REACH)
		made += 1
		chambers += room.chambers.size()
		var open := _open(room.solid, inside)
		var land := MDSRoomPainter.land_map(open)
		var ends: Array = []
		for g: Dictionary in gates:
			ends.append({"cell": g.cell + Vector2i(0, 1), "side": g.side})
		if room.chambers.size() >= 2 and MDSRoomHazards.joined(open, land, room.anchors, ends, REACH):
			joined += 1
		# Every chamber: rows enough above its floor's anchor to stand.
		var ok := true
		for a: Vector2i in room.anchors:
			for dy in TALL:
				ok = ok and open.has(a - Vector2i(0, dy))
		if ok:
			roomy += 1
		if s < 3:
			var again := RandomNumberGenerator.new()
			again.seed = 100 + s
			again.randi_range(0, 1)
			again.randi_range(0, 1)
			var twice := MDSRectRooms.build(inside, Vector2i.ZERO, size - Vector2i.ONE, {"style": "rooms"}, gates, again, TALL, STEP, REACH)
			check(twice.solid.hash() == room.solid.hash(), "seed %d: the same room again" % (100 + s))
	check(joined == made, "every chamber and both gates reach each other both ways (%d of %d rooms, %d chambers, %d ms)" % [joined, made, chambers, Time.get_ticks_msec() - t0])
	check(roomy == made, "room to stand on every chamber's floor (%d of %d)" % [roomy, made])
	check(chambers >= made * 3, "rooms of several chambers (%d in %d rooms)" % [chambers, made])

## An L-shaped room: nothing opened outside its shape.
func _l_shape() -> void:
	var inside := _box(64, 40)
	for y in range(0, 20):
		for x in range(32, 64):
			inside.erase(Vector2i(x, y))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var gates := [{"cell": Vector2i(0, 30), "side": "left"}, {"cell": Vector2i(63, 34), "side": "right"}]
	var room := MDSRectRooms.build(inside, Vector2i.ZERO, Vector2i(63, 39), {"style": "rooms"}, gates, rng, TALL, STEP, REACH)
	var outside := 0
	for y in range(0, 20):
		for x in range(32, 64):
			if not room.solid.has(Vector2i(x, y)):
				outside += 1
	check(outside == 0, "an L-shaped room: rock everywhere outside its shape")
	check(room.chambers.size() >= 2, "an L-shaped room: chambers in it (%d)" % room.chambers.size())

## Hazards on the layouts: placed, none cutting a path; "none" places none.
func _hazards() -> void:
	var placed := 0
	var kinds: Dictionary = {}
	var still := 0
	var t0 := Time.get_ticks_msec()
	for s in 10:
		var size := Vector2i(80, 40) if s % 2 == 0 else Vector2i(64, 32)
		var inside := _box(size.x, size.y)
		var rng := RandomNumberGenerator.new()
		rng.seed = 300 + s
		var gates := _gates(size.x, size.y, rng)
		var room := MDSRectRooms.build(inside, Vector2i.ZERO, size - Vector2i.ONE, {"style": "rooms"}, gates, rng, TALL, STEP, REACH)
		var ends: Array = []
		for g: Dictionary in gates:
			ends.append({"cell": g.cell + Vector2i(0, 1), "side": g.side})
		var solid: Dictionary = room.solid
		var hs := MDSRoomHazards.place(solid, inside, room.anchors, ends, room.keep, {"hazards": "many"}, rng, REACH, TALL, room.chambers.size())
		var deadly: Dictionary = {}
		for h: Dictionary in hs:
			kinds[h.kind] = int(kinds.get(h.kind, 0)) + 1
			for c: Vector2i in h.cells:
				deadly[c] = true
		placed += hs.size()
		var open := _open(solid, inside)
		# The chambers' anchors that hazards covered stand beside them now.
		var anchors := MDSRoomHazards.moved_anchors(room.anchors, deadly, open, solid)
		if not anchors.is_empty() and MDSRoomHazards.joined(open, MDSRoomPainter.land_map(open), anchors, ends, REACH, deadly):
			still += 1
		if s == 0:
			check(MDSRoomHazards.place(room.solid.duplicate(), inside, room.anchors, ends, room.keep, {"hazards": "none"}, rng, REACH, TALL, room.chambers.size()).is_empty(), "hazards none: none placed")
	check(still == 10, "with hazards, every chamber and gate still reach each other both ways (%d of 10)" % still)
	check(placed >= 30, "hazards placed (%d: %s, %d ms)" % [placed, kinds, Time.get_ticks_msec() - t0])
	check(kinds.size() == 3, "spikes, pits and gauntlets all placed (%s)" % [kinds])
	check(MDSRoomHazards.kinds_of({"hazard_kinds": ["pit", "lava"]}) == PackedStringArray(["pit"]), "only the kinds asked for, and that exist")

func _painter(world: MDSWorld, id: String) -> MDSRoomPainter:
	var root := Node2D.new()
	root.name = id
	var path := DIR + "/%s.tscn" % id.to_lower()
	save_scene(root, path)
	root.free()
	world.set_room_scene(id, path)
	return MDSRoomPainter.open(path, load(DIR + "/tiles.tres"))

func _hazard_nodes(p: MDSRoomPainter) -> Array:
	return p.root.get_children().filter(func(n: Node) -> bool: return n is MDSHazard)

## Generate cave: the rooms style, hazards in it and in a cave, replaced by a new generation.
func _in_rooms() -> void:
	var world := MDSWorld.new()
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	world.add_room("Keep", Rect2(0, 0, 2560, 1280))
	world.add_gate("Keep", Vector2(0, 1000), "left", "left1", false)
	world.add_gate("Keep", Vector2(2560, 700), "right", "right1", false)
	world.add_gate("Keep", Vector2(1280, 0), "top", "top1", false)
	var p := _painter(world, "Keep")
	p.generate_cave(world, "Keep", 4, 0, 0, {}, {"cave": {"style": "rooms", "hazards": "some"}})
	check(p.paths_joined, "rooms style: its gates joined")
	if OS.get_environment("LAYOUT_DEBUG") == "1":
		_dump(p)
	var nodes := _hazard_nodes(p)
	check(not nodes.is_empty() and nodes.size() == p.hazards_placed.size(), "rooms style: hazard nodes (%d)" % nodes.size())
	var generated := nodes.filter(func(n: Node) -> bool: return n.has_meta(MDSRoomPainter.GENERATED_META) and (n as MDSHazard).mode == MDSHazard.Mode.RESPAWN)
	check(generated.size() == nodes.size(), "they put the player back on safe ground, marked generated")
	# Lying on the floor: rock under each one's middle.
	var on_floor := 0
	for n: MDSHazard in nodes:
		var under := p.cell_at("Terrain", n.position + Vector2(0, n.size.y))
		if p.layers.Terrain.get_cell_source_id(under) != -1:
			on_floor += 1
	check(on_floor == nodes.size(), "each on a floor (%d of %d)" % [on_floor, nodes.size()])
	# A hazard placed by hand stays; the generated ones are replaced.
	var mine := MDSHazard.new()
	mine.name = "MySpikes"
	p.root.add_child(mine)
	mine.owner = p.root
	p.generate_cave(world, "Keep", 4, 0, 0, {}, {"cave": {"style": "rooms", "hazards": "none"}})
	var left := _hazard_nodes(p)
	check(left.size() == 1 and left[0] == mine, "hazards none again: the generated ones gone, the one placed by hand kept")
	p.free_instance()

	world.add_room("Grotto", Rect2(0, 1280, 2560, 1280))
	world.add_gate("Grotto", Vector2(0, 2200), "left", "left2", false)
	world.add_gate("Grotto", Vector2(2560, 2300), "right", "right2", false)
	var q := _painter(world, "Grotto")
	q.generate_cave(world, "Grotto", 11, 0, 0, {}, {"cave": {"shape": "skeleton", "hazards": "many"}})
	check(q.paths_joined, "a cave with hazards: its gates joined")
	check(not _hazard_nodes(q).is_empty(), "a cave with hazards: hazards in it (%d)" % _hazard_nodes(q).size())
	q.generate_cave(world, "Grotto", 11, 0, 0, {}, {"cave": {"shape": "natural", "hazards": "some"}})
	check(q.paths_joined and not _hazard_nodes(q).is_empty(), "a natural cave with hazards: joined, %d hazards" % _hazard_nodes(q).size())
	q.free_instance()

## The room's Terrain as text (# rock, ^ a hazard over a cell), for LAYOUT_DEBUG=1.
func _dump(p: MDSRoomPainter) -> void:
	var r: Rect2i = (p.layers.Terrain as TileMapLayer).get_used_rect()
	var spiked: Dictionary = {}
	for n in _hazard_nodes(p):
		var h := n as MDSHazard
		var a := p.cell_at("Terrain", h.position - Vector2(h.size.x * 0.5 - 1, 0))
		var b := p.cell_at("Terrain", h.position + Vector2(h.size.x * 0.5 - 1, 0))
		for x in range(a.x, b.x + 1):
			spiked[Vector2i(x, a.y)] = true
	for y in range(r.position.y, r.end.y):
		var line := ""
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			line += "^" if spiked.has(c) else ("#" if p.layers.Terrain.get_cell_source_id(c) != -1 else ".")
		print(line)

## The Room view: Rooms in the Style list, its splits, and the Hazards picker for any style.
func _room_view() -> void:
	var world := MDSWorld.new()
	world.path = DIR + "/rv.mdsworld.json"
	world.set_setting("room_tileset", DIR + "/tiles.tres")
	world.add_room("A", Rect2(0, 0, 1728, 972))
	var view := MDSRoomView.new()
	add_child(view)
	view.world = world
	var style := view.cave_style_picker
	var rooms := MDSCaveShapes.STYLES.map(func(c: Array) -> String: return c[0]).find("rooms")
	check(rooms >= 0 and style.item_count == MDSCaveShapes.STYLES.size(), "the Style list has Rooms")
	check(not view.cave_depth_spin.visible and view.generation_fills().get("cave", {}).is_empty(), "a natural cave, no hazards: nothing asked of the cave")
	style.select(rooms)
	style.item_selected.emit(rooms)
	view.cave_depth_spin.value = 5
	view.cave_depth_spin.value_changed.emit(5.0)
	var cave: Dictionary = view.generation_fills().get("cave", {})
	check(cave.get("style") == "rooms" and int(cave.get("depth", 0)) == 5 and view.cave_shape_picker.disabled and view.cave_depth_spin.visible, "Rooms picked: its splits, no shape to pick (%s)" % [cave])
	var some := MDSRoomHazards.LEVELS.map(func(c: Array) -> String: return c[0]).find("some")
	view.cave_hazards_picker.select(some)
	view.cave_hazards_picker.item_selected.emit(some)
	cave = view.generation_fills().get("cave", {})
	check(cave.get("hazards") == "some" and (cave.get("hazard_kinds", []) as Array).size() == 3 and not view.cave_hazard_kinds_menu.disabled, "Hazards Some: all kinds ticked")
	style.select(0)
	style.item_selected.emit(0)
	cave = view.generation_fills().get("cave", {})
	check(cave.get("hazards") == "some" and str(cave.get("shape", "")) == "natural", "a natural cave with hazards: Generate cave gets them")
	view.queue_free()
	await get_tree().process_frame
