@tool
class_name MDSWorld
extends MDSAnnotations
## Non-linear world map: rooms (scenes) placed freely in world pixels and connected by
## Hollow Knight-style named gates. Saved as [code]*.idpworld.json[/code].
##
## The format combines three proven ideas:
## - Tiled/LDtk "free" world layouts: every room is a scene at an x/y position in world
##   pixels, of any size, with no grid constraint.
## - Hollow Knight transitions: each room has named gates (left1, right1, top1, bot1,
##   door1...) and each gate stores its target room and the entry gate there. A gate whose
##   target doesn't lead back is a one-way transition (drops, collapsing floors).
## - Hollow Knight map zones: rooms belong to named, colored areas.
##
## [codeblock]
## {
##   "format": "idp_world", "version": 1, "name": "Pharloom",
##   "settings": {"grid": 32, "default_room_size": [1152, 648], "save_distance_warn": 4},
##   "layers": ["Main"],
##   "areas": {"The Greenhouse": {"color": "#5b6fd6", "map_zone": "GREENHOUSE", "label_pos": null}},
##   "rooms": {
##     "Greenhouse_01": {
##       "scene": "uid://b3x...", "scene_path": "res://rooms/greenhouse_01.tscn",
##       "area": "The Greenhouse", "layer": 0,
##       "origin": [4608, 1296],               # world position of the scene's (0, 0)
##       "rects": [[0, 0, 1152, 648], [1152, 324, 576, 324]],   # scene-local, any shape
##       "shape": [[0, 0, 1152, 0, 1728, 324, ...]],    # optional: its outline on the map (curves, slants)
##       "gates": {"right1": {"pos": [1728, 580], "side": "right", "to": "Greenhouse_02",
##                            "to_gate": "left1", "requires": ["dash"], "one_way": false}},
##       "type": "boss", "status": "blockout", "boss": "Moss Mother", "grants": [], "notes": ""
##     }
##   },
##   "links": [], "pins": [], "start_room": "Greenhouse_01"
## }
## [/codeblock]
## Rooms, gates and areas are also plain annotations, so [MDSAnalysis] and [MDSValidator]
## work on worlds exactly like on MetSys maps. At runtime use [method get_transition]
## (see [MDSGate]).

const FORMAT := "idp_world"
const WORLD_VERSION := 1
const EXTENSION := ".idpworld.json"
const SIDES: PackedStringArray = ["left", "right", "top", "bot", "door"]
const UNDO_LIMIT := 100

static var _cache: Dictionary = {}

var _undo: Array = []
var _redo: Array = []

func clear() -> void:
	data = {
		"format": FORMAT,
		"version": WORLD_VERSION,
		"name": "New World",
		"settings": {"grid": 32, "default_room_size": [1152, 648], "save_distance_warn": 4, "map_style": "handdrawn"},
		"layers": ["Main"],
		"areas": {},
		"rooms": {},
		"links": [],
		"pins": [],
		"start_room": "",
	}

static func is_world_file(file_path: String) -> bool:
	return file_path.ends_with(EXTENSION)

static func load_world(file_path: String) -> MDSWorld:
	var world := MDSWorld.new()
	world.path = file_path
	if FileAccess.file_exists(file_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file_path))
		if parsed is Dictionary and parsed.get("format", "") == FORMAT:
			for key in parsed:
				world.data[key] = parsed[key]
		else:
			push_warning("Metroidvania Developer System: %s is not an idp_world file" % file_path)
	return world

## Loads once and caches; for runtime lookups from many gates.
static func get_cached(file_path: String) -> MDSWorld:
	if not _cache.has(file_path):
		_cache[file_path] = load_world(file_path)
	return _cache[file_path]

# --- Undo --------------------------------------------------------------------------------

## Call before a user edit. Snapshots the whole world (cheap: plain dictionaries).
func checkpoint() -> void:
	_undo.append(data.duplicate(true))
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(data.duplicate(true))
	data = _undo.pop_back()
	_touch()
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(data.duplicate(true))
	data = _redo.pop_back()
	_touch()
	return true

# --- Settings, layers ---------------------------------------------------------------------

func get_grid() -> float:
	return maxf(1.0, float(get_setting("grid", 32)))

func snap(v: Vector2) -> Vector2:
	var g := get_grid()
	return (v / g).round() * g

func get_default_room_size() -> Vector2:
	var s: Array = get_setting("default_room_size", [1152, 648])
	return Vector2(float(s[0]), float(s[1]))

func get_world_name() -> String:
	return data.get("name", "World")

func get_layer_names() -> PackedStringArray:
	return PackedStringArray(data.get("layers", ["Main"]))

func get_layer_name(layer: int) -> String:
	var names := get_layer_names()
	return names[layer] if layer >= 0 and layer < names.size() and not names[layer].is_empty() else "Layer %d" % layer

func get_layers() -> Array[int]:
	var ret: Array[int] = []
	for i in get_layer_names().size():
		ret.append(i)
	for id in get_room_ids():
		var l := get_room_layer(id)
		if not l in ret:
			ret.append(l)
	ret.sort()
	return ret

# --- Areas --------------------------------------------------------------------------------

func get_areas() -> Dictionary:
	return data.areas

func has_area(area: String) -> bool:
	return data.areas.has(area)

func add_area(area: String, color := Color.TRANSPARENT) -> void:
	if area.is_empty() or data.areas.has(area):
		return
	if color.a == 0:
		color = MDSMapCanvas.area_color(area)
	data.areas[area] = {"color": "#" + color.to_html(false), "map_zone": area.to_upper().replace(" ", "_")}
	_touch()

func remove_area(area: String) -> void:
	data.areas.erase(area)
	for id in get_room_ids():
		if get_room_area(id) == area:
			data.rooms[id].erase("area")
	_touch()

