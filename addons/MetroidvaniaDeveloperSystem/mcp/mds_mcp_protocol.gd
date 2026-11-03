@tool
class_name MDSMcpProtocol
extends RefCounted
## The MCP server, knowing nothing of transports: [method handle] takes a JSON-RPC message and
## returns the answer. It speaks both generations of MCP: a request with the protocol version in
## its _meta is served as 2026-07-28 (no handshake, no state); an [code]initialize[/code] and the
## requests without it get the earlier behaviour. Neither keeps anything between requests.

const SERVER_NAME := "metroidvania-developer-system"
const MODERN_VERSIONS: PackedStringArray = ["2026-07-28"]
const LEGACY_VERSIONS: PackedStringArray = ["2025-11-25", "2025-06-18", "2025-03-26"]
const META_VERSION := "io.modelcontextprotocol/protocolVersion"
const META_CLIENT := "io.modelcontextprotocol/clientInfo"
const META_SERVER := "io.modelcontextprotocol/serverInfo"

const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INTERNAL_ERROR := -32603
const HEADER_MISMATCH := -32020
const UNSUPPORTED_VERSION := -32022

## How long clients may keep the lists: tools never change while the server runs.
const LIST_TTL_MSEC := 3600000
const PAGE_SIZE_TOOLS := 200
const MAX_BATCH_OPS := 200

const INSTRUCTIONS := """Builds Metroidvania worlds with the Metroidvania Developer System plugin. Check mds_status first. Use mds_catalog rather than guessing ids (styles, shapes, effects, particles, enemies). Typical order: mds_world_create, mds_tileset_create, mds_area_set, mds_room_add, mds_gate_add and mds_gate_connect (or mds_area_generate), mds_area_generate_caves, mds_room_place, mds_enemy_configure, mds_game_scene_create, then mds_validate and mds_room_check. Keep seeds fixed so rebuilding gives the same rooms. Put related edits in mds_batch: they undo as one step. mds_room_ascii and mds_room_preview show a room. mds_undo takes back the last change."""

var ctx: MDSMcpContext
var tools: Array[Dictionary] = []
var tools_by_name: Dictionary = {}
var resources: MDSMcpResources
var prompts: MDSMcpPrompts
var groups: Array[MDSMcpTools] = []

var _busy := false
var _client := ""

func _init(host: MDSMcpHost = null, tier: MDSMcpGuard.Tier = MDSMcpGuard.Tier.AUTHOR, data_dir := MDSMcpGuard.DATA_DIR) -> void:
	ctx = MDSMcpContext.new(host if host else MDSMcpHost.new(), MDSMcpGuard.new(tier, data_dir))
	groups.assign([MDSMcpToolsCore.new(), MDSMcpToolsWorld.new(), MDSMcpToolsRoom.new(), MDSMcpToolsGame.new(), MDSMcpToolsCheck.new()])
	for group in groups:
		group.register(self)
	resources = MDSMcpResources.new(self)
	prompts = MDSMcpPrompts.new()

## The plugin's version, from its plugin.cfg.
static func server_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://addons/MetroidvaniaDeveloperSystem/plugin.cfg") != OK:
		return "0"
	return str(cfg.get_value("plugin", "version", "0"))

func add_tool(def: Dictionary) -> void:
	tools.append(def)
	tools_by_name[def.name] = def

## Answers [param text], one JSON-RPC message. Returns the answer, or "" for a notification.
func handle_text(text: String, progress := Callable()) -> String:
	var json := JSON.new()
	if json.parse(text) != OK:
		return MDSMcpSchema.to_json(error_response(null, PARSE_ERROR, "Parse error: %s" % json.get_error_message()))
	if not json.data is Dictionary:
		return MDSMcpSchema.to_json(error_response(null, INVALID_REQUEST, "A message must be one JSON object."))
	var answer: Dictionary = await handle(MDSMcpSchema.clean(json.data), progress)
	return MDSMcpSchema.to_json(answer) if not answer.is_empty() else ""

