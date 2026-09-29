@tool
class_name IDPMapModel
extends RefCounted
## Parsed, analysis-friendly view of a MetSys MapData.txt file.
##
## Mirrors MetSys' own loader (MapData.gd): cells are grouped into rooms by flood-filling
## across "no border" (-1) edges, so irregular multi-cell rooms (L, T, U shapes...) keep
## their exact footprint. Passages between rooms become [Door]s that analysis and the
## map canvas share.

const R := 0
const D := 1
const L := 2
const U := 3
const FWD: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const DIR_NAMES: PackedStringArray = ["Right", "Down", "Left", "Up"]
const DIR_SHORT: PackedStringArray = ["R", "D", "L", "U"]

## MetSys border values. 2+ are theme-specific custom borders (locked doors etc.).
const BORDER_NONE := -1
const BORDER_WALL := 0
const BORDER_PASSAGE := 1

class Cell:
	var coords: Vector3i
	var borders: PackedInt32Array = [0, 0, 0, 0]
	var color := Color.TRANSPARENT
	var border_colors: Array[Color] = [Color.TRANSPARENT, Color.TRANSPARENT, Color.TRANSPARENT, Color.TRANSPARENT]
	var symbol := -1
	var scene_uid := ""
	var room: Room

class Room:
	## Stable id: the scene UID, or "unassigned:x,y,z" for cells without a scene.
	var id := ""
	var scene_uid := ""
	var scene_path := ""
	var layer := 0
	var cells: Array[Vector3i] = []
	var min_cell := Vector2i.MAX
	var max_cell := Vector2i.MIN
	var doors: Array[Door] = []
	var _cell_set: Dictionary = {}

	func has_cell(p: Vector2i) -> bool:
		return _cell_set.has(p)

	func get_display_name() -> String:
		if not scene_path.is_empty():
			return scene_path.get_file().get_basename()
		if not scene_uid.is_empty():
			return scene_uid
		return "Unassigned %d,%d" % [min_cell.x, min_cell.y]

	## Bounding rectangle in cell units.
	func get_rect() -> Rect2i:
		return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)

	func is_irregular() -> bool:
		var r := get_rect()
		return cells.size() != r.size.x * r.size.y

	## Cell used to anchor labels. For irregular rooms the bounding-box center can fall
	## outside the room, so pick the room cell closest to the centroid.
	func get_label_cell() -> Vector2i:
		var centroid := Vector2.ZERO
		for c in cells:
			centroid += Vector2(c.x, c.y)
		centroid /= max(1, cells.size())
		var best := Vector2i(cells[0].x, cells[0].y)
		var best_d := INF
		for c in cells:
			var d := Vector2(c.x, c.y).distance_squared_to(centroid)
			if d < best_d:
				best_d = d
				best = Vector2i(c.x, c.y)
		return best

	func get_neighbor_rooms() -> Array[Room]:
		var ret: Array[Room] = []
		for door in doors:
			var other := door.other(self)
			if other and other != self and not other in ret:
				ret.append(other)
		return ret

## A passage on the edge between two cells. Each physical edge is a single Door, even
## when both cells mark it as a passage.
class Door:
	## Canonical key, always expressed from the left/top cell ("x,y,z:R" or "x,y,z:D").
	var key := ""
	var a_room: Room
	var a_cell: Vector3i
	var a_dir := 0
	var a_border := 0
	var b_room: Room ## null for a passage to nowhere.
	var b_cell: Vector3i
	var b_border := -2 ## -2 when there's no cell on the other side.

	func other(room: Room) -> Room:
		return b_room if room == a_room else a_room

	func cell_of(room: Room) -> Vector3i:
		return a_cell if room == a_room else b_cell

	func dir_of(room: Room) -> int:
		return a_dir if room == a_room else (a_dir + 2) % 4

	func border_of(room: Room) -> int:
		return a_border if room == a_room else b_border

	func leads_nowhere() -> bool:
		return b_room == null

	## True when only one side draws a passage and the other side is a wall.
	func is_one_sided() -> bool:
		return b_room != null and ((a_border > 0) != (b_border > 0))

	## Highest custom border index on either side (0 wall, 1 passage, 2+ custom).
	func get_border_type() -> int:
		return max(a_border, b_border)

class CustomElement:
	var coords: Vector3i
	var name := ""
	var size := Vector2i.ONE
	var data := ""

var source_path := ""
var layer_names: PackedStringArray = []
var group_names: PackedStringArray = []
var cell_groups: Dictionary = {} ## int -> Array[Vector3i]
var cells: Dictionary = {} ## Vector3i -> Cell
var rooms: Dictionary = {} ## String id -> Room
var doors: Dictionary = {} ## String key -> Door
var custom_elements: Array[CustomElement] = []
var layers: Array[int] = []
## Scenes whose cells form more than one disconnected region (MetSys only keeps one).
var split_scenes: PackedStringArray = []