func rename_area(old_name: String, new_name: String) -> void:
	if old_name == new_name or new_name.is_empty() or data.areas.has(new_name) or not data.areas.has(old_name):
		return
	data.areas[new_name] = data.areas[old_name]
	data.areas.erase(old_name)
	for id in get_room_ids():
		if get_room_area(id) == old_name:
			data.rooms[id].area = new_name
	_touch()

## Sets an area's [param key]; an empty string or array (or null) removes it.
func set_area_value(area: String, key: String, value: Variant) -> void:
	if data.areas.has(area):
		if value == null or (value is String and value.is_empty()) or (value is Array and value.is_empty()):
			data.areas[area].erase(key)
		else:
			data.areas[area][key] = value
		_touch()

func get_area_color(area: String) -> Color:
	if data.areas.has(area) and data.areas[area].has("color"):
		return Color(data.areas[area].color)
	return MDSMapCanvas.area_color(area)

## Custom label position (world px) or Vector2.INF to place it automatically.
func get_area_label_pos(area: String) -> Vector2:
	var p = data.areas.get(area, {}).get("label_pos")
	return Vector2(float(p[0]), float(p[1])) if p is Array and p.size() == 2 else Vector2.INF

func get_area_rooms(area: String) -> Array[String]:
	var ret: Array[String] = []
	for id in get_room_ids():
		if get_room_area(id) == area:
			ret.append(id)
	return ret

# --- Rooms --------------------------------------------------------------------------------

func get_room_ids() -> Array[String]:
	var ret: Array[String] = []
	ret.assign(data.rooms.keys())
	return ret

func has_room(id: String) -> bool:
	return not id.is_empty() and data.rooms.has(id)

## Returns a free id based on [param base] ("Greenhouse_01", "Greenhouse_02"...).
func unique_room_id(base: String) -> String:
	base = base.strip_edges().replace(" ", "_").replace(":", "_").replace("|", "_")
	if base.is_empty():
		base = "Room"
	if not data.rooms.has(base):
		return base
	var stem := base
	var n := 2
	var m := RegEx.create_from_string("^(.*?)_?(\\d+)$").search(base)
	if m:
		stem = m.get_string(1)
		n = m.get_string(2).to_int() + 1
	while data.rooms.has("%s_%02d" % [stem, n]):
		n += 1
	return "%s_%02d" % [stem, n]

## Adds a room made of one rect. [param world_rect] is in world pixels; the room origin
## (scene (0,0)) is placed at its top-left unless [param origin] is given.
func add_room(id: String, world_rect: Rect2, layer := 0, area := "", scene := "", origin := Vector2.INF) -> String:
	id = unique_room_id(id)
	if origin == Vector2.INF:
		origin = world_rect.position
	var local := Rect2(world_rect.position - origin, world_rect.size)
	var room := {
		"origin": [origin.x, origin.y],
		"rects": [[local.position.x, local.position.y, local.size.x, local.size.y]],
		"gates": {},
		"layer": layer,
	}
	if not area.is_empty():
		room.area = area
	data.rooms[id] = room
	if not scene.is_empty():
		set_room_scene(id, scene)
	_touch()
	return id

func remove_room(id: String) -> void:
	if not data.rooms.has(id):
		return
	for gate_name in get_gates(id).keys():
		disconnect_gate(id, gate_name)
	# Gates elsewhere pointing at this room become unconnected.
	for other in get_room_ids():
		for gate in get_gates(other).values():
			if gate.get("to", "") == id:
				gate.erase("to")
				gate.erase("to_gate")
	data.rooms.erase(id)
	var links: Array = data.links
	for i in range(links.size() - 1, -1, -1):
		if links[i].a == id or links[i].b == id:
			links.remove_at(i)
	if data.start_room == id:
		data.start_room = ""
	_touch()

func rename_room(old_id: String, new_id: String) -> String:
	new_id = new_id.strip_edges().replace(" ", "_").replace(":", "_").replace("|", "_")
	if old_id == new_id or new_id.is_empty() or not data.rooms.has(old_id):
		return old_id
	new_id = unique_room_id(new_id)
	data.rooms[new_id] = data.rooms[old_id]
	data.rooms.erase(old_id)
	for other in get_room_ids():
		for gate in get_gates(other).values():
			if gate.get("to", "") == old_id:
				gate.to = new_id
	for link in data.links:
		if link.a == old_id:
			link.a = new_id
		if link.b == old_id:
			link.b = new_id
	if data.start_room == old_id:
		data.start_room = new_id
	_touch()
	return new_id

## Copies a room (without its gate connections) next to the original.
func duplicate_room(id: String) -> String:
	if not data.rooms.has(id):
		return ""
	var copy: Dictionary = data.rooms[id].duplicate(true)
	for gate in copy.get("gates", {}).values():
		gate.erase("to")
		gate.erase("to_gate")
	copy.erase("scene")
	copy.erase("scene_path")
	var new_id := unique_room_id(id)
	var b := get_room_bounds(id)
	var o := get_origin(id) + Vector2(b.size.x + get_grid() * 2, 0)
	copy.origin = [o.x, o.y]
	data.rooms[new_id] = copy
	_touch()
	return new_id

func get_room_layer(id: String) -> int:
	return int(data.rooms.get(id, {}).get("layer", 0))

func get_room_area(id: String) -> String:
	return str(data.rooms.get(id, {}).get("area", ""))

func set_room_scene(id: String, scene_path: String) -> void:
	if not data.rooms.has(id):
		return
	var room: Dictionary = data.rooms[id]
	if scene_path.is_empty():
		room.erase("scene")
		room.erase("scene_path")
	else:
		var path := ResourceUID.ensure_path(scene_path) if scene_path.begins_with("uid://") else scene_path
		var uid := ResourceLoader.get_resource_uid(path) if ResourceLoader.exists(path) else ResourceUID.INVALID_ID
		room.scene = ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else path
		room.scene_path = path
	_touch()