## Answers one JSON-RPC message, {} for a notification. [param progress]: called with a
## notification to send while a tool runs.
func handle(msg: Dictionary, progress := Callable()) -> Dictionary:
	var method := str(msg.get("method", ""))
	var has_id := msg.has("id")
	var id: Variant = msg.get("id")
	if method.is_empty() or str(msg.get("jsonrpc", "")) != "2.0":
		return error_response(id if has_id else null, INVALID_REQUEST, "Not a JSON-RPC 2.0 request.")
	if not has_id:
		return {} # initialized, cancelled, ...: nothing to do, nothing to answer
	var params: Variant = msg.get("params", {})
	if not params is Dictionary:
		return error_response(id, INVALID_PARAMS, "params must be an object.")
	var meta: Dictionary = params.get("_meta", {}) if params.get("_meta", {}) is Dictionary else {}
	var modern := meta.has(META_VERSION)
	if modern and not str(meta[META_VERSION]) in MODERN_VERSIONS:
		return error_response(id, UNSUPPORTED_VERSION, "Unsupported protocol version", {"supported": MODERN_VERSIONS + LEGACY_VERSIONS, "requested": meta[META_VERSION]})
	if meta.has(META_CLIENT) and meta[META_CLIENT] is Dictionary:
		_client = str(meta[META_CLIENT].get("name", ""))
	var result: Variant
	match method:
		"initialize":
			result = _initialize(params)
		"ping":
			result = {}
		"server/discover":
			result = _discover()
		"tools/list":
			result = _cacheable({"tools": list_tools()})
		"tools/call":
			result = await _tools_call(params, meta, progress)
		"resources/list":
			result = _cacheable({"resources": resources.list()})
		"resources/templates/list":
			result = _cacheable({"resourceTemplates": resources.templates()})
		"resources/read":
			result = await resources.read(str(params.get("uri", "")))
			if result.has("_rpc_error"):
				return error_response(id, INVALID_PARAMS, result._rpc_error, {"uri": params.get("uri", "")})
			result = _cacheable(result, 0)
		"prompts/list":
			result = _cacheable({"prompts": prompts.list()})
		"prompts/get":
			result = prompts.get_prompt(str(params.get("name", "")), params.get("arguments", {}))
			if result.has("_rpc_error"):
				return error_response(id, INVALID_PARAMS, result._rpc_error)
		_:
			return error_response(id, METHOD_NOT_FOUND, "Method not found: %s" % method)
	if result is Dictionary and result.has("_rpc_error"):
		return error_response(id, INVALID_PARAMS, result._rpc_error)
	return {"jsonrpc": "2.0", "id": id, "result": _modernized(result, modern or method == "server/discover")}

static func error_response(id: Variant, code: int, message: String, data: Variant = null) -> Dictionary:
	var error := {"code": code, "message": message}
	if data != null:
		error.data = data
	return {"jsonrpc": "2.0", "id": id, "error": error}

func _server_info() -> Dictionary:
	return {"name": SERVER_NAME, "title": "Metroidvania Developer System", "version": server_version()}

func _capabilities() -> Dictionary:
	return {"tools": {}, "resources": {}, "prompts": {}}

func _initialize(params: Dictionary) -> Dictionary:
	var client: Variant = params.get("clientInfo", {})
	if client is Dictionary:
		_client = str(client.get("name", ""))
	var asked := str(params.get("protocolVersion", ""))
	return {
		"protocolVersion": asked if asked in LEGACY_VERSIONS else LEGACY_VERSIONS[0],
		"capabilities": _capabilities(),
		"serverInfo": _server_info(),
		"instructions": INSTRUCTIONS,
	}

func _discover() -> Dictionary:
	return {
		"supportedVersions": MODERN_VERSIONS + LEGACY_VERSIONS,
		"capabilities": _capabilities(),
		"instructions": INSTRUCTIONS,
		"ttlMs": LIST_TTL_MSEC,
		"cacheScope": "private",
	}

## Marks a list or read result as cacheable, for the requests that want that.
func _cacheable(result: Dictionary, ttl := LIST_TTL_MSEC) -> Dictionary:
	result._ttl = ttl
	return result

## What the 2026-07-28 revision adds to every result, or takes them out for earlier clients.
func _modernized(result: Dictionary, modern: bool) -> Dictionary:
	var out := result.duplicate()
	var ttl: Variant = out.get("_ttl")
	out.erase("_ttl")
	if modern:
		out.resultType = "complete"
		if ttl != null:
			out.ttlMs = ttl
			out.cacheScope = "private"
		var meta: Dictionary = out.get("_meta", {})
		meta[META_SERVER] = _server_info()
		out._meta = meta
	return out

