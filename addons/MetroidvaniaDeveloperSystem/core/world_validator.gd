@tool
class_name MDSWorldValidator
extends RefCounted
## Checks for non-linear worlds: rooms, scenes, gates and layout, plus the shared
## progression/design checks from [MDSValidator].

const CATEGORY_ROOMS := "Rooms & scenes"
const CATEGORY_GATES := "Gates"
const CATEGORY_LAYOUT := "Layout"

static func run(world: MDSWorld, analysis: MDSAnalysis, scene_db: Dictionary) -> Array:
	var issues: Array = []
	var W := MDSValidator.Severity.WARNING
	var E := MDSValidator.Severity.ERROR
	var I := MDSValidator.Severity.INFO
	var scene_users: Dictionary = {}
	var ids := world.get_room_ids()

	for id in ids:
		var name := analysis.get_room_name(id)
		var layer := world.get_room_layer(id)
		var at := world.get_room_label_pos(id)
		var path := world.get_scene_path(id)
		# --- Rooms & scenes ---
		if not world.has_scene_reference(id):
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "%s has no scene yet. Right-click it > Create scene, or drop a .tscn on it" % name, id, Vector3i.MAX, at, layer)
		elif path.is_empty():
			MDSValidator._add(issues, E, CATEGORY_ROOMS, "%s: scene %s could not be found (deleted or moved outside the project?)" % [name, world.data.rooms[id].get("scene", "")], id, Vector3i.MAX, at, layer)
		else:
			if not scene_users.has(path):
				scene_users[path] = []
			scene_users[path].append(id)
		if not world.get_areas().is_empty() and world.get_room_area(id).is_empty():
			MDSValidator._add(issues, I, CATEGORY_ROOMS, "%s is not in any area" % name, id, Vector3i.MAX, at, layer)
		var weather_problem := MDSEnvironment.check(str(world.get_room_value(id, "weather", "")))
		if not weather_problem.is_empty():
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "%s's weather: %s" % [name, weather_problem], id, Vector3i.MAX, at, layer)
		var parallax_problem := MDSEnvironment.check_parallax(str(world.get_room_value(id, "parallax", "")))
		if not parallax_problem.is_empty():
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "%s's parallax background: %s" % [name, parallax_problem], id, Vector3i.MAX, at, layer)
		var background_problem := MDSEnvironment.check_background(str(world.get_room_value(id, "background", "")))
		if not background_problem.is_empty():
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "%s's animated background: %s" % [name, background_problem], id, Vector3i.MAX, at, layer)

		# --- Gates ---
		var gates := world.get_gates(id)
		if gates.is_empty() and ids.size() > 1:
			MDSValidator._add(issues, W, CATEGORY_GATES, "%s has no gates. Use the Gate tool (G) to add transitions" % name, id, Vector3i.MAX, at, layer)
		for gate_name in gates:
			var gate: Dictionary = gates[gate_name]
			var gpos := world.get_gate_world_pos(id, gate_name)
			var to: String = gate.get("to", "")
			var to_gate: String = gate.get("to_gate", "")
			if to.is_empty():
				if not gate.get("one_way", false):
					MDSValidator._add(issues, W, CATEGORY_GATES, "%s.%s is not connected. Drag from it to another gate" % [name, gate_name], id, Vector3i.MAX, gpos, layer)
				continue
			if not world.has_room(to):
				MDSValidator._add(issues, E, CATEGORY_GATES, "%s.%s leads to missing room '%s'" % [name, gate_name, to], id, Vector3i.MAX, gpos, layer)
				continue
			if not world.has_gate(to, to_gate):
				MDSValidator._add(issues, E, CATEGORY_GATES, "%s.%s leads to missing gate '%s' in %s" % [name, gate_name, to_gate, analysis.get_room_name(to)], id, Vector3i.MAX, gpos, layer)
				continue
			var back := world.get_gate(to, to_gate)
			var points_back: bool = back.get("to", "") == id and back.get("to_gate", "") == gate_name
			if not points_back and not gate.get("one_way", false):
				MDSValidator._add(issues, I, CATEGORY_GATES, "%s.%s -> %s.%s is one-way (the target gate doesn't lead back). Tick One-way if intended" % [name, gate_name, analysis.get_room_name(to), to_gate], id, Vector3i.MAX, gpos, layer)
			if world.get_room_layer(to) == layer:
				var dist := gpos.distance_to(world.get_gate_world_pos(to, to_gate))
				if dist > world.get_grid() * 4 and id < to:
					MDSValidator._add(issues, I, CATEGORY_LAYOUT, "%s.%s and %s.%s are %d px apart on the map. Move the rooms together, or keep it if it's an elevator/long corridor" % [name, gate_name, analysis.get_room_name(to), to_gate, int(dist)], id, Vector3i.MAX, gpos, layer)

		# --- Scene content vs. map ---
		var meta: Dictionary = scene_db.get(path, {})
		if meta.is_empty():
			continue
		var content: Rect2 = meta.get("content_rect", Rect2())
		if content.has_area():
			var local_bounds := Rect2()
			var first := true
			for r in world.get_local_rects(id):
				local_bounds = r if first else local_bounds.merge(r)
				first = false
			if not local_bounds.grow(world.get_grid()).encloses(content):
				MDSValidator._add(issues, W, CATEGORY_LAYOUT, "%s: the scene's terrain (%s) extends past the room drawn on the map. Use Inspect > Fit to scene" % [name, _fmt_rect(content)], id, Vector3i.MAX, at, layer)
		for t in meta.get("twisted", []):
			MDSValidator.add_twisted_issue(issues, name, t, id, Vector3i.MAX, world.get_origin(id) + Vector2(t.position), layer)
		for o in meta.get("overlaps", []):
			MDSValidator.add_overlap_issue(issues, name, o, id, Vector3i.MAX, world.get_origin(id) + Vector2(o.position), layer)
		for b in meta.get("broken_tiles", []):
			MDSValidator.add_broken_tiles_issue(issues, name, b, id, Vector3i.MAX, world.get_origin(id) + Vector2(b.position), layer)
		# Physics checks (MDSRoomCheck), run in the background by the panel.
		for g in meta.get("geometry", []):
			MDSValidator._add(issues, W, MDSValidator.CATEGORY_GEOMETRY, g.message, id, Vector3i.MAX, world.get_origin(id) + Vector2(g.pos), layer)
		# Gameplay Kit checks
		for p in meta.get("ability_pickups_without_data", []):
			MDSValidator._add(issues, E, MDSValidator.CATEGORY_PROGRESSION, "%s: ability pickup '%s' has no ability data assigned" % [name, p.name], id, Vector3i.MAX, world.get_origin(id) + Vector2(p.position), layer)
		for arena in meta.get("invalid_boss_arenas", []):
			var what := "no boss and no doors" if (not arena.has_boss and not arena.has_doors) else ("no boss assigned" if not arena.has_boss else "no doors assigned")
			MDSValidator._add(issues, E, CATEGORY_ROOMS, "%s: boss arena '%s' has %s" % [name, arena.name, what], id, Vector3i.MAX, world.get_origin(id) + Vector2(arena.position), layer)
		var expected_boss := str(world.get_room_value(id, "boss", "")).strip_edges()
		if not expected_boss.is_empty():
			for b in meta.get("boss_nodes", []):
				if not str(b.name).is_empty() and str(b.name).to_lower() != expected_boss.to_lower():
					MDSValidator._add(issues, W, CATEGORY_ROOMS, "%s: boss '%s' in scene differs from room's boss '%s' in world file" % [name, b.name, expected_boss], id, Vector3i.MAX, world.get_origin(id) + Vector2(b.position), layer)
		var scene_gates: Dictionary = {}
		for t in meta.get("transitions", []):
			scene_gates[t.name] = t
			if not gates.has(t.name):
				MDSValidator._add(issues, W, CATEGORY_GATES, "%s: scene has gate '%s' that is not on the map. Inspect > Import gates from scene" % [name, t.name], id, Vector3i.MAX, at, layer)
		if not scene_gates.is_empty():
			for gate_name in gates:
				if not scene_gates.has(gate_name):
					MDSValidator._add(issues, I, CATEGORY_GATES, "%s.%s exists on the map but not in the scene. Inspect > Write gates to scene" % [name, gate_name], id, Vector3i.MAX, world.get_gate_world_pos(id, gate_name), layer)

	# --- Weather of areas and of the world ---
	for area in world.get_areas():
		var problem := MDSEnvironment.check(str(world.get_areas()[area].get("weather", "")))
		var rooms := world.get_area_rooms(area)
		if not problem.is_empty():
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "Area %s's weather: %s (Areas tab)" % [area, problem], rooms[0] if not rooms.is_empty() else "")
		var p_problem := MDSEnvironment.check_parallax(str(world.get_areas()[area].get("parallax", "")))
		if not p_problem.is_empty():
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "Area %s's parallax background: %s (Areas tab)" % [area, p_problem], rooms[0] if not rooms.is_empty() else "")
		for key in ["background", "boss_background"]:
			var b_problem := MDSEnvironment.check_background(str(world.get_areas()[area].get(key, "")))
			if not b_problem.is_empty():
				MDSValidator._add(issues, W, CATEGORY_ROOMS, "Area %s's %s: %s (Areas tab)" % [area, "boss room background" if key == "boss_background" else "animated background", b_problem], rooms[0] if not rooms.is_empty() else "")
	var world_problem := MDSEnvironment.check(str(world.get_setting("weather", "")))
	if not world_problem.is_empty():
		MDSValidator._add(issues, W, CATEGORY_ROOMS, "The world's weather: %s (World settings)" % world_problem)
	for key in ["background", "boss_background"]:
		var bg_problem := MDSEnvironment.check_background(str(world.get_setting(key, "")))
		if not bg_problem.is_empty():
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "The world's %s: %s (World settings)" % ["boss rooms background" if key == "boss_background" else "animated background", bg_problem])

	for path in scene_users:
		if scene_users[path].size() > 1:
			MDSValidator._add(issues, W, CATEGORY_ROOMS, "%s is used by %d rooms: %s" % [path.get_file(), scene_users[path].size(), ", ".join(scene_users[path])], scene_users[path][0])

	# --- Overlaps ---
	# Each room's bounds once, the rooms from left to right: a room is held against the ones that
	# start before it ends only (a world of hundreds of rooms is checked in a few ms).
	var bounds: Dictionary = {}
	for id in ids:
		bounds[id] = world.get_room_bounds(id)
	var by_x := ids.duplicate()
	by_x.sort_custom(func(p: String, q: String) -> bool: return (bounds[p] as Rect2).position.x < (bounds[q] as Rect2).position.x)
	var rects_of: Dictionary = {}
	var pairs: Array = []
	for i in by_x.size():
		var a: String = by_x[i]
		var ba: Rect2 = bounds[a]
		for j in range(i + 1, by_x.size()):
			var b: String = by_x[j]
			var bb: Rect2 = bounds[b]
			if bb.position.x >= ba.end.x:
				break
			if not ba.intersects(bb) or world.get_room_layer(a) != world.get_room_layer(b):
				continue
			for id in [a, b]:
				if not rects_of.has(id):
					rects_of[id] = world.get_world_rects(id)
			var overlap := false
			for ra: Rect2 in rects_of[a]:
				for rb: Rect2 in rects_of[b]:
					if ra.intersection(rb).get_area() > 1.0:
						overlap = true
			if overlap:
				# In the order the rooms are listed, as before.
				pairs.append([a, b] if ids.find(a) < ids.find(b) else [b, a])
	pairs.sort_custom(func(p: Array, q: Array) -> bool: return ids.find(p[0]) < ids.find(q[0]) or (p[0] == q[0] and ids.find(p[1]) < ids.find(q[1])))
	for pair: Array in pairs:
		MDSValidator._add(issues, W, CATEGORY_LAYOUT, "%s overlaps %s" % [analysis.get_room_name(pair[0]), analysis.get_room_name(pair[1])], pair[0], Vector3i.MAX, world.get_room_label_pos(pair[0]), world.get_room_layer(pair[0]))

	var pin_locator := func(pin: Dictionary) -> Dictionary:
		var pos := Vector2(float(pin.x), float(pin.y))
		return {"room_id": world.room_at(pos, int(pin.layer)), "pos": pos}
	MDSValidator.run_common(issues, world, analysis, pin_locator)
	return MDSValidator.sort_issues(issues)

static func _fmt_rect(r: Rect2) -> String:
	return "%dx%d at %d,%d" % [int(r.size.x), int(r.size.y), int(r.position.x), int(r.position.y)]
