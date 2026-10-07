@tool
class_name MDSValidator
extends RefCounted
## Checks the map for data errors and common metroidvania design problems.
## Every issue points at a room or cell so the panel can jump to it.

enum Severity { INFO, WARNING, ERROR }

const CATEGORY_DATA := "Map data"
const CATEGORY_LAYOUT := "Room layout"
const CATEGORY_PROGRESSION := "Progression"
const CATEGORY_DESIGN := "Design"
const CATEGORY_NOTES := "Pins & notes"
const CATEGORY_GEOMETRY := "Geometry"

## Returns an Array of {severity, category, message, room_id, cell: Vector3i}.
static func run(model: MDSMapModel, ann: MDSAnnotations, analysis: MDSAnalysis, scene_db: Dictionary, scanned_scene_paths: Array = []) -> Array:
	var issues: Array = []

	# --- Map data -------------------------------------------------------------
	for room: MDSMapModel.Room in model.rooms.values():
		var name := analysis.get_room_name(room.id)
		if room.scene_uid.is_empty():
			_add(issues, Severity.WARNING, CATEGORY_DATA, "No scene assigned to %d cell(s) at %s" % [room.cells.size(), _fmt(room.cells[0])], room.id, room.cells[0])
		elif room.scene_path.is_empty():
			_add(issues, Severity.ERROR, CATEGORY_DATA, "Scene %s could not be resolved (deleted or moved outside the project?)" % room.scene_uid, room.id, room.cells[0])
		for c in room.cells:
			var cell := model.get_cell(c)
			for d in 4:
				if cell.borders[d] != MDSMapModel.BORDER_NONE:
					continue
				var n := c + Vector3i(MDSMapModel.FWD[d].x, MDSMapModel.FWD[d].y, 0)
				if not model.cells.has(n):
					_add(issues, Severity.WARNING, CATEGORY_DATA, "%s: open edge (%s side of %s) leads outside the map" % [name, MDSMapModel.DIR_NAMES[d], _fmt(c)], room.id, c)
	for uid in model.split_scenes:
		var room := model.get_room(uid)
		_add(issues, Severity.ERROR, CATEGORY_DATA, "%s is assigned to several disconnected cell regions; MetSys only keeps one" % analysis.get_room_name(uid), uid, room.cells[0] if room else Vector3i.MAX)
	for door: MDSMapModel.Door in model.doors.values():
		var a_name := analysis.get_room_name(door.a_room.id)
		if door.leads_nowhere():
			_add(issues, Severity.WARNING, CATEGORY_DATA, "%s: passage to nowhere (%s side of %s)" % [a_name, MDSMapModel.DIR_NAMES[door.a_dir], _fmt(door.a_cell)], door.a_room.id, door.a_cell)
		elif door.is_one_sided() and ann.get_door_one_way_from(door.key).is_empty():
			var open_room := door.a_room if door.a_border > 0 else door.b_room
			var wall_room := door.b_room if door.a_border > 0 else door.a_room
			_add(issues, Severity.WARNING, CATEGORY_DATA, "Passage %s -> %s hits a wall on the other side. Mark it one-way in the Inspector if intended" % [analysis.get_room_name(open_room.id), analysis.get_room_name(wall_room.id)], open_room.id, door.cell_of(open_room))

	# --- Room layout vs. scene content -----------------------------------------
	var placed_paths: Dictionary = {}
	for room: MDSMapModel.Room in model.rooms.values():
		if room.scene_path.is_empty():
			continue
		placed_paths[room.scene_path] = true
		var meta: Dictionary = scene_db.get(room.scene_path, {})
		if meta.is_empty() or meta.occupied_cells.is_empty():
			continue
		var name := analysis.get_room_name(room.id)
		var outside: Array = []
		for local in meta.occupied_cells:
			if not room.has_cell(room.min_cell + Vector2i(local)):
				outside.append(local)
		if not outside.is_empty():
			var world := room.min_cell + Vector2i(outside[0])
			_add(issues, Severity.WARNING, CATEGORY_LAYOUT, "%s: terrain extends into %d cell(s) not assigned on the map (e.g. local %s). Resize the room in MetSys" % [name, outside.size(), outside[0]], room.id, Vector3i(world.x, world.y, room.layer))
		var occupied: Dictionary = {}
		for local in meta.occupied_cells:
			occupied[Vector2i(local)] = true
		for c in room.cells:
			if not occupied.has(Vector2i(c.x, c.y) - room.min_cell):
				_add(issues, Severity.INFO, CATEGORY_LAYOUT, "%s: assigned cell %s has no terrain yet" % [name, _fmt(c)], room.id, c)
	for room: MDSMapModel.Room in model.rooms.values():
		var meta: Dictionary = scene_db.get(room.scene_path, {})
		for t in meta.get("twisted", []):
			var cell: Vector2i = room.min_cell + Vector2i(t.get("cell", Vector2i.ZERO))
			add_twisted_issue(issues, analysis.get_room_name(room.id), t, room.id, Vector3i(cell.x, cell.y, room.layer))
		for o in meta.get("overlaps", []):
			var cell: Vector2i = room.min_cell + Vector2i(o.get("cell", Vector2i.ZERO))
			add_overlap_issue(issues, analysis.get_room_name(room.id), o, room.id, Vector3i(cell.x, cell.y, room.layer))
		# Physics checks (MDSRoomCheck), run in the background by the panel.
		for g in meta.get("geometry", []):
			var cell: Vector2i = room.min_cell + Vector2i(g.get("cell", Vector2i.ZERO))
			_add(issues, Severity.WARNING, CATEGORY_GEOMETRY, g.message, room.id, Vector3i(cell.x, cell.y, room.layer))
	for path in scanned_scene_paths:
		if not placed_paths.has(path) and scene_db.has(path):
			_add(issues, Severity.INFO, CATEGORY_LAYOUT, "%s has a RoomInstance but is not placed on this map" % path.get_file())

	var pin_locator := func(pin: Dictionary) -> Dictionary:
		var c := Vector3i(floori(pin.x), floori(pin.y), int(pin.layer))
		var room := model.get_room_at(c)
		return {"room_id": room.id if room else "", "cell": c}
	run_common(issues, ann, analysis, pin_locator)
	return sort_issues(issues)

