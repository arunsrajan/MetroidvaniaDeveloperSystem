extends "res://tests/test_case.gd"
## The MCP protocol without any transport: both generations, ids, errors, the list of tools.

const DATA := TMP + "/mcp_protocol_data"
const Case := preload("res://tests/mcp_test_case.gd")

func _run() -> void:
	var p := MDSMcpProtocol.new(MDSMcpHost.new(), MDSMcpGuard.Tier.READ, DATA)

	# Modern: stateless, with the version in _meta.
	var meta := {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientInfo": {"name": "t", "version": "1"}}
	var discover: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {"_meta": meta}})
	check(discover.id == 1, "the id comes back as it was")
	check("2026-07-28" in discover.result.supportedVersions and "2025-11-25" in discover.result.supportedVersions, "server/discover lists both generations")
	check(discover.result.resultType == "complete" and discover.result.has("ttlMs"), "server/discover is complete and cacheable")
	check(discover.result._meta.has("io.modelcontextprotocol/serverInfo"), "server/discover names the server")
	var listed: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {"_meta": meta}})
	check(listed.result.resultType == "complete" and listed.result.ttlMs > 0 and listed.result.cacheScope == "private", "tools/list has the modern fields")
	check(not listed.result.has("_ttl"), "internal fields stay in")

	# Modern, with a version the server doesn't speak.
	var wrong: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 3, "method": "tools/list", "params": {"_meta": {"io.modelcontextprotocol/protocolVersion": "1999-01-01"}}})
	check(wrong.error.code == -32022 and wrong.error.data.requested == "1999-01-01", "an unknown version gets -32022")

	# Legacy: the handshake, no modern fields.
	var init: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 4, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "old", "version": "1"}}})
	check(init.result.protocolVersion == "2025-06-18", "initialize takes a version it knows")
	check(not init.result.has("resultType"), "legacy results stay as they were")
	var newest: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 5, "method": "initialize", "params": {"protocolVersion": "2020-01-01"}})
	check(newest.result.protocolVersion == "2025-11-25", "initialize offers its newest for one it doesn't")
	check((await p.handle({"jsonrpc": "2.0", "method": "notifications/initialized"})).is_empty(), "a notification has no answer")
	check((await p.handle({"jsonrpc": "2.0", "id": 6, "method": "ping"})).result.is_empty(), "ping")
	var old_list: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 7, "method": "tools/list"})
	check(not old_list.result.has("resultType") and not old_list.result.has("ttlMs"), "legacy tools/list has no modern fields")

	# Text in, text out: numbers, and what isn't JSON.
	var text: String = await p.handle_text('{"jsonrpc":"2.0","id":1,"method":"ping"}')
	check(text.contains('"id":1') and not text.contains("1.0"), "an id of 1 stays 1: %s" % text)
	var bad: String = await p.handle_text("{nope")
	check(JSON.parse_string(bad).error.code == -32700, "broken JSON gets -32700")
	var not_object: String = await p.handle_text("[1,2]")
	check(JSON.parse_string(not_object).error.code == -32600, "a batch array gets -32600")
	var string_id: Dictionary = await p.handle({"jsonrpc": "2.0", "id": "abc", "method": "ping"})
	check(string_id.id == "abc", "a string id comes back")
	var unknown: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 8, "method": "no/such"})
	check(unknown.error.code == -32601, "an unknown method gets -32601")

	# Tools.
	var tools: Array = listed.result.tools
	var names: Array = tools.map(func(t: Dictionary) -> String: return t.name)
	for wanted in ["mds_status", "mds_catalog", "mds_batch", "mds_undo", "mds_world_create", "mds_room_generate", "mds_enemy_configure", "mds_validate", "mds_room_preview", "mds_editor_open"]:
		check(wanted in names, "%s is listed" % wanted)
	var again: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 9, "method": "tools/list"})
	check(again.result.tools.map(func(t: Dictionary) -> String: return t.name) == names, "the order of the tools doesn't change")
	for t: Dictionary in tools:
		check(t.inputSchema.type == "object" and t.description.length() < 500, "%s has an object schema and a short description" % t.name)
		check(t.annotations.has("readOnlyHint") and t.annotations.has("destructiveHint"), "%s has annotations" % t.name)
	var status: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": {"name": "mds_status", "arguments": {}}})
	check(not status.result.isError and status.result.structuredContent.mode == "headless", "mds_status runs")
	check(JSON.parse_string(status.result.content[0].text).tier == "read", "the same result as text")
	var no_tool: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 11, "method": "tools/call", "params": {"name": "nope"}})
	check(no_tool.has("error") and no_tool.error.code == -32602, "an unknown tool gets -32602")
	var catalog: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 12, "method": "tools/call", "params": {"name": "mds_catalog", "arguments": {"kind": "attack_fx"}}})
	check(catalog.result.structuredContent.items.size() == 30, "the catalog has the 30 attack effects")
	var bad_args: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 13, "method": "tools/call", "params": {"name": "mds_catalog", "arguments": {"kind": "nope"}}})
	check(bad_args.result.isError and bad_args.result.structuredContent.code == "bad_arguments", "bad arguments are a tool error")

	# Resources and prompts.
	var res: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 14, "method": "resources/list"})
	check(res.result.resources.size() >= 3, "resources are listed")
	var worlds: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 15, "method": "resources/read", "params": {"uri": "mds://worlds"}})
	check(worlds.result.contents[0].mimeType == "application/json", "a resource can be read")
	var gone: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 16, "method": "resources/read", "params": {"uri": "mds://nope"}})
	check(gone.error.code == -32602, "a missing resource gets -32602")
	var prompts: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 17, "method": "prompts/list"})
	check(prompts.result.prompts.size() == 5, "five prompts")
	var prompt: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 18, "method": "prompts/get", "params": {"name": "build_area", "arguments": {"theme": "ice", "rooms": "4"}}})
	check(prompt.result.messages[0].content.text.contains("ice"), "a prompt takes its arguments")
	var missing: Dictionary = await p.handle({"jsonrpc": "2.0", "id": 19, "method": "prompts/get", "params": {"name": "build_area"}})
	check(missing.has("error"), "a prompt needs its required arguments")
	p = null
	Case.clean_folder(DATA)
