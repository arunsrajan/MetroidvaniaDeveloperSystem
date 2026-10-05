@tool
class_name IDPWorldValidator
extends RefCounted
## Checks for non-linear worlds: rooms, scenes, gates and layout, plus the shared
## progression/design checks from [IDPValidator].

const CATEGORY_ROOMS := "Rooms & scenes"
const CATEGORY_GATES := "Gates"
const CATEGORY_LAYOUT := "Layout"

static func run(world: IDPWorld, analysis: IDPAnalysis, scene_db: Dictionary) -> Array:
	var issues: Array = []
	var W := IDPValidator.Severity.WARNING
	var E := IDPValidator.Severity.ERROR
	var I := IDPValidator.Severity.INFO
	var scene_users: Dictionary = {}
	var ids := world.get_room_ids()

	for id in ids:
		var name := analysis.get_room_name(id)
		var layer := world.get_room_layer(id)
		var at := world.get_room_label_pos(id)
		var path := world.get_scene_path(id)
		# --- Rooms & scenes ---
		if not world.has_scene_reference(id):
			IDPValidator._add(issues, W, CATEGORY_ROOMS, "%s has no scene yet. Right-click it > Create scene, or drop a .tscn on it" % name, id, Vector3i.MAX, at, layer)
		elif path.is_empty():
			IDPValidator._add(issues, E, CATEGORY_ROOMS, "%s: scene %s could not be found (deleted or moved outside the project?)" % [name, world.data.rooms[id].get("scene", "")], id, Vector3i.MAX, at, layer)
		else:
			if not scene_users.has(path):
				scene_users[path] = []
			scene_users[path].append(id)
		if not world.get_areas().is_empty() and world.get_room_area(id).is_empty():
			IDPValidator._add(issues, I, CATEGORY_ROOMS, "%s is not in any area" % name, id, Vector3i.MAX, at, layer)

		# --- Gates ---
		var gates := world.get_gates(id)
		if gates.is_empty() and ids.size() > 1:
			IDPValidator._add(issues, W, CATEGORY_GATES, "%s has no gates. Use the Gate tool (G) to add transitions" % name, id, Vector3i.MAX, at, layer)
		for gate_name in gates:
			var gate: Dictionary = gates[gate_name]
			var gpos := world.get_gate_world_pos(id, gate_name)
			var to: String = gate.get("to", "")
			var to_gate: String = gate.get("to_gate", "")
			if to.is_empty():
				if not gate.get("one_way", false):
					IDPValidator._add(issues, W, CATEGORY_GATES, "%s.%s is not connected. Drag from it to another gate" % [name, gate_name], id, Vector3i.MAX, gpos, layer)
				continue
			if not world.has_room(to):
				IDPValidator._add(issues, E, CATEGORY_GATES, "%s.%s leads to missing room '%s'" % [name, gate_name, to], id, Vector3i.MAX, gpos, layer)
				continue
			if not world.has_gate(to, to_gate):
				IDPValidator._add(issues, E, CATEGORY_GATES, "%s.%s leads to missing gate '%s' in %s" % [name, gate_name, to_gate, analysis.get_room_name(to)], id, Vector3i.MAX, gpos, layer)
				continue
			var back := world.get_gate(to, to_gate)
			var points_back: bool = back.get("to", "") == id and back.get("to_gate", "") == gate_name
			if not points_back and not gate.get("one_way", false):
				IDPValidator._add(issues, I, CATEGORY_GATES, "%s.%s -> %s.%s is one-way (the target gate doesn't lead back). Tick One-way if intended" % [name, gate_name, analysis.get_room_name(to), to_gate], id, Vector3i.MAX, gpos, layer)
			if world.get_room_layer(to) == layer:
				var dist := gpos.distance_to(world.get_gate_world_pos(to, to_gate))
				if dist > world.get_grid() * 4 and id < to:
					IDPValidator._add(issues, I, CATEGORY_LAYOUT, "%s.%s and %s.%s are %d px apart on the map. Move the rooms together, or keep it if it's an elevator/long corridor" % [name, gate_name, analysis.get_room_name(to), to_gate, int(dist)], id, Vector3i.MAX, gpos, layer)

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
				IDPValidator._add(issues, W, CATEGORY_LAYOUT, "%s: the scene's terrain (%s) extends past the room drawn on the map. Use Inspect > Fit to scene" % [name, _fmt_rect(content)], id, Vector3i.MAX, at, layer)
		for t in meta.get("twisted", []):
			IDPValidator.add_twisted_issue(issues, name, t, id, Vector3i.MAX, world.get_origin(id) + Vector2(t.position), layer)
		for o in meta.get("overlaps", []):
			IDPValidator.add_overlap_issue(issues, name, o, id, Vector3i.MAX, world.get_origin(id) + Vector2(o.position), layer)
		# Physics checks (IDPRoomCheck), run in the background by the panel.
		for g in meta.get("geometry", []):
			IDPValidator._add(issues, W, IDPValidator.CATEGORY_GEOMETRY, g.message, id, Vector3i.MAX, world.get_origin(id) + Vector2(g.pos), layer)
		var scene_gates: Dictionary = {}
		for t in meta.get("transitions", []):
			scene_gates[t.name] = t
			if not gates.has(t.name):
				IDPValidator._add(issues, W, CATEGORY_GATES, "%s: scene has gate '%s' that is not on the map. Inspect > Import gates from scene" % [name, t.name], id, Vector3i.MAX, at, layer)
		if not scene_gates.is_empty():
			for gate_name in gates:
				if not scene_gates.has(gate_name):
					IDPValidator._add(issues, I, CATEGORY_GATES, "%s.%s exists on the map but not in the scene. Inspect > Write gates to scene" % [name, gate_name], id, Vector3i.MAX, world.get_gate_world_pos(id, gate_name), layer)

	for path in scene_users:
		if scene_users[path].size() > 1:
			IDPValidator._add(issues, W, CATEGORY_ROOMS, "%s is used by %d rooms: %s" % [path.get_file(), scene_users[path].size(), ", ".join(scene_users[path])], scene_users[path][0])

	# --- Overlaps ---
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			if world.get_room_layer(a) != world.get_room_layer(b) or not world.get_room_bounds(a).intersects(world.get_room_bounds(b)):
				continue
			var overlap := false
			for ra in world.get_world_rects(a):
				for rb in world.get_world_rects(b):
					if ra.intersection(rb).get_area() > 1.0:
						overlap = true
			if overlap:
				IDPValidator._add(issues, W, CATEGORY_LAYOUT, "%s overlaps %s" % [analysis.get_room_name(a), analysis.get_room_name(b)], a, Vector3i.MAX, world.get_room_label_pos(a), world.get_room_layer(a))

	var pin_locator := func(pin: Dictionary) -> Dictionary:
		var pos := Vector2(float(pin.x), float(pin.y))
		return {"room_id": world.room_at(pos, int(pin.layer)), "pos": pos}
	IDPValidator.run_common(issues, world, analysis, pin_locator)
	return IDPValidator.sort_issues(issues)

static func _fmt_rect(r: Rect2) -> String:
	return "%dx%d at %d,%d" % [int(r.size.x), int(r.size.y), int(r.position.x), int(r.position.y)]