## Resolves the room's scene through its uid first (survives moves), then its path.
func get_scene_path(id: String) -> String:
	var room: Dictionary = data.rooms.get(id, {})
	var scene: String = room.get("scene", "")
	if scene.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(scene)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
			return ResourceUID.get_id_path(uid)
	var p: String = room.get("scene_path", scene)
	return p if not p.is_empty() and ResourceLoader.exists(p) else ""

func has_scene_reference(id: String) -> bool:
	var room: Dictionary = data.rooms.get(id, {})
	return not str(room.get("scene", "")).is_empty() or not str(room.get("scene_path", "")).is_empty()

func find_room_by_scene(scene_path: String) -> String:
	for id in get_room_ids():
		if get_scene_path(id) == scene_path or data.rooms[id].get("scene_path", "") == scene_path:
			return id
	return ""

# --- Geometry -----------------------------------------------------------------------------

func get_origin(id: String) -> Vector2:
	var o: Array = data.rooms.get(id, {}).get("origin", [0, 0])
	return Vector2(float(o[0]), float(o[1]))

func set_origin(id: String, origin: Vector2) -> void:
	if data.rooms.has(id):
		data.rooms[id].origin = [origin.x, origin.y]
		_touch()

func get_local_rects(id: String) -> Array[Rect2]:
	var ret: Array[Rect2] = []
	for r in data.rooms.get(id, {}).get("rects", []):
		ret.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	return ret

func get_world_rects(id: String) -> Array[Rect2]:
	var o := get_origin(id)
	var ret: Array[Rect2] = []
	for r in get_local_rects(id):
		ret.append(Rect2(r.position + o, r.size))
	return ret

func get_room_bounds(id: String) -> Rect2:
	var rects := get_world_rects(id)
	if rects.is_empty():
		return Rect2(get_origin(id), Vector2.ZERO)
	var b := rects[0]
	for r in rects:
		b = b.merge(r)
	return b

func add_rect(id: String, world_rect: Rect2) -> void:
	if not data.rooms.has(id):
		return
	var before := get_world_rects(id)
	var local := Rect2(world_rect.position - get_origin(id), world_rect.size).abs()
	data.rooms[id].rects.append([local.position.x, local.position.y, local.size.x, local.size.y])
	_reshape(id, before)
	_touch()

func set_local_rect(id: String, index: int, local: Rect2) -> void:
	var rects: Array = data.rooms.get(id, {}).get("rects", [])
	if index >= 0 and index < rects.size():
		var before := get_world_rects(id)
		local = local.abs()
		rects[index] = [local.position.x, local.position.y, local.size.x, local.size.y]
		_reshape(id, before)
		_touch()

func remove_rect(id: String, index: int) -> bool:
	var rects: Array = data.rooms.get(id, {}).get("rects", [])
	if rects.size() <= 1 or index < 0 or index >= rects.size():
		return false
	var before := get_world_rects(id)
	rects.remove_at(index)
	_reshape(id, before)
	_touch()
	return true

## Whether the room's rectangles hold [param world_pos]: the room in the game, and its cells.
## [method room_shape_contains] follows its outline on the map instead.
func room_contains(id: String, world_pos: Vector2) -> bool:
	for r in get_world_rects(id):
		if r.has_point(world_pos):
			return true
	return false

## Topmost room at [param world_pos] on [param layer] (last added wins, like drawing order).
## With [param by_shape], rooms with an outline on the map ([method get_room_shape]) are hit
## only inside it, as they are drawn.
func room_at(world_pos: Vector2, layer: int, by_shape := false) -> String:
	var ids := get_room_ids()
	for i in range(ids.size() - 1, -1, -1):
		if get_room_layer(ids[i]) == layer and (room_shape_contains(ids[i], world_pos) if by_shape else room_contains(ids[i], world_pos)):
			return ids[i]
	return ""

# --- Outlines on the map ---------------------------------------------------------------------
# A room is made of rectangles (what the game, the camera and the paint cells use). Its outline
# on the map can follow curves and slants within them ("shape": polygons, scene-local, flat
# [x0, y0, x1, y1...] lists), as generated areas have. Without one it is drawn as its rects.

func has_room_shape(id: String) -> bool:
	return not data.rooms.get(id, {}).get("shape", []).is_empty()

## The room's outline on the map, scene-local polygons (none: drawn as its rectangles).
func get_local_shape(id: String) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for flat in data.rooms.get(id, {}).get("shape", []):
		var poly := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			poly.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if poly.size() >= 3:
			out.append(poly)
	return out

## The room's outline on the map in world px (see [method get_local_shape]).
func get_room_shape(id: String) -> Array[PackedVector2Array]:
	var o := get_origin(id)
	var out: Array[PackedVector2Array] = []
	for poly in get_local_shape(id):
		var moved := PackedVector2Array()
		moved.resize(poly.size())
		for i in poly.size():
			moved[i] = poly[i] + o
		out.append(moved)
	return out

## Sets the room's outline on the map ([param polys] in world px); empty: its rectangles.
func set_room_shape(id: String, polys: Array) -> void:
	if not data.rooms.has(id):
		return
	var o := get_origin(id)
	var flat_list: Array = []
	for poly: PackedVector2Array in polys:
		if poly.size() < 3:
			continue
		var flat: Array = []
		for p in poly:
			flat.append(snappedf(p.x - o.x, 0.1))
			flat.append(snappedf(p.y - o.y, 0.1))
		flat_list.append(flat)
	if flat_list.is_empty():
		data.rooms[id].erase("shape")
	else:
		data.rooms[id].shape = flat_list
	_touch()

## The room's outline on the map, else its rectangles, as world-px polygons.
func get_room_outline(id: String) -> Array[PackedVector2Array]:
	if has_room_shape(id):
		return get_room_shape(id)
	var out: Array[PackedVector2Array] = []
	for r in get_world_rects(id):
		out.append(MDSGeometry.rect_polygon(r))
	return out

