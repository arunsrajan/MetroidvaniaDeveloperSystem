extends "res://tests/test_case.gd"
## Generate cave with what is picked in the Room view (terrain, background, decor, foreground,
## stamps), the paths it joins a room's gates with (crossed and backtracked: walking, jumping,
## climbing ledges, falling), caves for a whole area, and placing effects one after another.

const DIR := TMP + "/cave_paths"
const STAMPS := "res://asset_packs/mossgrove/freeform/mossgrove.stamps.tres"

## Collects the engine errors logged while it is added (OS.add_logger).
class ErrorCatcher extends Logger:
	var errors: PackedStringArray = []
	func _log_error(function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s: %s %s" % [function, code, rationale])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_reach()
	_paths()
	_fills()
	_area_caves()
	await _effects_one_after_another()

## A room 1152 x 648 (36 x 20 tiles) with a low left gate, a high right gate and a top gate.
func _room(world: MDSWorld, id := "Cave") -> MDSRoomPainter:
	world.add_room(id, Rect2(0, 0, 1152, 648), 0)
	world.add_gate(id, Vector2(0, 540), "left", "left1", false)
	world.add_gate(id, Vector2(1152, 160), "right", "right1", false)
	world.add_gate(id, Vector2(800, 0), "top", "top1", false)
	var root := Node2D.new()
	root.name = id
	var path := DIR + "/" + id.to_lower() + ".tscn"
	save_scene(root, path)
	root.free()
	load_fresh(path)
	world.set_room_scene(id, path)
	return MDSRoomPainter.open(path)

## Whether every gate of [param id] reaches every other one and back in the painter's cave.
func _crossable(world: MDSWorld, id: String, painter: MDSRoomPainter) -> Array:
	var inside := painter.room_cells(world, id)
	var solid: Dictionary = {}
	for c in painter.layers.Terrain.get_used_cells():
		solid[c] = true
	var ends: Array = []
	for g in world.get_gates(id):
		var e := painter.gate_end(world, id, g, inside)
		if not e.is_empty():
			ends.append(e)
	var bad: Array = []
	for i in ends.size():
		for j in range(i + 1, ends.size()):
			if not painter._both_ways(inside, solid, ends[i], ends[j], 6):
				bad.append("%s-%s" % [ends[i].side, ends[j].side])
	return bad

func _reach() -> void:
	# A floor, a wall three tiles high to jump, a ledge ladder in a shaft.
	var open: Dictionary = {}
	for x in 12:
		for y in 12:
			open[Vector2i(x, y)] = true
	for x in 12:
		open.erase(Vector2i(x, 12))
	var land := MDSRoomPainter.land_map(open)
	check(land[Vector2i(3, 2)] == Vector2i(3, 11), "let go in the air, you land on the floor")
	var all := MDSRoomPainter.climb_reach(open, Vector2i(0, 11), 4, 3, land)
	check(all.has(Vector2i(11, 11)) and all.size() == 12, "walking reaches the whole floor (%d)" % all.size())
	# A shelf too high to jump to, then a step to it.
	var shelf := open.duplicate()
	for x in range(6, 12):
		shelf.erase(Vector2i(x, 5))
	var reach := MDSRoomPainter.climb_reach(shelf, Vector2i(0, 11), 4, 3)
	check(not reach.has(Vector2i(8, 4)), "a shelf six tiles up can't be jumped to")
	shelf.erase(Vector2i(4, 8))
	shelf.erase(Vector2i(5, 8))
	reach = MDSRoomPainter.climb_reach(shelf, Vector2i(0, 11), 4, 3)
	check(reach.has(Vector2i(4, 7)) and reach.has(Vector2i(8, 4)), "with a step between, it can")

func _paths() -> void:
	var t := 0
	for seed_value in [11, 12, 13, 14, 15, 16]:
		var world := MDSWorld.new()
		var painter := _room(world)
		var terrain: Array = painter.get_terrains()[0]
		painter.generate_cave(world, "Cave", seed_value, terrain[0], terrain[1], {}, {"paths": true})
		var bad := _crossable(world, "Cave", painter)
		check(bad.is_empty(), "seed %d: every gate reaches every other one and back (%s)" % [seed_value, bad])
		painter.free_instance()
		t += 1
	# A tall shaft between a low and a high gate gets ledges to climb.
	var world := MDSWorld.new()
	world.add_room("Shaft", Rect2(0, 0, 576, 1296), 0)
	world.add_gate("Shaft", Vector2(0, 1200), "left", "left1", false)
	world.add_gate("Shaft", Vector2(576, 120), "right", "right1", false)
	var root := Node2D.new()
	root.name = "Shaft"
	save_scene(root, DIR + "/shaft.tscn")
	root.free()
	load_fresh(DIR + "/shaft.tscn")
	world.set_room_scene("Shaft", DIR + "/shaft.tscn")
	var p := MDSRoomPainter.open(DIR + "/shaft.tscn")
	var tr: Array = p.get_terrains()[0]
	p.generate_cave(world, "Shaft", 5, tr[0], tr[1], {}, {"paths": true})
	check(_crossable(world, "Shaft", p).is_empty(), "a room 40 tiles tall: up from the low gate to the high one and back down")
	p.free_instance()

func _fills() -> void:
	var world := MDSWorld.new()
	var painter := _room(world)
	var stamps := load(STAMPS) as MDSStampSet
	var category: String = stamps.get_categories()[0] if stamps and not stamps.get_categories().is_empty() else ""
	var fills := {
		"terrain": {"type": "color", "color": Color(0.3, 0.2, 0.1)},
		"background": {"type": "color", "color": Color(0.1, 0.3, 0.2)},
		"decor": {"type": "color", "color": Color(0.9, 0.9, 0.2)},
		"foreground": {"type": "color", "color": Color(0.02, 0.03, 0.04)},
		"stamps": {"set": stamps, "category": category, "group": "StampsFront", "scale": 1.0},
	}
	painter.generate_cave(world, "Cave", 21, 0, 0, {}, fills)
	var color_source := func(layer: String) -> bool:
		var cells: Array = painter.layers[layer].get_used_cells()
		if cells.is_empty():
			return false
		for c in cells:
			var src := painter.tile_set.get_source(painter.layers[layer].get_cell_source_id(c))
			if src.resource_name not in [MDSRoomPainter.COLOR_SOURCE_NAME, MDSLegacy.OLD_COLOR_SOURCE_NAME]:
				return false
		return true
	check(color_source.call("Terrain"), "the rock is painted with the Terrain fill, autotiled or not (a solid color here)")
	check(color_source.call("Background"), "the background with the Background fill")
	var decor_colored: Array = painter.layers.Decor.get_used_cells().filter(func(c: Vector2i) -> bool: return painter.tile_set.get_source(painter.layers.Decor.get_cell_source_id(c)).resource_name == MDSRoomPainter.COLOR_SOURCE_NAME)
	check(not decor_colored.is_empty(), "floor decorations of the Decor fill (%d)" % decor_colored.size())
	# The foreground fill darkens the rock deep in the walls, never where the player goes.
	var inside := painter.room_cells(world, "Cave")
	var open: Dictionary = {}
	for c in inside:
		if painter.layers.Terrain.get_cell_source_id(c) == -1:
			open[c] = true
	var fg: Array = painter.layers.Foreground.get_used_cells()
	var near: Array = fg.filter(func(c: Vector2i) -> bool:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) <= 2 and open.has(c + Vector2i(dx, dy)):
					return true
		return false)
	check(not fg.is_empty() and near.is_empty(), "the foreground fills the rock deep in the walls (%d tiles, %d near the cave)" % [fg.size(), near.size()])
	var generated := func() -> int: return painter.items("StampsFront").filter(func(s: Node) -> bool: return s.has_meta(MDSRoomPainter.GENERATED_META)).size()
	if stamps:
		var n: int = generated.call()
		check(n > 0, "stamps of the picked set along the floors (%d)" % n)
		painter.generate_cave(world, "Cave", 22, 0, 0, {}, fills)
		check(generated.call() <= n + 3 and generated.call() > 0, "a new variation replaces them (%d)" % generated.call())
	else:
		check(false, "the Mossgrove stamps are in the project")
	painter.free_instance()

