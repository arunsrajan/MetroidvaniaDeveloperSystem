extends "res://tests/mcp_test_case.gd"
## The MCP HTTP server over real sockets, on a port of its own: what it checks before anything is
## parsed, what MCP asks of it, and requests that don't arrive in one piece.

const TOKEN := "test-token"
const MODERN := "2026-07-28"
const PING := '{"jsonrpc":"2.0","id":1,"method":"ping"}'

var http: MDSMcpHttp

func _run() -> void:
	start_server(MDSMcpGuard.Tier.READ)
	http = MDSMcpHttp.new()
	add_child(http)
	check(http.start(server, 0, TOKEN) == OK and http.port > 0, "listens on a free port")
	var other := TCPServer.new()
	check(other.listen(http.port, MDSMcpHttp.BIND_ADDRESS) != OK, "the port is taken")

	# Legacy: no MCP headers needed.
	var r := await _post(PING)
	check(r.status == 200 and r.json.id == 1 and r.headers.contains("application/json"), "a plain request: %s" % r.status)

	# Who may ask.
	r = await _post(PING, {"Authorization": "Bearer wrong"})
	check(r.status == 401, "a wrong token: %s" % r.status)
	r = await _post(PING, {"Authorization": ""})
	check(r.status == 401, "no token: %s" % r.status)
	r = await _post(PING, {"Origin": "https://evil.example"})
	check(r.status == 403, "another site: %s" % r.status)
	r = await _post(PING, {"Origin": "http://127.0.0.1:%d" % http.port})
	check(r.status == 200, "the server's own origin: %s" % r.status)
	r = await _post(PING, {"Origin": "http://localhost:%d" % http.port})
	check(r.status == 200, "localhost too: %s" % r.status)
	r = await _post(PING, {"Origin": "http://127.0.0.1:1"})
	check(r.status == 403, "another port: %s" % r.status)
	r = await _post(PING, {"Host": "evil.example:%d" % http.port})
	check(r.status == 403, "another host, as DNS rebinding sends: %s" % r.status)
	r = await _raw("GET /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\n\r\n" % [http.port, TOKEN])
	check(r.status == 405, "GET: %s" % r.status)
	r = await _raw("DELETE /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\nContent-Length: 0\r\n\r\n" % [http.port, TOKEN])
	check(r.status == 405, "DELETE: %s" % r.status)
	r = await _raw("POST /other HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\nContent-Length: 0\r\n\r\n" % [http.port, TOKEN])
	check(r.status == 404, "another path: %s" % r.status)
	check(MDSMcpHttp.same_token("abc", "abc") and not MDSMcpHttp.same_token("abd", "abc") and not MDSMcpHttp.same_token("ab", "abc") and not MDSMcpHttp.same_token("abcd", "abc"), "comparing tokens")

	# Notifications, broken bodies.
	r = await _post('{"jsonrpc":"2.0","method":"notifications/initialized"}')
	check(r.status == 202 and r.body.is_empty(), "a notification: %s" % r.status)
	r = await _post("{nope")
	check(r.status == 400 and r.json.error.code == -32700, "broken JSON: %s" % r.status)

	# 2026-07-28: the headers must match the body.
	var modern := _modern("tools/call", {"name": "mds_status", "arguments": {}})
	r = await _post(modern, {"MCP-Protocol-Version": MODERN, "Mcp-Method": "tools/call", "Mcp-Name": "mds_status"})
	check(r.status == 200 and r.json.result.resultType == "complete", "a modern request: %s" % r.status)
	check(r.json.result.structuredContent.tier == "read", "its result")
	r = await _post(modern, {"Mcp-Method": "tools/call", "Mcp-Name": "mds_status"})
	check(r.status == 400 and r.json.error.code == -32020, "no version header: %s" % r.status)
	r = await _post(modern, {"MCP-Protocol-Version": MODERN, "Mcp-Method": "tools/list", "Mcp-Name": "mds_status"})
	check(r.status == 400 and r.json.error.code == -32020, "another method in the header: %s" % r.status)
	r = await _post(modern, {"MCP-Protocol-Version": MODERN, "Mcp-Method": "tools/call", "Mcp-Name": "mds_catalog"})
	check(r.status == 400 and r.json.error.code == -32020, "another tool in the header: %s" % r.status)
	r = await _post(modern, {"MCP-Protocol-Version": MODERN, "Mcp-Method": "tools/call", "Mcp-Name": "=?base64?%s?=" % Marshalls.utf8_to_base64("mds_status")})
	check(r.status == 200, "a name in base64: %s" % r.status)
	r = await _post(_modern("no/such", {}), {"MCP-Protocol-Version": MODERN, "Mcp-Method": "no/such"})
	check(r.status == 404 and r.json.error.code == -32601, "an unknown method: %s" % r.status)
	var old := '{"jsonrpc":"2.0","id":1,"method":"ping","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"1999-01-01"}}}'
	r = await _post(old, {"MCP-Protocol-Version": "1999-01-01", "Mcp-Method": "ping"})
	check(r.status == 400 and r.json.error.code == -32022, "an unknown version: %s" % r.status)
	check(MDSMcpHttp.request_headers(JSON.parse_string(modern)).contains("Mcp-Name: =?base64?"), "forwarding sends the headers")

	# Requests in pieces, and too large.
	var head := "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n" % [http.port, TOKEN, PING.length()]
	r = await _raw(head + PING, 7)
	check(r.status == 200 and r.json.id == 1, "split into small packets: %s" % r.status)
	r = await _raw("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\nContent-Length: %d\r\n\r\n" % [http.port, TOKEN, MDSMcpHttp.MAX_BODY_BYTES + 1])
	check(r.status == 413, "too large: %s" % r.status)
	r = await _raw("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\n\r\n" % [http.port, TOKEN])
	check(r.status == 411, "no length: %s" % r.status)
	r = await _raw("POST /mcp HTTP/1.1\r\nX-Pad: %s" % "x".repeat(MDSMcpHttp.MAX_HEADER_BYTES + 10))
	check(r.status == 431, "headers too large: %s" % r.status)
	var big := '{"jsonrpc":"2.0","id":7,"method":"ping","params":{"pad":"%s"}}' % "é".repeat(200000)
	r = await _post(big)
	check(r.status == 200 and r.json.id == 7, "a large request in UTF-8: %s" % r.status)

	# Long tools report progress as events, when asked for.
	var batch := {"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "mds_status", "arguments": {}, "_meta": {"progressToken": "p"}}}
	r = await _post(JSON.stringify(batch), {"Accept": "application/json, text/event-stream"})
	check(r.status == 200 and r.headers.to_lower().contains("text/event-stream"), "an event stream: %s" % r.headers)
	check(r.body.contains("data: ") and r.body.contains('"id":9'), "with the answer as an event: %s" % r.body.left(200))
	check(http.requests > 5 and http.last_tool == "mds_status", "the status the panel shows")

	# More connections than it takes: still answers afterwards.
	var idle: Array[StreamPeerTCP] = []
	for i in MDSMcpHttp.MAX_CONNECTIONS + 3:
		var peer := StreamPeerTCP.new()
		peer.connect_to_host(MDSMcpHttp.BIND_ADDRESS, http.port)
		idle.append(peer)
	for i in 5:
		await get_tree().process_frame
	for peer in idle:
		peer.disconnect_from_host()
	for i in 5:
		await get_tree().process_frame
	r = await _post(PING)
	check(r.status == 200, "after a crowd: %s" % r.status)

	http.stop()
	check(not TCPServer.new().is_listening(), "stopped")
	var freed := TCPServer.new()
	check(freed.listen(http.port, MDSMcpHttp.BIND_ADDRESS) == OK, "stopping frees the port")
	freed.stop()
	http.queue_free()
	end_server()

func _modern(method: String, params: Dictionary) -> String:
	var p := params.duplicate()
	p._meta = {"io.modelcontextprotocol/protocolVersion": MODERN, "io.modelcontextprotocol/clientInfo": {"name": "t", "version": "1"}}
	return JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": method, "params": p})

func _post(body: String, headers := {}) -> Dictionary:
	var all := {"Host": "127.0.0.1:%d" % http.port, "Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"}
	all.merge(headers, true)
	var text := "POST /mcp HTTP/1.1\r\n"
	for key: String in all:
		if not str(all[key]).is_empty():
			text += "%s: %s\r\n" % [key, all[key]]
	text += "Content-Length: %d\r\n\r\n" % body.to_utf8_buffer().size()
	return await _raw(text + body)

## Sends [param text], in pieces of [param piece] bytes when given, and reads the answer.
func _raw(text: String, piece := 0) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host(MDSMcpHttp.BIND_ADDRESS, http.port)
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		peer.poll()
		await get_tree().process_frame
	var bytes := text.to_utf8_buffer()
	if piece > 0:
		var at := 0
		while at < bytes.size():
			peer.put_data(bytes.slice(at, at + piece))
			at += piece
			await get_tree().process_frame
	else:
		peer.put_data(bytes)
	var got := PackedByteArray()
	var until := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		else:
			await get_tree().process_frame
	var end := MDSMcpHttp.find_header_end(got)
	if end < 0:
		return {"status": 0, "headers": "", "body": "", "json": {}}
	var headers := got.slice(0, end).get_string_from_utf8()
	var body := got.slice(end + 4).get_string_from_utf8()
	var json: Variant = JSON.parse_string(body) if body.begins_with("{") else null
	return {"status": headers.split(" ")[1].to_int(), "headers": headers, "body": body, "json": MDSMcpSchema.clean(json) if json is Dictionary else {}}