## Whether the room's outline on the map holds [param world_pos] (its rects when it has none).
func room_shape_contains(id: String, world_pos: Vector2) -> bool:
	if not has_room_shape(id):
		return room_contains(id, world_pos)
	if not room_contains(id, world_pos):
		return false
	for poly in get_room_shape(id):
		if Geometry2D.is_point_in_polygon(world_pos, poly):
			return true
	return false

## After the room's rectangles changed from [param before] (world px): its outline keeps its
## curves where the room still is, and what was added comes in as plain rectangles.
func _reshape(id: String, before: Array[Rect2]) -> void:
	if not has_room_shape(id):
		return
	var now := get_world_rects(id)
	var pieces: Array[PackedVector2Array] = []
	for poly in get_room_shape(id):
		for r in now:
			pieces.append_array(Geometry2D.intersect_polygons(poly, MDSGeometry.rect_polygon(r)))
	for r in now:
		var left: Array[PackedVector2Array] = [MDSGeometry.rect_polygon(r)]
		for old in before:
			var next: Array[PackedVector2Array] = []
			for part in left:
				if MDSGeometry.bounds(part).intersects(old):
					next.append_array(MDSGeometry.without_holes(Geometry2D.clip_polygons(part, MDSGeometry.rect_polygon(old)), 1.0))
				else:
					next.append(part)
			left = next
		pieces.append_array(left)
	var kept: Array[PackedVector2Array] = []
	for piece in pieces:
		if not Geometry2D.is_polygon_clockwise(piece) and absf(MDSGeometry.signed_area(piece)) > 1.0:
			kept.append(piece)
	set_room_shape(id, MDSGeometry.union_all(kept, INF))

func get_layer_bounds(layer: int) -> Rect2:
	var b := Rect2()
	var first := true
	for id in get_room_ids():
		if get_room_layer(id) != layer:
			continue
		var r := get_room_bounds(id)
		b = r if first else b.merge(r)
		first = false
	return b

## Label anchor: center of the room's largest rect.
func get_room_label_pos(id: String) -> Vector2:
	var best := Rect2()
	for r in get_world_rects(id):
		if r.get_area() > best.get_area():
			best = r
	return best.get_center()

## Rooms whose rects touch this room's rects on the same layer (LDtk's "neighbours").
func get_touching_rooms(id: String, tolerance := 1.0) -> Array[String]:
	var ret: Array[String] = []
	var mine := get_world_rects(id)
	for other in get_room_ids():
		if other == id or get_room_layer(other) != get_room_layer(id):
			continue
		for a in mine:
			for b in get_world_rects(other):
				if a.grow(tolerance).intersects(b) and not other in ret:
					ret.append(other)
	return ret

## Where the room's outline is closest to [param world_pos]: {pos (world), side, normal}.
## Edges shared by two rects of the same room are skipped.
func nearest_edge_point(id: String, world_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	var rects := get_world_rects(id)
	for r in rects:
		var edges := [
			["left", r.position, Vector2(r.position.x, r.end.y), Vector2.LEFT],
			["right", Vector2(r.end.x, r.position.y), r.end, Vector2.RIGHT],
			["top", r.position, Vector2(r.end.x, r.position.y), Vector2.UP],
			["bot", Vector2(r.position.x, r.end.y), r.end, Vector2.DOWN],
		]
		for e in edges:
			var p := Geometry2D.get_closest_point_to_segment(world_pos, e[1], e[2])
			var outside: Vector2 = p + e[3] * 2.0
			var interior := false
			for other in rects:
				if other != r and other.has_point(outside):
					interior = true
			if interior:
				continue
			var d := p.distance_squared_to(world_pos)
			if d < best_d:
				best_d = d
				best = {"pos": p, "side": e[0], "normal": e[3]}
	return best

# --- Painting (map cells) ----------------------------------------------------------------------
# The brush paints on a coarser "paint cell" grid (default: a quarter of the default room
# size). A room's cells are the paint cells whose centers lie inside its rectangles; painting
# rebuilds the rectangles from the cells, so the saved format stays plain rects.

func get_paint_cell() -> Vector2:
	var c = get_setting("paint_cell", null)
	if c is Array and c.size() == 2 and float(c[0]) > 0 and float(c[1]) > 0:
		return Vector2(float(c[0]), float(c[1]))
	return (get_default_room_size() / 4.0).round()

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos / get_paint_cell()).floor())

func cell_to_world_rect(cell: Vector2i) -> Rect2:
	var s := get_paint_cell()
	return Rect2(Vector2(cell) * s, s)

## Paint cells covered by the room (cell centers inside its rects). Vector2i -> true.
func get_room_cells(id: String) -> Dictionary:
	var cells: Dictionary = {}
	var s := get_paint_cell()
	for r in get_world_rects(id):
		var c0 := Vector2i(((r.position) / s - Vector2(0.5, 0.5)).ceil())
		var c1 := Vector2i(((r.end) / s - Vector2(0.5, 0.5)).ceil()) - Vector2i.ONE
		for y in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				cells[Vector2i(x, y)] = true
	return cells

## Room on [param layer] whose shape covers the paint cell, or "".
func room_at_cell(cell: Vector2i, layer: int) -> String:
	return room_at(cell_to_world_rect(cell).get_center(), layer)

## Replaces the room's shape with [param cells] (merged into as few rects as possible).
## Returns false when [param cells] is empty (the room is left unchanged).
func set_room_cells(id: String, cells: Dictionary) -> bool:
	if cells.is_empty() or not data.rooms.has(id):
		return false
	var s := get_paint_cell()
	var origin := get_origin(id)
	var before := get_world_rects(id)
	var rects: Array = []
	for run in cells_to_runs(cells):
		var r := Rect2(Vector2(run[0], run[2]) * s, Vector2(run[1] - run[0] + 1, run[3] - run[2] + 1) * s)
		rects.append([r.position.x - origin.x, r.position.y - origin.y, r.size.x, r.size.y])
	data.rooms[id].rects = rects
	_reshape(id, before)
	_touch()
	return true

