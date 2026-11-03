extends "res://tests/test_case.gd"
## Checking arguments against the MCP tools' schemas, and converting values for JSON.

const S := preload("res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_schema.gd")
const Case := preload("res://tests/mcp_test_case.gd")

func _run() -> void:
	var schema := S.object({"a": S.integer("", 1, 5), "b": S.text(), "c": S.choice(["x", "y"]), "d": S.array(S.integer(), "", 2), "e": S.boolean(), "f": S.number()}, ["a"])
	check(S.check({"a": 1}, schema).is_empty(), "required only")
	check(not S.check({}, schema).is_empty(), "required missing")
	check(not S.check({"a": 1, "zz": 1}, schema).is_empty(), "unknown field")
	check(not S.check({"a": 1.5}, schema).is_empty(), "a float isn't a whole number")
	check(not S.check({"a": 9}, schema).is_empty(), "above the maximum")
	check(not S.check({"a": 0}, schema).is_empty(), "below the minimum")
	check(not S.check({"a": 1, "b": 2}, schema).is_empty(), "a number isn't a string")
	check(not S.check({"a": 1, "c": "z"}, schema).is_empty(), "not one of the choices")
	check(not S.check({"a": 1, "d": [1, 2, 3]}, schema).is_empty(), "too many items")
	check(not S.check({"a": 1, "d": [1, "x"]}, schema).is_empty(), "wrong item")
	check(not S.check({"a": 1, "e": 1}, schema).is_empty(), "a number isn't a bool")
	check(S.check({"a": 1, "f": 1}, schema).is_empty() and S.check({"a": 1, "f": 1.5}, schema).is_empty(), "number takes both")
	check(S.check({"a": 1}, schema, "args").is_empty(), "custom label")
	check(S.check({"a": "x"}, schema).contains("arguments.a"), "the message says which")

	check(typeof(S.clean(1.0)) == TYPE_INT, "whole floats become ints")
	check(typeof(S.clean(1.5)) == TYPE_FLOAT, "others stay")
	check(S.clean({"a": [1.0, 2.0]}).a[1] is int, "inside containers too")
	check(S.clean(Vector2(1, 2.5)) == [1, 2.5], "vectors become pairs")
	check(S.clean(Rect2(1, 2, 3, 4)) == [1, 2, 3, 4], "rectangles become lists")
	check(S.clean(Color.RED) == "#ff0000ff", "colors become strings")
	check(S.clean(INF) == null, "infinities become null")
	check(S.clean(PackedStringArray(["a"])) == ["a"], "packed arrays become arrays")
	check(S.to_json({"a": 1.0}) == '{"a":1}', "to_json keeps ints")
	check(S.color("#ff0000") == Color.RED and S.color("nope", Color.BLUE) == Color.BLUE, "colors from strings")

	# Every tool's schema, and its required fields in it.
	var p := MDSMcpProtocol.new(MDSMcpHost.new(), MDSMcpGuard.Tier.READ, TMP + "/mcp_schema_data")
	for t: Dictionary in p.list_tools():
		var bad: PackedStringArray = _schema_problems(t.inputSchema, t.name)
		check(bad.is_empty(), "%s: %s" % [t.name, ", ".join(bad)])
		check(t.name.begins_with("mds_"), "%s has the prefix" % t.name)
		check(JSON.stringify(t).length() < 6000, "%s stays small" % t.name)
	check(p.list_tools().size() >= 40 and p.list_tools().size() <= 50, "about 45 tools: %d" % p.list_tools().size())
	Case.clean_folder(TMP + "/mcp_schema_data")

static func _schema_problems(schema: Dictionary, at: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not str(schema.get("type", "")) in ["string", "integer", "number", "boolean", "array", "object"]:
		out.append("%s has no type" % at)
	for r in schema.get("required", []):
		if not schema.get("properties", {}).has(r):
			out.append("%s requires unknown %s" % [at, r])
	for key: String in schema.get("properties", {}):
		out.append_array(_schema_problems(schema.properties[key], at + "." + key))
	if schema.has("items"):
		out.append_array(_schema_problems(schema["items"], at + "[]"))
	return out