func _area_caves() -> void:
	var world := MDSWorld.new()
	var gen := MDSAreaGenerator.new()
	gen.shape = MDSAreaGenerator.Shape.HYBRID
	gen.seed_value = 9
	var r := gen.generate(world, Rect2i(0, 0, 12, 8), 0, "The Test Caves")
	var ids: Array[String] = r.rooms
	check(ids.size() >= 4, "an area of rooms with doors (%d)" % ids.size())
	var order := MDSWorldSceneTools.area_room_order(world, "The Test Caves", 0)
	check(order.size() == ids.size() and order.all(func(id: String) -> bool: return ids.has(id)), "the area's rooms in the order a player meets them")
	var path_for := func(id: String) -> String: return DIR + "/area/" + id.to_snake_case() + ".tscn"
	var res := MDSWorldSceneTools.generate_area_caves(world, order, path_for, {"paths": true}, null, false, 3)
	check(res.made.size() == ids.size() and res.generated.size() == ids.size() and res.failed.is_empty(), "caves in every room, a scene made for each (%s)" % [res.failed])
	var all_crossable := true
	var gates_written := true
	var painted := true
	for id in ids:
		var path := world.get_scene_path(id)
		load_fresh(path)
		var p := MDSRoomPainter.open(path)
		painted = painted and not p.layers.Terrain.get_used_cells().is_empty()
		var bad := _crossable(world, id, p)
		if not bad.is_empty():
			all_crossable = false
			print("    ", id, " ", bad)
		var nodes := p.root.find_children("*", "MDSGate", true, false)
		gates_written = gates_written and nodes.size() == world.get_gates(id).size()
		p.free_instance()
	check(painted and gates_written, "each is painted and has its gate nodes")
	check(all_crossable, "and every room's gates reach each other both ways: the area can be crossed and backtracked")
	var again := MDSWorldSceneTools.generate_area_caves(world, order, path_for, {"paths": true}, null, true, 3)
	check(again.skipped.size() == ids.size() and again.generated.is_empty(), "Leave rooms already painted alone")