## Merges cells into rectangles: horizontal runs per row, then identical runs on consecutive
## rows. Returns [[x0, x1, y0, y1], ...] in cell units.
static func cells_to_runs(cells: Dictionary) -> Array:
	var rows: Dictionary = {}
	for c in cells:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	var ys: Array = rows.keys()
	ys.sort()
	var runs: Array = []
	var open: Dictionary = {} # "x0,x1" -> run extending down
	for y in ys:
		var xs: Array = rows[y]
		xs.sort()
		var row_runs: Array = []
		var i := 0
		while i < xs.size():
			var x0: int = xs[i]
			var x1: int = x0
			while i + 1 < xs.size() and xs[i + 1] == x1 + 1:
				i += 1
				x1 = xs[i]
			row_runs.append([x0, x1])
			i += 1
		var next_open: Dictionary = {}
		for rr in row_runs:
			var key := "%d,%d" % rr
			if open.has(key) and open[key][3] == y - 1:
				open[key][3] = y
				next_open[key] = open[key]
			else:
				var run := [rr[0], rr[1], y, y]
				runs.append(run)
				next_open[key] = run
		open = next_open
	return runs

## Adds [param cells] to room [param id] (cells owned by other rooms are skipped).
func paint_cells(id: String, cells: Array) -> void:
	if not data.rooms.has(id):
		return
	var mine := get_room_cells(id)
	var layer := get_room_layer(id)
	var changed := false
	for c in cells:
		if mine.has(c):
			continue
		var other := room_at_cell(c, layer)
		if not other.is_empty() and other != id:
			continue
		mine[c] = true
		changed = true
	if changed:
		set_room_cells(id, mine)

## Starts a new room from painted cells. Returns its id ("" if every cell is taken).
func add_room_from_cells(cells: Array, layer: int, area := "", base_id := "Room_01") -> String:
	var free: Array = cells.filter(func(c: Vector2i) -> bool: return room_at_cell(c, layer).is_empty())
	if free.is_empty():
		return ""
	var id := add_room(base_id, cell_to_world_rect(free[0]), layer, area)
	paint_cells(id, free)
	return id

## Removes [param cells] from every room on [param layer]; rooms left without cells are
## deleted. Returns the ids of the rooms that changed.
func erase_cells(cells: Array, layer: int) -> Array[String]:
	var by_room: Dictionary = {}
	for c in cells:
		var id := room_at_cell(c, layer)
		if id.is_empty():
			continue
		if not by_room.has(id):
			by_room[id] = []
		by_room[id].append(c)
	var changed: Array[String] = []
	for id in by_room:
		var mine := get_room_cells(id)
		for c in by_room[id]:
			mine.erase(c)
		if mine.is_empty():
			remove_room(id)
		else:
			set_room_cells(id, mine)
		changed.append(id)
	return changed

## Moves the room's origin (the scene's (0, 0)) without moving its shape or gates on the map.
## Used when a scene is dropped on a painted room: the scene's (0, 0) goes to the room's
## top-left corner.
func rebase_origin(id: String, new_origin: Vector2) -> void:
	if not data.rooms.has(id):
		return
	var delta := get_origin(id) - new_origin
	for r in data.rooms[id].get("rects", []):
		r[0] = float(r[0]) + delta.x
		r[1] = float(r[1]) + delta.y
	for gate in get_gates(id).values():
		var p: Array = gate.get("pos", [0, 0])
		gate.pos = [float(p[0]) + delta.x, float(p[1]) + delta.y]
	for flat in data.rooms[id].get("shape", []):
		for i in range(0, flat.size() - 1, 2):
			flat[i] = float(flat[i]) + delta.x
			flat[i + 1] = float(flat[i + 1]) + delta.y
	data.rooms[id].origin = [new_origin.x, new_origin.y]
	_touch()

## Adds a connected gate pair on the longest shared edge of every two touching rooms that
## aren't connected yet (the painted map's doors). Returns the number of pairs added.
func auto_gates_between_touching() -> int:
	var count := 0
	var ids := get_room_ids()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := ids[i]
			var b := ids[j]
			if get_room_layer(a) != get_room_layer(b) or _rooms_connected(a, b):
				continue
			var best := {}
			var best_len := 0.0
			for ra in get_world_rects(a):
				for rb in get_world_rects(b):
					for e in _shared_edges(ra, rb):
						if e.length > best_len:
							best_len = e.length
							best = e
			if best_len < 1.0:
				continue
			var ga := add_gate(a, best.mid, best.side_a, "", false)
			var gb := add_gate(b, best.mid, best.side_b, "", false)
			connect_gates(a, ga, b, gb)
			count += 1
	return count

func _rooms_connected(a: String, b: String) -> bool:
	for g in get_gates(a).values():
		if g.get("to", "") == b:
			return true
	for g in get_gates(b).values():
		if g.get("to", "") == a:
			return true
	return false

static func _shared_edges(ra: Rect2, rb: Rect2) -> Array:
	var out: Array = []
	var eps := 0.5
	if absf(ra.end.x - rb.position.x) < eps or absf(rb.end.x - ra.position.x) < eps:
		var y0 := maxf(ra.position.y, rb.position.y)
		var y1 := minf(ra.end.y, rb.end.y)
		if y1 - y0 > eps:
			var a_left := absf(ra.end.x - rb.position.x) < eps
			var x := ra.end.x if a_left else ra.position.x
			out.append({"length": y1 - y0, "mid": Vector2(x, (y0 + y1) / 2.0), "side_a": "right" if a_left else "left", "side_b": "left" if a_left else "right"})
	if absf(ra.end.y - rb.position.y) < eps or absf(rb.end.y - ra.position.y) < eps:
		var x0 := maxf(ra.position.x, rb.position.x)
		var x1 := minf(ra.end.x, rb.end.x)
		if x1 - x0 > eps:
			var a_top := absf(ra.end.y - rb.position.y) < eps
			var y := ra.end.y if a_top else ra.position.y
			out.append({"length": x1 - x0, "mid": Vector2((x0 + x1) / 2.0, y), "side_a": "bot" if a_top else "top", "side_b": "top" if a_top else "bot"})
	return out

