@tool
class_name MDSMcpResources
extends RefCounted
## The MCP resources. Clients vary in how they use these, so everything here can also be had
## through a tool.

const GUIDE_FILE := "res://docs/mds_objects_guide.md"

## Weak: the protocol holds this.
var protocol_ref: WeakRef

func _init(p: MDSMcpProtocol) -> void:
	protocol_ref = weakref(p)

func list() -> Array:
	return [
		{"uri": "mds://worlds", "name": "worlds", "description": "The worlds in this project", "mimeType": "application/json"},
		{"uri": "mds://guide/objects", "name": "object guide", "description": "Which objects MDS has and how to use them", "mimeType": "text/markdown"},
		{"uri": "mds://audit", "name": "audit", "description": "Recent tool calls", "mimeType": "application/json"},
	]

func templates() -> Array:
	return [
		{"uriTemplate": "mds://world/{path}", "name": "world", "description": "A world's summary. path: url-encoded res:// path", "mimeType": "application/json"},
		{"uriTemplate": "mds://world/{path}/room/{id}", "name": "room", "description": "A room's data with its gates", "mimeType": "application/json"},
		{"uriTemplate": "mds://world/{path}/issues", "name": "issues", "description": "A world's validator output", "mimeType": "application/json"},
		{"uriTemplate": "mds://catalog/{kind}", "name": "catalog", "description": "Valid ids of a kind, as mds_catalog gives them", "mimeType": "application/json"},
	]

## The resource at [param uri], as resources/read answers: {contents: [...]}, or {_rpc_error}.
func read(uri: String) -> Dictionary:
	if uri == "mds://guide/objects":
		if not FileAccess.file_exists(GUIDE_FILE):
			return _text(uri, "The object guide is in docs/ of the MDS repository, which this install doesn't have.", "text/markdown")
		return _text(uri, FileAccess.get_file_as_string(GUIDE_FILE), "text/markdown")
	if uri == "mds://audit":
		return _json(uri, {"calls": protocol_ref.get_ref().ctx.guard.recent_audit()})
	if uri == "mds://worlds":
		return await _from_tool(uri, "mds_world_list", {})
	if uri.begins_with("mds://catalog/"):
		return await _from_tool(uri, "mds_catalog", {"kind": uri.trim_prefix("mds://catalog/")})
	if uri.begins_with("mds://world/"):
		var rest := uri.trim_prefix("mds://world/")
		var parts := rest.split("/")
		var world := parts[0].uri_decode()
		if parts.size() == 1:
			return await _from_tool(uri, "mds_world_get", {"world": world, "include": ["settings", "areas", "rooms"]})
		if parts.size() == 2 and parts[1] == "issues":
			return await _from_tool(uri, "mds_validate", {"world": world})
		if parts.size() == 3 and parts[1] == "room":
			var w: MDSWorld = protocol_ref.get_ref().ctx.read_world({"world": world})
			if not w:
				return {"_rpc_error": "Resource not found: %s" % uri}
			var id := parts[2].uri_decode()
			if not w.has_room(id):
				return {"_rpc_error": "Resource not found: %s" % uri}
			return _json(uri, MDSMcpToolsWorld.room_summary(w, id))
	return {"_rpc_error": "Resource not found: %s" % uri}

func _from_tool(uri: String, tool_name: String, args: Dictionary) -> Dictionary:
	var r: Dictionary = await protocol_ref.get_ref().call_tool(tool_name, args)
	if MDSMcpContext.is_failure(r):
		return {"_rpc_error": "Resource not found: %s (%s)" % [uri, r._error.message]}
	return _json(uri, r)

static func _json(uri: String, value: Variant) -> Dictionary:
	return _text(uri, MDSMcpSchema.to_json(value), "application/json")

static func _text(uri: String, text: String, mime: String) -> Dictionary:
	return {"contents": [{"uri": uri, "mimeType": mime, "text": text}]}
