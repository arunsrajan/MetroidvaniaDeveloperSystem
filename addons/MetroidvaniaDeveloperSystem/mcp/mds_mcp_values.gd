@tool
class_name MDSMcpValues
extends RefCounted
## The classes tools may make, and their properties' values to and from JSON, read from their
## exports: a class of the plugin or a project's own class extending one needs nothing here to be
## built through the tools.
##
## In JSON a vector is [x, y] or {x, y}, a rectangle [x, y, w, h] or {x, y, w, h}, a color
## "#rrggbbaa", an enum its name or number. A resource is a path ("res://....tres") or
## {"class": "MDSMoveDash", "set": {...}}, which makes one inside what holds it. A node in a scene
## is its path from the scene's root. No value can be or hold a script.

## Godot's own classes that a room's objects are commonly made of.
const NATIVE_NODES: PackedStringArray = [
	"Node", "Node2D", "Marker2D", "Sprite2D", "AnimatedSprite2D", "Polygon2D", "Line2D", "CollisionShape2D", "CollisionPolygon2D",
	"Area2D", "StaticBody2D", "AnimatableBody2D", "CharacterBody2D", "RayCast2D", "PointLight2D", "DirectionalLight2D", "LightOccluder2D",
	"AudioStreamPlayer", "AudioStreamPlayer2D", "AnimationPlayer", "Timer", "Camera2D", "CanvasLayer", "Label", "ColorRect", "TextureRect", "Control",
	"GPUParticles2D", "CPUParticles2D", "Path2D", "PathFollow2D", "TileMapLayer", "NavigationRegion2D",
]
const NATIVE_RESOURCES: PackedStringArray = [
	"RectangleShape2D", "CircleShape2D", "CapsuleShape2D", "SegmentShape2D", "ConvexPolygonShape2D", "ConcavePolygonShape2D", "WorldBoundaryShape2D",
	"Gradient", "GradientTexture1D", "GradientTexture2D", "Curve", "CurveTexture", "ParticleProcessMaterial", "CanvasItemMaterial", "AtlasTexture", "SpriteFrames", "LabelSettings",
]
## The plugin's own tools, not things a game holds.
const TOOL_FOLDERS: PackedStringArray = [
	"res://addons/MetroidvaniaDeveloperSystem/mcp/", "res://addons/MetroidvaniaDeveloperSystem/ui/",
	"res://addons/MetroidvaniaDeveloperSystem/gameplay/editor/", "res://tests/",
]
const TOOL_FILES: PackedStringArray = ["plugin.gd", "dock.gd", "world_panel.gd", "metsys_panel.gd", "play_here.gd", "scene_scanner.gd"]
## Properties that are never set. Scripts above all: tools don't run code.
const NEVER_SET: PackedStringArray = ["script", "owner", "scene_file_path", "multiplayer", "unique_name_in_owner", "resource_path", "resource_local_to_scene", "resource_scene_unique_id"]
## A packed array longer than this is reported by its size.
const LONGEST_PACKED := 2000

## Why the last call that returned null or false failed.
var error := ""
## What node paths are read from.
var scene_root: Node

# --- Classes ---------------------------------------------------------------------------------

## The classes tools may make: name -> {path, base, kind (node, resource)}.
static func classes() -> Dictionary:
	var all := {}
	for c: Dictionary in ProjectSettings.get_global_class_list():
		all[String(c["class"])] = c
	var out := {}
	for name: String in all:
		var c: Dictionary = all[name]
		var path := String(c["path"])
		if _is_tool_file(path) or not _extends_mds(name, all):
			continue
		var native := name
		while all.has(native):
			native = String(all[native]["base"])
		var kind := "node" if ClassDB.is_parent_class(native, "Node") else ("resource" if ClassDB.is_parent_class(native, "Resource") else "")
		if not kind.is_empty():
			out[name] = {"path": path, "base": String(c["base"]), "kind": kind}
	return out

static func _is_tool_file(path: String) -> bool:
	for folder in TOOL_FOLDERS:
		if path.begins_with(folder):
			return true
	return path.get_base_dir() == "res://addons/MetroidvaniaDeveloperSystem" and path.get_file() in TOOL_FILES

static func _extends_mds(name: String, all: Dictionary) -> bool:
	var at := name
	while all.has(at):
		if at.begins_with("MDS"):
			return true
		at = String(all[at]["base"])
	return false

## Whether [param class_id] may be made, and it is a [param kind] ("" for either).
static func can_make(class_id: String, kind := "") -> bool:
	if class_id in NATIVE_NODES:
		return kind != "resource"
	if class_id in NATIVE_RESOURCES:
		return kind != "node"
	var c: Dictionary = classes().get(class_id, {})
	return not c.is_empty() and (kind.is_empty() or c["kind"] == kind)