# --- Gates (Hollow Knight transitions) ------------------------------------------------------

## Snaps an edge point to the grid along the edge, keeping it exactly on the edge.
func _snap_along_edge(edge: Dictionary) -> Vector2:
	var p: Vector2 = snap(edge.pos)
	if edge.side in ["left", "right"]:
		p.x = edge.pos.x
	else:
		p.y = edge.pos.y
	return p

func get_gates(id: String) -> Dictionary:
	var room: Dictionary = data.rooms.get(id, {})
	if not room.has("gates"):
		room["gates"] = {}
	return room.get("gates", {})

func get_gate(id: String, gate_name: String) -> Dictionary:
	return get_gates(id).get(gate_name, {}) if has_room(id) else {}

func has_gate(id: String, gate_name: String) -> bool:
	return has_room(id) and get_gates(id).has(gate_name)

func get_gate_local_pos(id: String, gate_name: String) -> Vector2:
	var p: Array = get_gate(id, gate_name).get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))

func get_gate_world_pos(id: String, gate_name: String) -> Vector2:
	return get_origin(id) + get_gate_local_pos(id, gate_name)

func get_gate_side(id: String, gate_name: String) -> String:
	return get_gate(id, gate_name).get("side", side_from_name(gate_name))

static func side_from_name(gate_name: String) -> String:
	for s in SIDES:
		if gate_name.begins_with(s):
			return s
	if gate_name.begins_with("bottom"):
		return "bot"
	return "door"

func next_gate_name(id: String, side: String) -> String:
	var n := 1
	while get_gates(id).has("%s%d" % [side, n]):
		n += 1
	return "%s%d" % [side, n]

## Adds a gate at [param world_pos]. With [param snap_to_edge] it moves to the closest
## outline point and takes that side. Returns the gate name.
func add_gate(id: String, world_pos: Vector2, side := "", gate_name := "", snap_to_edge := true) -> String:
	if not data.rooms.has(id):
		return ""
	var pos := world_pos
	if snap_to_edge:
		var edge := nearest_edge_point(id, world_pos)
		if not edge.is_empty():
			pos = _snap_along_edge(edge)
			if side.is_empty():
				side = edge.side
	if side.is_empty():
		side = "door"
	if gate_name.is_empty() or get_gates(id).has(gate_name):
		gate_name = next_gate_name(id, side)
	var local := snap(pos) - get_origin(id) if side == "door" else pos - get_origin(id)
	get_gates(id)[gate_name] = {"pos": [local.x, local.y], "side": side}
	_touch()
	return gate_name

func remove_gate(id: String, gate_name: String) -> void:
	if not has_gate(id, gate_name):
		return
	disconnect_gate(id, gate_name)
	for other in get_room_ids():
		for g in get_gates(other).values():
			if g.get("to", "") == id and g.get("to_gate", "") == gate_name:
				g.erase("to")
				g.erase("to_gate")
	get_gates(id).erase(gate_name)
	_touch()

func rename_gate(id: String, old_name: String, new_name: String) -> String:
	new_name = new_name.strip_edges()
	if not has_gate(id, old_name) or new_name.is_empty() or old_name == new_name or get_gates(id).has(new_name):
		return old_name
	var gates := get_gates(id)
	gates[new_name] = gates[old_name]
	gates.erase(old_name)
	for other in get_room_ids():
		for g in get_gates(other).values():
			if g.get("to", "") == id and g.get("to_gate", "") == old_name:
				g.to_gate = new_name
	_touch()
	return new_name

func set_gate_value(id: String, gate_name: String, key: String, value: Variant) -> void:
	if not has_gate(id, gate_name):
		return
	var gate: Dictionary = get_gates(id)[gate_name]
	var empty: bool = value == null or (value is String and value.is_empty()) or (value is Array and value.is_empty()) or (value is bool and not value)
	if empty:
		gate.erase(key)
	else:
		gate[key] = value
	_touch()

func set_gate_world_pos(id: String, gate_name: String, world_pos: Vector2, snap_to_edge := true) -> void:
	if not has_gate(id, gate_name):
		return
	var gate: Dictionary = get_gates(id)[gate_name]
	var pos := world_pos
	if snap_to_edge and gate.get("side", "") != "door":
		var edge := nearest_edge_point(id, world_pos)
		if not edge.is_empty():
			pos = _snap_along_edge(edge)
			gate.side = edge.side
	var local := pos - get_origin(id)
	gate.pos = [local.x, local.y]
	_touch()

## Connects gate [param a_gate] of room [param a] to [param b_gate] of room [param b].
## Two-way by default, like a normal Hollow Knight doorway.
func connect_gates(a: String, a_gate: String, b: String, b_gate: String, two_way := true) -> void:
	if not has_gate(a, a_gate) or not has_gate(b, b_gate) or (a == b and a_gate == b_gate):
		return
	disconnect_gate(a, a_gate)
	var ga: Dictionary = get_gates(a)[a_gate]
	ga.to = b
	ga.to_gate = b_gate
	if two_way:
		disconnect_gate(b, b_gate)
		var gb: Dictionary = get_gates(b)[b_gate]
		gb.to = a
		gb.to_gate = a_gate
	_touch()

## Clears the gate's target and, when the target pointed back, the target's too.
func disconnect_gate(id: String, gate_name: String) -> void:
	if not has_gate(id, gate_name):
		return
	var gate: Dictionary = get_gates(id)[gate_name]
	var to: String = gate.get("to", "")
	var to_gate: String = gate.get("to_gate", "")
	if has_gate(to, to_gate):
		var back: Dictionary = get_gates(to)[to_gate]
		if back.get("to", "") == id and back.get("to_gate", "") == gate_name:
			back.erase("to")
			back.erase("to_gate")
	gate.erase("to")
	gate.erase("to_gate")
	_touch()