func _effects_one_after_another() -> void:
	var world := MDSWorld.new()
	var painter := _room(world, "Fx")
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(900, 520)
	add_child(canvas)
	canvas.open(world, "Fx", painter)
	canvas.tool = MDSRoomCanvas.Tool.EFFECT
	var picks: Array = []
	canvas.effect_pick_changed.connect(func(id: String) -> void: picks.append(id))
	var press := func(at: Vector2, pressed: bool, shift := false, ctrl := false) -> void:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.shift_pressed = shift
		mb.ctrl_pressed = ctrl
		mb.position = at
		canvas._effect_input(mb)
	var click := func(at: Vector2, shift := false, ctrl := false) -> void:
		press.call(at, true, shift, ctrl)
		press.call(at, false, shift, ctrl)
	var drag := func(from: Vector2, to: Vector2) -> void:
		press.call(from, true)
		for k in range(1, 5):
			var mm := InputEventMouseMotion.new()
			mm.position = from.lerp(to, k / 4.0)
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			canvas._effect_motion(mm)
		press.call(to, false)
	# Place one: picked in the list, a click places it and selects it.
	canvas.effect_id = "rain"
	click.call(Vector2(300, 200))
	var rain: MDSEnvironmentEffect = canvas.selected_effect
	check(painter.effects().size() == 1 and rain is MDSRain, "a click places the picked effect, selected")
	check(canvas.effect_id.is_empty() and picks == [""], "then the list goes back to No effect")
	# The same effect is selectable and draggable again.
	canvas.selected_effect = null
	click.call(Vector2(310, 210))
	check(painter.effects().size() == 1 and canvas.selected_effect == rain, "clicking it again selects it, no new one")
	var before := rain.position
	var undo_steps := painter._undo.size()
	drag.call(Vector2(310, 210), Vector2(410, 260))
	check(painter.effects().size() == 1 and rain.position.distance_to(before + (Vector2(100, 50) / canvas.zoom)) < 2.0, "and dragging moves it (%s -> %s)" % [before, rain.position])
	check(painter._undo.size() == undo_steps + 1, "one undo step for the move")
	undo_steps = painter._undo.size()
	click.call(Vector2(410, 260))
	check(painter._undo.size() == undo_steps, "a click alone adds no undo step")
	# Dragging right after placing moves the new one.
	canvas.effect_id = "fog"
	press.call(Vector2(500, 300), true)
	var fog: MDSEnvironmentEffect = canvas.selected_effect
	var fog_at := fog.position
	for k in range(1, 5):
		var mm := InputEventMouseMotion.new()
		mm.position = Vector2(500, 300) + Vector2(15, 5) * k
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		canvas._effect_motion(mm)
	press.call(Vector2(560, 320), false)
	check(fog is MDSFog and fog.position.distance_to(fog_at + Vector2(60, 20) / canvas.zoom) < 2.0 and painter.effects().size() == 2, "placing and dragging at once puts it where you let go")
	painter.undo()
	check(painter.effects().size() == 1, "and placing it is one undo step")
	await get_tree().process_frame
	# Several in a row: Ctrl+click keeps it picked.
	canvas.effect_id = "fog"
	click.call(Vector2(200, 150), false, true)
	click.call(Vector2(250, 180), false, true)
	check(painter.effects().size() == 3 and canvas.effect_id == "fog", "Ctrl+click places several, the effect staying picked")
	click.call(Vector2(260, 190), true)
	check(painter.effects().size() == 3, "Shift+click selects instead of placing")
	# Stacked effects (most cover the whole room): clicking the selected one picks the next.
	canvas.effect_id = ""
	var here := painter.effects_at(canvas.screen_to_local(Vector2(320, 220)))
	click.call(Vector2(320, 220))
	var first := canvas.selected_effect
	click.call(Vector2(320, 220))
	check(here.size() >= 2 and canvas.selected_effect != first and here.has(canvas.selected_effect), "clicking the selected effect again selects the next one under it (%d here)" % here.size())
	# Undo takes the selected effect out (and frees it): clicking on stays quiet.
	canvas.effect_id = "rain"
	click.call(Vector2(600, 300))
	painter.undo()
	await get_tree().process_frame
	await get_tree().process_frame
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	click.call(Vector2(600, 300), true)
	drag.call(Vector2(620, 320), Vector2(640, 340))
	canvas.delete_selected_effect()
	OS.remove_logger(catcher)
	check(catcher.errors.is_empty(), "after undo took the selected effect out, clicks, drags and Delete raise no errors (%s)" % "; ".join(catcher.errors))
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
	await get_tree().process_frame