## Checks shared by every mode: progression, design heuristics, pins and notes.
## [param pin_locator] maps a pin Dictionary to {room_id, cell?, pos?} for jumping.
static func run_common(issues: Array, ann: MDSAnnotations, analysis: MDSAnalysis, pin_locator: Callable) -> void:
	var graph := analysis.graph
	# --- Progression -------------------------------------------------------------
	if not analysis.start_room_id.is_empty():
		for id in analysis.locked:
			_add(issues, Severity.WARNING, CATEGORY_PROGRESSION, "%s can never be entered: its requirements are never granted before it" % analysis.get_room_name(id), id)
		for id in analysis.disconnected:
			var room := graph.get_room(id)
			if room and not room.has_scene:
				continue
			_add(issues, Severity.WARNING, CATEGORY_PROGRESSION, "%s is not connected to the start room. Add a door or a link (elevator/teleport) in the Inspector" % analysis.get_room_name(id), id)
	for ability in analysis.all_required:
		if not ability in analysis.all_granted:
			_add(issues, Severity.ERROR, CATEGORY_PROGRESSION, "'%s' is required by a door but no room grants it" % ability)
	for ability in analysis.all_granted:
		if not ability in analysis.all_required:
			_add(issues, Severity.INFO, CATEGORY_PROGRESSION, "'%s' is granted but no door requires it (no backtracking payoff)" % ability, analysis.get_ability_sources(ability)[0])

	for o in analysis.get_objectives():
		if not str(o.problem).is_empty():
			var where: String = o.rooms[0] if not o.rooms.is_empty() else ""
			_add(issues, Severity.ERROR, CATEGORY_PROGRESSION, "The objective of %s (\"%s\") can never complete: %s" % [o.area, o.text if not str(o.text).is_empty() else o.condition, o.problem], where)

	# --- Design heuristics -------------------------------------------------------
	var warn_distance: int = int(ann.get_setting("save_distance_warn", 4))
	var any_save := analysis.room_info.values().any(func(i: Dictionary) -> bool: return i.is_save)
	for id in analysis.room_info:
		var info: Dictionary = analysis.room_info[id]
		var room := graph.get_room(id)
		if not room.has_scene:
			continue
		var dist: int = analysis.save_distance.get(id, -1)
		if info.is_boss and any_save:
			if dist < 0 or dist > 2:
				_add(issues, Severity.WARNING, CATEGORY_DESIGN, "Boss room %s is %s from the nearest save point; players will have a long run back after dying" % [info.name, "%d rooms" % dist if dist >= 0 else "unreachable"], id)
		elif any_save and dist > warn_distance:
			_add(issues, Severity.INFO, CATEGORY_DESIGN, "%s is %d rooms from the nearest save point" % [info.name, dist], id)
		if id in analysis.dead_ends and info.scanned and info.collectibles == 0 and info.grants.is_empty() \
				and not (info.is_save or info.is_boss or info.is_shop or info.is_teleporter) \
				and not info.type in ["npc", "secret", "treasure", "transition"]:
			_add(issues, Severity.INFO, CATEGORY_DESIGN, "%s is a dead end with no reward. Consider an item, NPC or shortcut" % info.name, id)

	# --- Pins ----------------------------------------------------------------------
	for pin in ann.get_pins():
		if pin.get("kind", "note") in ["todo", "bug"]:
			var where: Dictionary = pin_locator.call(pin)
			_add(issues, Severity.INFO, CATEGORY_NOTES, "%s: %s" % [str(pin.kind).to_upper(), pin.text], where.get("room_id", ""), where.get("cell", Vector3i.MAX), where.get("pos", Vector2.INF), int(pin.layer))
	for id in ann.data.rooms:
		var notes: String = ann.get_room_value(id, "notes", "")
		if notes.to_lower().contains("todo"):
			_add(issues, Severity.INFO, CATEGORY_NOTES, "%s: %s" % [analysis.get_room_name(id), notes.get_slice("\n", 0)], id)