## The tools as tools/list gives them: in a fixed order, so clients can cache them.
func list_tools() -> Array:
	var out := []
	for t in tools:
		var read_only: bool = t.tier == MDSMcpGuard.Tier.READ
		out.append({
			"name": t.name,
			"description": t.description,
			"inputSchema": t.schema,
			"annotations": {
				"readOnlyHint": read_only,
				"destructiveHint": t.destructive,
				"idempotentHint": read_only,
				"openWorldHint": false,
			},
		})
	return out

func _tools_call(params: Dictionary, _meta: Dictionary, progress: Callable) -> Dictionary:
	var tool_name := str(params.get("name", ""))
	if not tools_by_name.has(tool_name):
		return {"_rpc_error": "Unknown tool: %s" % tool_name}
	var args: Variant = params.get("arguments", {})
	if not args is Dictionary:
		return {"_rpc_error": "arguments must be an object."}
	var token: Variant = _meta.get("progressToken")
	var report := Callable()
	if token != null and progress.is_valid():
		report = func(done: int, total: int, message: String) -> void:
			progress.call({"jsonrpc": "2.0", "method": "notifications/progress", "params": {"progressToken": token, "progress": done, "total": total, "message": message}})
	# One tool at a time: their steps must not interleave.
	var tree := Engine.get_main_loop() as SceneTree
	while _busy:
		await tree.process_frame
	_busy = true
	var result: Dictionary = await call_tool(tool_name, args, report)
	_busy = false
	return _tool_result(result)

## Runs a tool: checks its arguments and permissions, and runs it in a step of its own (or the
## batch's) when it writes. Returns its result, or a failure (see [method MDSMcpContext.fail]).
func call_tool(tool_name: String, args: Dictionary, report := Callable()) -> Dictionary:
	var def: Dictionary = tools_by_name.get(tool_name, {})
	if def.is_empty():
		return MDSMcpContext.fail("unknown_tool", "No tool named %s." % tool_name)
	var bad := MDSMcpSchema.check(args, def.schema)
	if not bad.is_empty():
		return MDSMcpContext.fail("bad_arguments", bad)
	if int(def.tier) > int(ctx.guard.tier):
		return MDSMcpContext.fail("tier_too_low", "%s needs the %s tier; this server runs at %s." % [tool_name, MDSMcpGuard.TIER_NAMES[def.tier], MDSMcpGuard.TIER_NAMES[ctx.guard.tier]], "The user can change it in the MetDevSys panel, or with --tier in the server's arguments.")
	if def.destructive and args.get("confirm") != true:
		return MDSMcpContext.fail("confirm_needed", "%s removes something, so it needs confirm: true." % tool_name)
	if def.editor_only and ctx.host.mode() != "editor":
		return MDSMcpContext.fail("requires_editor", "%s needs the Godot editor open with MCP turned on." % tool_name)
	var result: Dictionary
	if not def.writes:
		result = await def.handler.call(args, report)
		if not MDSMcpContext.is_failure(result):
			ctx.guard.audit(tool_name, _client, true, [])
		return result
	var refused: Dictionary = await ctx.begin(tool_name)
	if not refused.is_empty():
		return refused
	ctx.guard.allow_project_file = def.get("project_file", false)
	result = await def.handler.call(args, report)
	ctx.guard.allow_project_file = false
	var failed := MDSMcpContext.is_failure(result)
	var step := ctx.finish(not failed)
	if not step.is_empty():
		result.merge(step)
		ctx.guard.audit(tool_name, _client, not failed, step.get("changed", []))
	return result

## The result as MCP wants it: structured, and the same as text for clients without that.
func _tool_result(result: Dictionary) -> Dictionary:
	if MDSMcpContext.is_failure(result):
		var e: Dictionary = result._error
		return {"content": [{"type": "text", "text": MDSMcpSchema.to_json(e)}], "structuredContent": MDSMcpSchema.clean(e), "isError": true}
	var content := []
	if result.has("_image"):
		content.append({"type": "image", "data": result._image, "mimeType": "image/png"})
		result.erase("_image")
	var clean: Variant = MDSMcpSchema.clean(result)
	content.append({"type": "text", "text": JSON.stringify(clean)})
	return {"content": content, "structuredContent": clean, "isError": false}