## A new [param class_id], or null. Outside the editor's scripting (a class without @tool, in the
## editor) it holds its exports in a placeholder, as a node added in the Scene dock does.
static func make(class_id: String) -> Object:
	if class_id in NATIVE_NODES or class_id in NATIVE_RESOURCES:
		return ClassDB.instantiate(class_id)
	var c: Dictionary = classes().get(class_id, {})
	if c.is_empty():
		return null
	var script := load(c["path"]) as Script
	if not script:
		return null
	if script.can_instantiate():
		return script.new()
	var made: Object = ClassDB.instantiate(script.get_instance_base_type())
	made.set_script(script)
	return made

## The name [param obj]'s class goes by: its script's, or the first of its bases with one, or Godot's.
static func class_of(obj: Object) -> String:
	var script := obj.get_script() as Script
	while script:
		if not String(script.get_global_name()).is_empty():
			return String(script.get_global_name())
		script = script.get_base_script()
	return obj.get_class()

## Whether [param obj] is one of [param types] (comma-separated class names).
static func is_a(obj: Object, types: String) -> bool:
	if types.is_empty():
		return true
	for type in types.split(","):
		if obj.is_class(type):
			return true
		var script := obj.get_script() as Script
		while script:
			if String(script.get_global_name()) == type:
				return true
			script = script.get_base_script()
	return false