## A scanned outline that crosses itself ({path, kind, position} from the scanner).
static func add_twisted_issue(issues: Array, room_name: String, t: Dictionary, room_id: String, cell := Vector3i.MAX, pos := Vector2.INF, layer := 0) -> void:
	var what := "freeform shape %s" % t.path if t.get("kind", "") == "freeform" else "collision polygon %s" % t.path
	var fix := "select it in the Room view and press Repair" if t.get("kind", "") == "freeform" else "move its points apart in the scene"
	_add(issues, Severity.ERROR, CATEGORY_GEOMETRY, "%s: %s crosses itself (no fill, no collision); %s" % [room_name, what, fix], room_id, cell, pos, layer)

## Two objects that stand in or behind each other ({a, b, position} from the scanner).
static func add_overlap_issue(issues: Array, room_name: String, o: Dictionary, room_id: String, cell := Vector3i.MAX, pos := Vector2.INF, layer := 0) -> void:
	_add(issues, Severity.INFO, CATEGORY_GEOMETRY, "%s: objects overlap: %s and %s (Room view > Declutter separates them)" % [room_name, o.a, o.b], room_id, cell, pos, layer)

static func sort_issues(issues: Array) -> Array:
	issues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.severity != b.severity:
			return a.severity > b.severity
		return a.category < b.category)
	return issues

## [param cell] locates MetSys issues, [param pos] (world pixels) non-linear ones.
static func _add(issues: Array, severity: int, category: String, message: String, room_id := "", cell := Vector3i.MAX, pos := Vector2.INF, layer := 0) -> void:
	issues.append({"severity": severity, "category": category, "message": message, "room_id": room_id, "cell": cell, "pos": pos, "layer": layer})

static func _fmt(c: Vector3i) -> String:
	return "(%d,%d)" % [c.x, c.y]
