@tool
class_name IDPAnnotations
extends RefCounted
## Designer annotations that MetSys' MapData.txt has no place for: room names and types,
## boss labels, build status, ability gates on doors, extra links (elevators, cross-layer
## transitions), map pins and notes.
##
## Stored as JSON next to the map file ("MapData.txt" -> "MapData.idp.json") so it can be
## versioned and diffed. Rooms are keyed by scene UID and doors by edge key, so moving
## scene files around does not lose data.

signal changed

const VERSION := 1

const ROOM_TYPES: PackedStringArray = [
	"", "normal", "corridor", "hub", "save", "boss", "mini_boss", "shop", "npc",
	"fast_travel", "secret", "treasure", "challenge", "transition",
]
const STATUSES: PackedStringArray = ["", "idea", "blockout", "art_pass", "polish", "done"]
const PIN_KINDS: PackedStringArray = ["note", "todo", "secret", "bug", "idea"]

var path := ""
var data: Dictionary = {}

func _init() -> void:
	clear()

func clear() -> void:
	data = {
		"version": VERSION,
		"start_room": "",
		"rooms": {},
		"doors": {},
		"links": [],
		"pins": [],
		"settings": {"save_distance_warn": 4},
	}

static func path_for_map(map_path: String) -> String:
	return map_path.get_basename() + ".idp.json"

static func load_for_map(map_path: String) -> IDPAnnotations:
	var ann := IDPAnnotations.new()
	ann.path = path_for_map(map_path)
	if FileAccess.file_exists(ann.path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ann.path))
		if parsed is Dictionary:
			for key in parsed:
				ann.data[key] = parsed[key]
		else:
			push_warning("InteractiveDevPanel: could not parse %s" % ann.path)
	return ann

func save() -> Error:
	if path.is_empty():
		return ERR_FILE_BAD_PATH
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", true))
	file.close()
	return OK

func _touch() -> void:
	changed.emit()

# --- Rooms -------------------------------------------------------------------

func get_room(id: String) -> Dictionary:
	return data.rooms.get(id, {})

func get_room_value(id: String, key: String, default: Variant = "") -> Variant:
	return get_room(id).get(key, default)

func set_room_value(id: String, key: String, value: Variant) -> void:
	var room: Dictionary = data.rooms.get(id, {})
	var empty: bool = value == null or (value is String and value.is_empty()) or (value is Array and value.is_empty())
	if empty:
		room.erase(key)
	else:
		room[key] = value
	if room.is_empty():
		data.rooms.erase(id)
	else:
		data.rooms[id] = room
	_touch()

func get_room_grants(id: String) -> PackedStringArray:
	return PackedStringArray(get_room_value(id, "grants", []))

# --- Doors -------------------------------------------------------------------

func get_door(key: String) -> Dictionary:
	return data.doors.get(key, {})

func get_door_requires(key: String) -> PackedStringArray:
	return PackedStringArray(get_door(key).get("requires", []))

func set_door_value(key: String, field: String, value: Variant) -> void:
	var door: Dictionary = data.doors.get(key, {})
	var empty: bool = value == null or (value is String and value.is_empty()) or (value is Array and value.is_empty())
	if empty:
		door.erase(field)
	else:
		door[field] = value
	if door.is_empty():
		data.doors.erase(key)
	else:
		data.doors[key] = door
	_touch()

## Room id the door can only be passed *from*, or "" when two-way.
func get_door_one_way_from(key: String) -> String:
	return get_door(key).get("one_way_from", "")

# --- Links (elevators, teleporters, cross-layer transitions) -------------------

func get_links() -> Array:
	return data.links

func add_link(a: String, b: String, note := "") -> void:
	for link in data.links:
		if (link.a == a and link.b == b) or (link.a == b and link.b == a):
			return
	data.links.append({"a": a, "b": b, "note": note, "requires": []})
	_touch()

func remove_link(index: int) -> void:
	if index >= 0 and index < data.links.size():
		data.links.remove_at(index)
		_touch()

func set_link_value(index: int, field: String, value: Variant) -> void:
	if index >= 0 and index < data.links.size():
		data.links[index][field] = value
		_touch()

# --- Pins --------------------------------------------------------------------

func get_pins() -> Array:
	return data.pins

## [param pos] is in cell units (fractional, so pins can sit anywhere inside a cell).
func add_pin(layer: int, pos: Vector2, text: String, kind := "note") -> void:
	data.pins.append({"layer": layer, "x": pos.x, "y": pos.y, "text": text, "kind": kind})
	_touch()

func remove_pin(index: int) -> void:
	if index >= 0 and index < data.pins.size():
		data.pins.remove_at(index)
		_touch()

# --- Misc --------------------------------------------------------------------

func get_start_room() -> String:
	return data.get("start_room", "")

func set_start_room(id: String) -> void:
	data.start_room = id
	_touch()

func get_setting(key: String, default: Variant) -> Variant:
	return data.get("settings", {}).get(key, default)

func set_setting(key: String, value: Variant) -> void:
	if not data.has("settings"):
		data.settings = {}
	data.settings[key] = value
	_touch()

## Every ability name mentioned anywhere (grants, door and link requirements).
func get_known_abilities() -> PackedStringArray:
	var ret: PackedStringArray = []
	for room in data.rooms.values():
		for a in room.get("grants", []):
			if not a in ret:
				ret.append(a)
	for door in data.doors.values():
		for a in door.get("requires", []):
			if not a in ret:
				ret.append(a)
	for link in data.links:
		for a in link.get("requires", []):
			if not a in ret:
				ret.append(a)
	ret.sort()
	return ret

## Splits "dash, double jump" into ["dash", "double_jump"].
static func parse_list(text: String) -> PackedStringArray:
	var ret: PackedStringArray = []
	for part in text.split(",", false):
		var s := part.strip_edges().to_lower().replace(" ", "_")
		if not s.is_empty() and not s in ret:
			ret.append(s)
	return ret