var _group_cache: Dictionary = {} ## Vector3i -> PackedInt32Array

static func load_file(path: String) -> IDPMapModel:
	var model := IDPMapModel.new()
	model.source_path = path
	if not FileAccess.file_exists(path):
		return model
	model.parse_text(FileAccess.get_file_as_string(path))
	return model

## Parses MapData text. Same section order as MetSys: layer names, cell groups, custom
## elements, then cells ("[x,y,z]" followed by the cell data line).
func parse_text(text: String) -> void:
	var lines := text.split("\n")
	var section := 0 # 0 groups, 1 custom elements, 2 cells
	var i := 0
	while i < lines.size():
		var line := lines[i].strip_edges()
		i += 1
		if line.is_empty():
			continue
		if line.begins_with("$ln"):
			layer_names = line.split(";").slice(1)
		elif line.begins_with("["):
			section = 2
			var coords := _parse_coords(line.trim_prefix("[").trim_suffix("]"))
			var data_line := lines[i].strip_edges() if i < lines.size() else ""
			i += 1
			cells[coords] = _parse_cell(coords, data_line)
		elif section == 1 or (section == 0 and line.contains("/")):
			section = 1
			var parts := line.split("/")
			if parts.size() < 3:
				continue
			var element := CustomElement.new()
			element.coords = _parse_coords(parts[0])
			element.name = parts[1]
			element.size = Vector2i(parts[2].get_slice("x", 0).to_int(), parts[2].get_slice("x", 1).to_int())
			element.data = parts[3] if parts.size() > 3 else ""
			custom_elements.append(element)
		elif section == 0:
			var parts := line.split(":")
			var group_id := parts[0].get_slice(";", 0).to_int()
			var group_cells: Array[Vector3i] = []
			for j in range(1, parts.size()):
				group_cells.append(_parse_coords(parts[j]))
			cell_groups[group_id] = group_cells
			if parts[0].get_slice_count(";") > 1:
				if group_names.size() < group_id + 1:
					group_names.resize(group_id + 1)
				group_names[group_id] = parts[0].get_slice(";", 1)
			for c in group_cells:
				if not _group_cache.has(c):
					_group_cache[c] = PackedInt32Array()
				_group_cache[c].append(group_id)
	_build_rooms()
	_build_doors()

func _parse_coords(s: String) -> Vector3i:
	return Vector3i(s.get_slice(",", 0).to_int(), s.get_slice(",", 1).to_int(), s.get_slice(",", 2).to_int())

func _parse_cell(coords: Vector3i, line: String) -> Cell:
	var cell := Cell.new()
	cell.coords = coords
	var chunks := line.split("|")
	if chunks.size() > 0:
		for d in 4:
			cell.borders[d] = chunks[0].get_slice(",", d).to_int()
	if chunks.size() > 1 and not chunks[1].is_empty():
		var color_slice := chunks[1].get_slice(",", 0)
		if not color_slice.is_empty():
			cell.color = Color(color_slice)
		for d in 4:
			color_slice = chunks[1].get_slice(",", d + 1)
			if not color_slice.is_empty():
				cell.border_colors[d] = Color(color_slice)
	if chunks.size() > 2 and not chunks[2].is_empty():
		cell.symbol = chunks[2].to_int()
	if chunks.size() > 3:
		cell.scene_uid = chunks[3].strip_edges()
		# MetSys compat: ":abc" is a shortened uid.
		if cell.scene_uid.begins_with(":"):
			cell.scene_uid = "uid://" + cell.scene_uid.trim_prefix(":")
	return cell

func _build_rooms() -> void:
	var seen_scenes: Dictionary = {}
	var visited: Dictionary = {}
	var sorted_coords: Array = cells.keys()
	sorted_coords.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.z != b.z:
			return a.z < b.z
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	for start in sorted_coords:
		if visited.has(start):
			continue
		var region := _flood_room(start, visited)
		var room := Room.new()
		room.layer = start.z
		for c in region:
			if room.scene_uid.is_empty() and not cells[c].scene_uid.is_empty():
				room.scene_uid = cells[c].scene_uid
		if room.scene_uid.is_empty():
			room.id = "unassigned:%d,%d,%d" % [start.x, start.y, start.z]
		elif seen_scenes.has(room.scene_uid):
			seen_scenes[room.scene_uid] += 1
			room.id = "%s#%d" % [room.scene_uid, seen_scenes[room.scene_uid]]
			if not room.scene_uid in split_scenes:
				split_scenes.append(room.scene_uid)
		else:
			seen_scenes[room.scene_uid] = 1
			room.id = room.scene_uid
		room.scene_path = resolve_scene_path(room.scene_uid)
		for c in region:
			room.cells.append(c)
			room._cell_set[Vector2i(c.x, c.y)] = true
			room.min_cell = Vector2i(mini(room.min_cell.x, c.x), mini(room.min_cell.y, c.y))
			room.max_cell = Vector2i(maxi(room.max_cell.x, c.x), maxi(room.max_cell.y, c.y))
			cells[c].room = room
		rooms[room.id] = room
		if not room.layer in layers:
			layers.append(room.layer)
	layers.sort()

