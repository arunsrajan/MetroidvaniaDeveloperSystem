@tool
class_name MDSMcpSchema
extends RefCounted
## The small part of JSON Schema the MCP tools use: builders for their input schemas, a check of
## arguments against them, and the conversion of values to and from what JSON can hold.
##
## Godot's JSON parser makes every number a float, so a request's [code]id[/code] of 1 would go
## back as 1.0: [method clean] turns whole floats back into ints, both ways.

const MAX_SAFE_INT := 9007199254740992.0

static func text(description := "") -> Dictionary:
	return _described({"type": "string"}, description)

static func integer(description := "", minimum: Variant = null, maximum: Variant = null) -> Dictionary:
	return _ranged({"type": "integer"}, description, minimum, maximum)

static func number(description := "", minimum: Variant = null, maximum: Variant = null) -> Dictionary:
	return _ranged({"type": "number"}, description, minimum, maximum)

static func boolean(description := "") -> Dictionary:
	return _described({"type": "boolean"}, description)

static func choice(values: Array, description := "") -> Dictionary:
	return _described({"type": "string", "enum": values}, description)

static func array(items: Dictionary, description := "", max_items := 0) -> Dictionary:
	var out := _described({"type": "array", "items": items}, description)
	if max_items > 0:
		out.maxItems = max_items
	return out

## An object with these properties and no others.
static func object(properties: Dictionary, required: Array = [], description := "") -> Dictionary:
	var out := _described({"type": "object", "properties": properties, "additionalProperties": false}, description)
	if not required.is_empty():
		out.required = required
	return out

## An object with any properties.
static func any_object(description := "") -> Dictionary:
	return _described({"type": "object"}, description)

static func point(description := "") -> Dictionary:
	return object({"x": number(), "y": number()}, ["x", "y"], description)

static func rect(description := "") -> Dictionary:
	return object({"x": number(), "y": number(), "w": number("Width", 1), "h": number("Height", 1)}, ["x", "y", "w", "h"], description)

static func cell_box(description := "") -> Dictionary:
	return object({"x": integer(), "y": integer(), "w": integer("Width", 1), "h": integer("Height", 1)}, ["x", "y", "w", "h"], description)

static func cells(description := "Cells as [x, y] pairs", max_items := 50000) -> Dictionary:
	return array(array(integer(), "", 2), description, max_items)

static func _described(schema: Dictionary, description: String) -> Dictionary:
	if not description.is_empty():
		schema.description = description
	return schema

static func _ranged(schema: Dictionary, description: String, minimum: Variant, maximum: Variant) -> Dictionary:
	if minimum != null:
		schema.minimum = minimum
	if maximum != null:
		schema.maximum = maximum
	return _described(schema, description)

## Why [param value] doesn't fit [param schema], or "" when it does. Run it on [method clean]ed
## values.
static func check(value: Variant, schema: Dictionary, at := "arguments") -> String:
	match str(schema.get("type", "")):
		"string":
			if not value is String:
				return "%s must be a string" % at
		"integer":
			if not value is int:
				return "%s must be a whole number" % at
		"number":
			if not (value is int or value is float):
				return "%s must be a number" % at
		"boolean":
			if not value is bool:
				return "%s must be true or false" % at
		"array":
			if not value is Array:
				return "%s must be an array" % at
			if schema.has("maxItems") and value.size() > int(schema.maxItems):
				return "%s has more than %d items" % [at, int(schema.maxItems)]
			if schema.has("items"):
				for i in value.size():
					var bad := check(value[i], schema.items, "%s[%d]" % [at, i])
					if not bad.is_empty():
						return bad
		"object":
			if not value is Dictionary:
				return "%s must be an object" % at
			for key in schema.get("required", []):
				if not value.has(key):
					return "%s.%s is missing" % [at, key]
			var properties: Dictionary = schema.get("properties", {})
			for key in value:
				if properties.has(key):
					var bad := check(value[key], properties[key], "%s.%s" % [at, key])
					if not bad.is_empty():
						return bad
				elif schema.get("additionalProperties", true) == false:
					return "%s.%s is not a known field (known: %s)" % [at, key, ", ".join(PackedStringArray(properties.keys()))]
	if schema.has("enum") and not value in schema.enum:
		return "%s must be one of: %s" % [at, ", ".join(PackedStringArray(schema.enum))]
	if value is int or value is float:
		if schema.has("minimum") and value < schema.minimum:
			return "%s must be at least %s" % [at, schema.minimum]
		if schema.has("maximum") and value > schema.maximum:
			return "%s must be at most %s" % [at, schema.maximum]
	return ""

## [param value] as what JSON can hold: whole floats are ints, vectors [x, y], rectangles
## [x, y, w, h], colors "#rrggbbaa"; infinities and NaN are null.
static func clean(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return null
			if absf(value) < MAX_SAFE_INT and value == floorf(value):
				return int(value)
			return value
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[str(key) if not key is String else key] = clean(value[key])
			return out
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var out := []
			for v in value:
				out.append(clean(v))
			return out
		TYPE_VECTOR2:
			return [clean(value.x), clean(value.y)]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3I:
			return null if value == Vector3i.MAX else [value.x, value.y, value.z]
		TYPE_RECT2:
			return [clean(value.position.x), clean(value.position.y), clean(value.size.x), clean(value.size.y)]
		TYPE_RECT2I:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			return "#" + (value as Color).to_html()
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			return null if value == null else str(value)
	return value

## [param value] as one line of JSON.
static func to_json(value: Variant) -> String:
	return JSON.stringify(clean(value))

## The color [param value] names, or [param default] when it isn't one.
static func color(value: Variant, default := Color.TRANSPARENT) -> Color:
	var s := str(value)
	return Color(s) if Color.html_is_valid(s) else default