## The properties of [param obj] that can be set. [param native]: Godot's own as well as its exports.
static func properties(obj: Object, native := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var group := ""
	var own := {}
	var script := obj.get_script() as Script
	if script:
		for p: Dictionary in script.get_script_property_list():
			own[String(p["name"])] = true
	for p: Dictionary in obj.get_property_list():
		var usage := int(p["usage"])
		if usage & PROPERTY_USAGE_CATEGORY:
			continue
		if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			group = String(p["name"])
			continue
		if not usage & PROPERTY_USAGE_EDITOR or String(p["name"]) in NEVER_SET or String(p["name"]).contains("/"):
			continue
		var mine := own.has(String(p["name"]))
		if not native and not mine:
			continue
		var entry := p.duplicate()
		entry["script"] = mine
		entry["group"] = group if mine else ""
		out.append(entry)
	return out

## What tools show of a property's type.
static func type_of(info: Dictionary) -> String:
	var type := int(info["type"])
	if type == TYPE_NIL:
		return "any"
	if type == TYPE_OBJECT:
		return String(info["hint_string"]) if not String(info["hint_string"]).is_empty() else "Object"
	if type == TYPE_ARRAY:
		var each := element_info(info)
		return "Array[%s]" % type_of(each) if int(each["type"]) != TYPE_NIL else "Array"
	return type_string(type)

## What a class is made of: {class, base, kind, properties: [{name, type, default, group, enum, min, max, node}]}.
static func describe(class_id: String, native := false) -> Dictionary:
	var made := make(class_id)
	if not made:
		return {}
	var c: Dictionary = classes().get(class_id, {})
	var defaults := MDSMcpValues.new()
	if made is Node:
		defaults.scene_root = made
	var props := []
	for p in properties(made, native or c.is_empty()):
		var entry := {"name": p["name"], "type": type_of(p)}
		if not String(p["group"]).is_empty():
			entry["group"] = p["group"]
		var names := enum_names(p)
		if not names.is_empty():
			entry["enum"] = names
		if int(p["hint"]) == PROPERTY_HINT_RANGE:
			var range_of := String(p["hint_string"]).split(",")
			if range_of.size() >= 2:
				entry["min"] = range_of[0].to_float()
				entry["max"] = range_of[1].to_float()
		if int(p["hint"]) == PROPERTY_HINT_NODE_TYPE:
			entry["node"] = true
		entry["default"] = defaults.encode(made.get(p["name"]))
		props.append(entry)
	var out := {"class": class_id, "base": c["base"] if c.has("base") else ClassDB.get_parent_class(class_id), "kind": c.get("kind", "node" if class_id in NATIVE_NODES else "resource"), "properties": props}
	if made is Node:
		(made as Node).free()
	return out

## The names of an enum property (or a string chosen from a list). Empty for other properties.
static func enum_names(info: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if int(info["hint"]) != PROPERTY_HINT_ENUM:
		return out
	for item in String(info["hint_string"]).split(",", false):
		out.append(item.get_slice(":", 0))
	return out

static func _plain(text: String) -> String:
	return text.to_lower().replace(" ", "").replace("_", "")

# --- From JSON -------------------------------------------------------------------------------

## What the elements of an Array property are, as a property of its own.
static func element_info(info: Dictionary) -> Dictionary:
	var hint := int(info["hint"])
	var text := String(info["hint_string"])
	if text.is_empty():
		return {"type": TYPE_NIL, "hint": 0, "hint_string": ""}
	if hint == PROPERTY_HINT_ARRAY_TYPE:
		for t in TYPE_MAX:
			if type_string(t) == text:
				return {"type": t, "hint": 0, "hint_string": ""}
		return {"type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": text}
	if hint == PROPERTY_HINT_TYPE_STRING:
		var colon := text.find(":")
		var head := text.substr(0, colon) if colon >= 0 else text
		var rest := text.substr(colon + 1) if colon >= 0 else ""
		var t := head.get_slice("/", 0).to_int()
		var h := head.get_slice("/", 1).to_int() if head.contains("/") else (PROPERTY_HINT_TYPE_STRING if t == TYPE_ARRAY and not rest.is_empty() else 0)
		return {"type": t, "hint": h, "hint_string": rest}
	return {"type": TYPE_NIL, "hint": 0, "hint_string": ""}

func _fail(text: String) -> Variant:
	if error.is_empty():
		error = text
	return null

## [param value] as property [param info] holds it; null with [member error] if it can't be. Check
## [member error]: null is also a good value for an object. [param current]: what it holds now,
## which gives a new array its type.
func decode(value: Variant, info: Dictionary, current: Variant = null) -> Variant:
	var type := int(info["type"])
	var at := String(info.get("name", "value"))
	match type:
		TYPE_NIL:
			return value
		TYPE_BOOL:
			return value if value is bool else _fail("%s must be true or false." % at)
		TYPE_INT:
			if value is String:
				for item in String(info["hint_string"]).split(",", false):
					if _plain(item.get_slice(":", 0)) == _plain(value):
						return item.get_slice(":", 1).to_int() if item.contains(":") else Array(String(info["hint_string"]).split(",", false)).find(item)
				return _fail("%s: %s is not one of %s." % [at, value, ", ".join(enum_names(info))])
			return int(value) if value is int or value is float else _fail("%s must be a whole number." % at)
		TYPE_FLOAT:
			return float(value) if value is int or value is float else _fail("%s must be a number." % at)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			if not value is String:
				return _fail("%s must be text." % at)
			return _decode_text(value, info, type)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var n: Array = _numbers(value, ["x", "y"])
			if n.is_empty():
				return _fail("%s must be [x, y]." % at)
			return Vector2(n[0], n[1]) if type == TYPE_VECTOR2 else Vector2i(int(n[0]), int(n[1]))
		TYPE_VECTOR3, TYPE_VECTOR3I:
			var n: Array = _numbers(value, ["x", "y", "z"])
			if n.is_empty():
				return _fail("%s must be [x, y, z]." % at)
			return Vector3(n[0], n[1], n[2]) if type == TYPE_VECTOR3 else Vector3i(int(n[0]), int(n[1]), int(n[2]))
		TYPE_RECT2, TYPE_RECT2I:
			var n: Array = _numbers(value, ["x", "y", "w", "h"])
			if n.is_empty():
				return _fail("%s must be [x, y, w, h]." % at)
			return Rect2(n[0], n[1], n[2], n[3]) if type == TYPE_RECT2 else Rect2i(int(n[0]), int(n[1]), int(n[2]), int(n[3]))
		TYPE_TRANSFORM2D:
			var n: Array = _numbers(value, ["ax", "ay", "bx", "by", "ox", "oy"])
			if n.is_empty():
				return _fail("%s must be [ax, ay, bx, by, ox, oy]." % at)
			return Transform2D(Vector2(n[0], n[1]), Vector2(n[2], n[3]), Vector2(n[4], n[5]))
		TYPE_COLOR:
			return _decode_color(value, at)
		TYPE_DICTIONARY:
			if not value is Dictionary:
				return _fail("%s must be an object." % at)
			if current is Dictionary:
				var out: Dictionary = (current as Dictionary).duplicate()
				out.clear()
				for key in value:
					out[_dictionary_key(key, out)] = value[key]
				return out
			return value
		TYPE_ARRAY:
			if not value is Array:
				return _fail("%s must be an array." % at)
			return _decode_array(value, info, current)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if not value is Array:
				return _fail("%s must be an array." % at)
			return _decode_packed(value, type, at)
		TYPE_OBJECT:
			return _decode_object(value, info)
	return _fail("%s is a %s, which tools can't set." % [at, type_string(type)])

func _decode_text(value: String, info: Dictionary, type: int) -> Variant:
	var at := String(info.get("name", "value"))
	var hint := int(info["hint"])
	if hint == PROPERTY_HINT_ENUM and not value.is_empty() and not value in enum_names(info):
		return _fail("%s: %s is not one of %s." % [at, value, ", ".join(enum_names(info))])
	if hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_DIR, PROPERTY_HINT_GLOBAL_FILE, PROPERTY_HINT_GLOBAL_DIR, PROPERTY_HINT_SAVE_FILE, PROPERTY_HINT_GLOBAL_SAVE_FILE]:
		if not value.is_empty() and not value.begins_with("user://") and not value.begins_with("uid://") and MDSMcpGuard.normalize(value).is_empty():
			return _fail("%s: %s is not a path inside the project." % [at, value])
	if type == TYPE_STRING_NAME:
		return StringName(value)
	return NodePath(value) if type == TYPE_NODE_PATH else value

## The numbers of [param value], an array or an object with [param keys]. Empty when it isn't.
static func _numbers(value: Variant, keys: Array) -> Array:
	var out := []
	if value is Array:
		if value.size() != keys.size():
			return []
		out = value
	elif value is Dictionary:
		for key in keys:
			if not value.has(key):
				return []
			out.append(value[key])
	else:
		return []
	for n in out:
		if not (n is int or n is float):
			return []
	return out.map(func(n: Variant) -> float: return float(n))

func _decode_color(value: Variant, at: String) -> Variant:
	if value is String and Color.html_is_valid(value):
		return Color(value)
	if value is Array and value.size() in [3, 4]:
		var n: Array = _numbers(value, ["r", "g", "b", "a"].slice(0, value.size()))
		if not n.is_empty():
			return Color(n[0], n[1], n[2], n[3] if n.size() > 3 else 1.0)
	return _fail("%s must be a color: #rrggbb or #rrggbbaa." % at)

## JSON keys are text: a dictionary with keys of another type has them turned back, by what the
## property's type says. Only the type's own keys can go in.
static func _dictionary_key(key: Variant, like: Dictionary) -> Variant:
	if like.is_typed_key() and like.get_typed_key_builtin() == TYPE_INT:
		return str(key).to_int()
	if like.is_typed_key() and like.get_typed_key_builtin() == TYPE_STRING_NAME:
		return StringName(str(key))
	return key

func _decode_array(value: Array, info: Dictionary, current: Variant) -> Variant:
	var each := element_info(info)
	each["name"] = "%s[]" % info.get("name", "value")
	var out: Array = (current as Array).duplicate() if current is Array else []
	out.clear()
	for v in value:
		var item: Variant = decode(v, each)
		if not error.is_empty():
			return null
		out.append(item)
	if out.size() != value.size():
		return _fail("%s: one of these isn't what it holds (%s)." % [info.get("name", "value"), type_of(each)])
	return out

func _decode_packed(value: Array, type: int, at: String) -> Variant:
	var each := {"name": "%s[]" % at, "hint": 0, "hint_string": ""}
	match type:
		TYPE_PACKED_STRING_ARRAY:
			each["type"] = TYPE_STRING
		TYPE_PACKED_VECTOR2_ARRAY:
			each["type"] = TYPE_VECTOR2
		TYPE_PACKED_VECTOR3_ARRAY:
			each["type"] = TYPE_VECTOR3
		TYPE_PACKED_COLOR_ARRAY:
			each["type"] = TYPE_COLOR
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			each["type"] = TYPE_FLOAT
		_:
			each["type"] = TYPE_INT
	var list := []
	for v in value:
		var item: Variant = decode(v, each)
		if not error.is_empty():
			return null
		list.append(item)
	match type:
		TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray(list)
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(list)
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array(list)
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array(list)
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array(list)
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(list)
		TYPE_PACKED_VECTOR2_ARRAY:
			return PackedVector2Array(list)
		TYPE_PACKED_VECTOR3_ARRAY:
			return PackedVector3Array(list)
	return PackedColorArray(list)

func _decode_object(value: Variant, info: Dictionary) -> Variant:
	var at := String(info.get("name", "value"))
	if value == null:
		return null
	var types := String(info["hint_string"])
	if int(info["hint"]) == PROPERTY_HINT_NODE_TYPE:
		return _decode_node(value, types, at)
	if value is Dictionary and value.has("class"):
		return _decode_inline(value, types, at)
	var path: String = value.get("path", "") if value is Dictionary else (value if value is String else "")
	if path.is_empty():
		return _fail("%s must be a res:// path, or {class, set}." % at)
	var inside := MDSMcpGuard.normalize(path)
	if inside.is_empty() or not ResourceLoader.exists(inside):
		return _fail("%s: %s isn't a resource in the project." % [at, path])
	var res := load(inside)
	if not res or res is Script:
		return _fail("%s: %s can't be used here." % [at, path])
	if not is_a(res, types):
		return _fail("%s: %s is a %s, and this holds %s." % [at, path, class_of(res), types])
	return res

func _decode_node(value: Variant, types: String, at: String) -> Variant:
	if not scene_root:
		return _fail("%s is a node: it can only be set in a scene." % at)
	if not value is String:
		return _fail("%s must be a node's path in the scene." % at)
	var node := scene_root.get_node_or_null(NodePath(value))
	if not node:
		return _fail("%s: the scene has no node %s." % [at, value])
	if not is_a(node, types):
		return _fail("%s: %s is a %s, and this holds %s." % [at, value, class_of(node), types])
	return node

func _decode_inline(value: Dictionary, types: String, at: String) -> Variant:
	var class_id := str(value["class"])
	if not can_make(class_id, "resource"):
		return _fail("%s: %s is not a resource tools can make." % [at, class_id])
	var res := make(class_id)
	if not res or not is_a(res, types):
		return _fail("%s: a %s can't go in %s." % [at, class_id, types])
	if value.has("set"):
		if not value["set"] is Dictionary:
			return _fail("%s: set must be an object." % at)
		if not set_all(res, value["set"]):
			return null
	return res

## Sets properties of [param obj] from JSON. Returns whether it could; nothing is set if any can't
## be read, since each is checked before the first is set.
func set_all(obj: Object, values: Dictionary) -> bool:
	var infos := {}
	for p in properties(obj):
		infos[String(p["name"])] = p
	var decoded := {}
	for key: String in values:
		if key in NEVER_SET:
			error = "%s can't be set." % key
			return false
		if not infos.has(key):
			var names := PackedStringArray()
			for p in properties(obj, false):
				names.append(String(p["name"]))
			error = "%s has no property %s. It has: %s." % [class_of(obj), key, ", ".join(names)]
			return false
		decoded[key] = decode(values[key], infos[key], obj.get(key))
		if not error.is_empty():
			return false
	for key: String in decoded:
		obj.set(key, decoded[key])
	return true

# --- To JSON ---------------------------------------------------------------------------------

## [param value] as JSON holds it, and as [method decode] reads it back.
func encode(value: Variant, seen: Dictionary = {}) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			return _encode_object(value, seen)
		TYPE_ARRAY:
			var out := []
			for v in value:
				out.append(encode(v, seen))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[str(key)] = encode(value[key], seen)
			return out
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if value.size() > LONGEST_PACKED:
				return {"size": value.size()}
			var out := []
			for v in value:
				out.append(MDSMcpSchema.clean(v))
			return out
		TYPE_TRANSFORM2D:
			var t: Transform2D = value
			return MDSMcpSchema.clean([t.x.x, t.x.y, t.y.x, t.y.y, t.origin.x, t.origin.y])
		TYPE_VECTOR3:
			return MDSMcpSchema.clean([value.x, value.y, value.z])
	return MDSMcpSchema.clean(value)

func _encode_object(value: Object, seen: Dictionary) -> Variant:
	if not is_instance_valid(value):
		return null
	if value is Node:
		if scene_root and (value == scene_root or scene_root.is_ancestor_of(value)):
			return str(scene_root.get_path_to(value))
		return null
	if not value is Resource:
		return null
	var res := value as Resource
	if not res.resource_path.is_empty() and not res.resource_path.contains("::"):
		return res.resource_path
	if seen.has(res):
		return {"class": class_of(res), "repeated": true}
	seen[res] = true
	var out := {"class": class_of(res)}
	var values := changed_values(res, seen)
	if not values.is_empty():
		out["set"] = values
	return out

## The properties of [param obj] that differ from its class's defaults, as JSON.
func changed_values(obj: Object, seen: Dictionary = {}) -> Dictionary:
	var out := {}
	var script := obj.get_script() as Script
	for p in properties(obj):
		var name := String(p["name"])
		var now: Variant = obj.get(name)
		var was: Variant = script.get_property_default_value(name) if script and p["script"] else ClassDB.class_get_property_default_value(obj.get_class(), name)
		if typeof(now) == typeof(was) and now == was:
			continue
		if now == null and was == null:
			continue
		out[name] = encode(now, seen)
	return out