func _flood_room(start: Vector3i, visited: Dictionary) -> Array[Vector3i]:
	var region: Array[Vector3i] = []
	var stack: Array[Vector3i] = [start]
	visited[start] = true
	while not stack.is_empty():
		var c: Vector3i = stack.pop_back()
		region.append(c)
		for d in 4:
			if cells[c].borders[d] != BORDER_NONE:
				continue
			var n := c + Vector3i(FWD[d].x, FWD[d].y, 0)
			if cells.has(n) and not visited.has(n):
				visited[n] = true
				stack.append(n)
	return region

func _build_doors() -> void:
	for coords in cells:
		var cell: Cell = cells[coords]
		for d in 4:
			var n: Vector3i = coords + Vector3i(FWD[d].x, FWD[d].y, 0)
			var neighbor: Cell = cells.get(n)
			if neighbor and neighbor.room == cell.room:
				continue
			var mine := cell.borders[d]
			var theirs := neighbor.borders[(d + 2) % 4] if neighbor else -2
			if mine <= 0 and theirs <= 0:
				continue
			var key := door_key(coords, d)
			if doors.has(key):
				continue
			var door := Door.new()
			door.key = key
			# Store from the left/top cell so the canonical key and a_* agree.
			if d == R or d == D or not neighbor:
				door.a_room = cell.room
				door.a_cell = coords
				door.a_dir = d
				door.a_border = mine
				door.b_room = neighbor.room if neighbor else null
				door.b_cell = n
				door.b_border = theirs
			else:
				door.a_room = neighbor.room
				door.a_cell = n
				door.a_dir = (d + 2) % 4
				door.a_border = theirs
				door.b_room = cell.room
				door.b_cell = coords
				door.b_border = mine
			doors[key] = door
			door.a_room.doors.append(door)
			if door.b_room:
				door.b_room.doors.append(door)

## Canonical key of the edge on side [param dir] of [param coords].
static func door_key(coords: Vector3i, dir: int) -> String:
	match dir:
		L:
			coords.x -= 1
			dir = R
		U:
			coords.y -= 1
			dir = D
	return "%d,%d,%d:%s" % [coords.x, coords.y, coords.z, DIR_SHORT[dir]]

static func resolve_scene_path(uid_or_path: String) -> String:
	if uid_or_path.is_empty():
		return ""
	if uid_or_path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(uid_or_path)
		if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
		return ""
	return uid_or_path if ResourceLoader.exists(uid_or_path) else ""

func get_cell(coords: Vector3i) -> Cell:
	return cells.get(coords)

func get_room_at(coords: Vector3i) -> Room:
	var cell: Cell = cells.get(coords)
	return cell.room if cell else null

func get_room(id: String) -> Room:
	return rooms.get(id)

func find_room_by_scene_path(path: String) -> Room:
	for room in rooms.values():
		if room.scene_path == path:
			return room
	return null

func get_rooms_on_layer(layer: int) -> Array[Room]:
	var ret: Array[Room] = []
	for room in rooms.values():
		if room.layer == layer:
			ret.append(room)
	return ret

## Bounding rectangle of all cells on a layer, in cell units.
func get_layer_bounds(layer: int) -> Rect2i:
	var min_p := Vector2i.MAX
	var max_p := Vector2i.MIN
	for c in cells:
		if c.z != layer:
			continue
		min_p = Vector2i(mini(min_p.x, c.x), mini(min_p.y, c.y))
		max_p = Vector2i(maxi(max_p.x, c.x), maxi(max_p.y, c.y))
	if min_p == Vector2i.MAX:
		return Rect2i()
	return Rect2i(min_p, max_p - min_p + Vector2i.ONE)

func get_layer_name(layer: int) -> String:
	if layer >= 0 and layer < layer_names.size() and not layer_names[layer].is_empty():
		return layer_names[layer]
	return "Layer %d" % layer

func get_group_name(group_id: int) -> String:
	if group_id >= 0 and group_id < group_names.size() and not group_names[group_id].is_empty():
		return group_names[group_id]
	return "Group %d" % group_id

func get_cell_groups(coords: Vector3i) -> PackedInt32Array:
	return _group_cache.get(coords, PackedInt32Array())

## Named MetSys cell groups touching this room.
func get_room_group_names(room: Room) -> PackedStringArray:
	var ret: PackedStringArray = []
	for c in room.cells:
		for g in get_cell_groups(c):
			var n := get_group_name(g)
			if not n in ret:
				ret.append(n)
	return ret

func get_custom_element_names() -> PackedStringArray:
	var ret: PackedStringArray = []
	for e in custom_elements:
		if not e.name in ret:
			ret.append(e.name)
	return ret