## Pairs every unconnected gate with the nearest unconnected gate of another room within
## [param max_distance] world px (facing sides only). Returns the number of new connections.
func auto_connect_gates(max_distance := -1.0) -> int:
	if max_distance < 0:
		max_distance = get_grid() * 3.0
	var opposite := {"left": "right", "right": "left", "top": "bot", "bot": "top"}
	var count := 0
	for a in get_room_ids():
		for ga in get_gates(a).keys():
			var gate_a := get_gate(a, ga)
			if not str(gate_a.get("to", "")).is_empty():
				continue
			var side_a := get_gate_side(a, ga)
			var pa := get_gate_world_pos(a, ga)
			var best := []
			var best_d := max_distance
			for b in get_room_ids():
				if b == a or get_room_layer(b) != get_room_layer(a):
					continue
				for gb in get_gates(b).keys():
					if not str(get_gate(b, gb).get("to", "")).is_empty():
						continue
					if opposite.get(side_a, "") != get_gate_side(b, gb):
						continue
					var d := pa.distance_to(get_gate_world_pos(b, gb))
					if d <= best_d:
						best_d = d
						best = [b, gb]
			if not best.is_empty():
				connect_gates(a, ga, best[0], best[1])
				count += 1
	return count

## Canonical key of the transition between two gates (same for both directions).
static func edge_key(a: String, a_gate: String, b: String, b_gate: String) -> String:
	var ka := "%s:%s" % [a, a_gate]
	if b.is_empty():
		return ka
	var kb := "%s:%s" % [b, b_gate]
	return ka + "|" + kb if ka < kb else kb + "|" + ka

## Runtime lookup, the equivalent of Hollow Knight's TransitionPoint targetScene/entryPoint.
## Returns {room, gate, scene_path, entry_pos (target scene-local), side} or {}.
func get_transition(room_id: String, gate_name: String) -> Dictionary:
	var gate := get_gate(room_id, gate_name)
	var to: String = gate.get("to", "")
	if to.is_empty() or not has_room(to):
		return {}
	var to_gate: String = gate.get("to_gate", "")
	return {
		"room": to,
		"gate": to_gate,
		"scene_path": get_scene_path(to),
		"entry_pos": get_gate_local_pos(to, to_gate) if has_gate(to, to_gate) else Vector2.ZERO,
		"side": get_gate_side(to, to_gate) if has_gate(to, to_gate) else "",
	}

## Runtime lookup of a map link used as a fast-travel pair (an [MDSGate] with
## [member MDSGate.link] on): the link of [param room_id] whose end here is
## [param gate_name] (a link with no gate named at this end matches any gate). Returns
## {room, gate, scene_path, entry_pos, side, link: true, requires, note} or {}.
func get_link_transition(room_id: String, gate_name: String) -> Dictionary:
	for link in get_links():
		for ends in [["a", "b"], ["b", "a"]]:
			if link.get(ends[0], "") != room_id:
				continue
			var here := str(link.get(ends[0] + "_gate", ""))
			if not here.is_empty() and here != gate_name:
				continue
			var to: String = link.get(ends[1], "")
			if not has_room(to):
				continue
			var there := str(link.get(ends[1] + "_gate", ""))
			return {
				"room": to,
				"gate": there,
				"scene_path": get_scene_path(to),
				"entry_pos": get_gate_local_pos(to, there) if has_gate(to, there) else Vector2.ZERO,
				"side": get_gate_side(to, there) if has_gate(to, there) else "door",
				"link": true,
				"requires": link.get("requires", []),
				"note": link.get("note", ""),
			}
	return {}

# --- MDSAnnotations overrides (world stores door data on gates) -----------------------------

func _gates_of_key(key: String) -> Array:
	var ret: Array = []
	for part in key.split("|"):
		var room := part.get_slice(":", 0)
		var gate := part.get_slice(":", 1)
		if has_gate(room, gate):
			ret.append([room, gate])
	return ret

func get_door(key: String) -> Dictionary:
	var parts := _gates_of_key(key)
	return get_gate(parts[0][0], parts[0][1]) if not parts.is_empty() else {}

func get_door_requires(key: String) -> PackedStringArray:
	var ret: PackedStringArray = []
	for p in _gates_of_key(key):
		for r in get_gate(p[0], p[1]).get("requires", []):
			if not r in ret:
				ret.append(r)
	return ret

func set_door_value(key: String, field: String, value: Variant) -> void:
	var parts := _gates_of_key(key)
	if parts.is_empty():
		return
	set_gate_value(parts[0][0], parts[0][1], field, value)
	for i in range(1, parts.size()):
		set_gate_value(parts[i][0], parts[i][1], field, null)

## One-way-ness is structural in worlds (see MDSGraph.from_world).
func get_door_one_way_from(_key: String) -> String:
	return ""

func get_known_abilities() -> PackedStringArray:
	var ret: PackedStringArray = []
	for id in get_room_ids():
		for a in get_room_grants(id):
			if not a in ret:
				ret.append(a)
		for gate in get_gates(id).values():
			for a in gate.get("requires", []):
				if not a in ret:
					ret.append(a)
	ret.sort()
	return ret

# --- Import from MetSys ---------------------------------------------------------------------

## Builds a world from a MetSys map (and its panel annotations): each room becomes a scene
## placed at its cell position, cells merge into rects, passages become named gates.
static func from_metsys(model: MDSMapModel, ann: MDSAnnotations, cell_size: Vector2) -> MDSWorld:
	var world := MDSWorld.new()
	world.data.name = model.source_path.get_file().get_basename()
	world.data.settings.default_room_size = [cell_size.x, cell_size.y]
	world.data.settings.grid = 32
	var layer_names: Array = []
	for l in model.layers:
		while layer_names.size() <= l:
			layer_names.append("")
		layer_names[l] = model.get_layer_name(l)
	world.data.layers = layer_names if not layer_names.is_empty() else ["Main"]
	var ids: Dictionary = {} # MetSys room id -> world id
	var sorted: Array = model.rooms.values()
	sorted.sort_custom(func(a: MDSMapModel.Room, b: MDSMapModel.Room) -> bool:
		return [a.layer, a.min_cell.y, a.min_cell.x] < [b.layer, b.min_cell.y, b.min_cell.x])
	for room: MDSMapModel.Room in sorted:
		var base := room.scene_path.get_file().get_basename() if not room.scene_path.is_empty() else "Room_%d_%d" % [room.min_cell.x, room.min_cell.y]
		var id := world.unique_room_id(base)
		ids[room.id] = id
		var origin := Vector2(room.min_cell) * cell_size
		var entry := {"origin": [origin.x, origin.y], "rects": _cells_to_rects(room, cell_size), "gates": {}, "layer": room.layer}
		if not room.scene_uid.is_empty():
			entry.scene = room.scene_uid
			if not room.scene_path.is_empty():
				entry.scene_path = room.scene_path
		var ann_room := ann.get_room(room.id)
		for key in ["name", "type", "status", "boss", "grants", "notes"]:
			if ann_room.has(key):
				entry[key] = ann_room[key]
		var area: String = ann_room.get("area", "")
		if area.is_empty():
			var groups := model.get_room_group_names(room)
			area = groups[0] if not groups.is_empty() else ""
		if not area.is_empty():
			entry.area = area
			if not world.data.areas.has(area):
				world.data.areas[area] = {"color": "#" + MDSMapCanvas.area_color(area).to_html(false), "map_zone": area.to_upper().replace(" ", "_")}
		world.data.rooms[id] = entry
	# Passages -> gates, named per side like Hollow Knight (left1, right1, ...).
	var dir_side := ["right", "bot", "left", "top"]
	for door: MDSMapModel.Door in model.doors.values():
		var a_id: String = ids[door.a_room.id]
		var ga := _add_metsys_gate(world, a_id, door.a_room, door.a_cell, door.a_dir, dir_side, cell_size)
		var reqs := ann.get_door_requires(door.key)
		if not reqs.is_empty():
			world.data.rooms[a_id].gates[ga].requires = Array(reqs)
		if not door.b_room:
			continue
		var b_id: String = ids[door.b_room.id]
		var gb := _add_metsys_gate(world, b_id, door.b_room, door.b_cell, (door.a_dir + 2) % 4, dir_side, cell_size)
		var one_way := ann.get_door_one_way_from(door.key)
		# One-sided MetSys passages keep a two-way connection; explicit one-ways become
		# exit-only gates.
		world.data.rooms[a_id].gates[ga].merge({"to": b_id, "to_gate": gb})
		world.data.rooms[b_id].gates[gb].merge({"to": a_id, "to_gate": ga})
		if one_way == door.a_room.id:
			world.data.rooms[a_id].gates[ga].one_way = true
			world.data.rooms[b_id].gates[gb].erase("to")
			world.data.rooms[b_id].gates[gb].erase("to_gate")
		elif one_way == door.b_room.id:
			world.data.rooms[b_id].gates[gb].one_way = true
			world.data.rooms[a_id].gates[ga].erase("to")
			world.data.rooms[a_id].gates[ga].erase("to_gate")
	for link in ann.get_links():
		if ids.has(link.a) and ids.has(link.b):
			var l: Dictionary = link.duplicate(true)
			l.a = ids[link.a]
			l.b = ids[link.b]
			world.data.links.append(l)
	for pin in ann.get_pins():
		var p: Dictionary = pin.duplicate(true)
		p.x = float(pin.x) * cell_size.x
		p.y = float(pin.y) * cell_size.y
		world.data.pins.append(p)
	world.data.start_room = ids.get(ann.get_start_room(), "")
	return world

static func _add_metsys_gate(world: MDSWorld, id: String, room: MDSMapModel.Room, cell: Vector3i, dir: int, dir_side: Array, cell_size: Vector2) -> String:
	var side: String = dir_side[dir]
	var gate_name := world.next_gate_name(id, side)
	var local_cell := Vector2(cell.x - room.min_cell.x, cell.y - room.min_cell.y)
	var pos := (local_cell + Vector2(0.5, 0.5) + Vector2(MDSMapModel.FWD[dir]) * 0.5) * cell_size
	world.data.rooms[id].gates[gate_name] = {"pos": [pos.x, pos.y], "side": side}
	return gate_name

## Merges a room's cells into few rects: horizontal runs per row, then identical runs on
## consecutive rows.
static func _cells_to_rects(room: MDSMapModel.Room, cell_size: Vector2) -> Array:
	var runs: Array = [] # [x0, x1, y0, y1] in local cells
	for y in range(room.min_cell.y, room.max_cell.y + 1):
		var x := room.min_cell.x
		while x <= room.max_cell.x:
			if room.has_cell(Vector2i(x, y)):
				var x0 := x
				while x <= room.max_cell.x and room.has_cell(Vector2i(x, y)):
					x += 1
				var merged := false
				for run in runs:
					if run[0] == x0 and run[1] == x - 1 and run[3] == y - 1:
						run[3] = y
						merged = true
						break
				if not merged:
					runs.append([x0, x - 1, y, y])
			else:
				x += 1
	var rects: Array = []
	for run in runs:
		var p := Vector2(run[0] - room.min_cell.x, run[2] - room.min_cell.y) * cell_size
		var s := Vector2(run[1] - run[0] + 1, run[3] - run[2] + 1) * cell_size
		rects.append([p.x, p.y, s.x, s.y])
	return rects
