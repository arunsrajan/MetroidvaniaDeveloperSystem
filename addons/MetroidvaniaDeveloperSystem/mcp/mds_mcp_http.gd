@tool
class_name MDSMcpHttp
extends Node
## Streamable HTTP for MCP, on Godot's TCP classes (the engine has no HTTP server): one POST
## endpoint on the loopback address, polled on the main thread. Each request is answered with
## JSON, or with a stream of events when its tool reports progress.
##
## Before anything is parsed: the Host must be this server (against DNS rebinding), an Origin must
## be a loopback one on this port (403), and the bearer token must match (401).

const BIND_ADDRESS := "127.0.0.1"
const ENDPOINT := "/mcp"
const MAX_HEADER_BYTES := 16 * 1024
const MAX_BODY_BYTES := 8 * 1024 * 1024
const MAX_CONNECTIONS := 8
const IDLE_LIMIT_MSEC := 30000
## While clients are active the editor is polled this often (usec between frames): unfocused, it
## sleeps 100 ms between them.
const ACTIVE_SLEEP_USEC := 2000
const ACTIVE_LINGER_MSEC := 5000

var protocol: MDSMcpProtocol
var token := ""
var port := 0
## Requests answered, and when the last one came.
var requests := 0
var last_tool := ""

var _server := TCPServer.new()
var _connections: Array[Dictionary] = []
var _closing: Array[StreamPeerTCP] = []
var _last_activity := -ACTIVE_LINGER_MSEC
var _idle_sleep := -1

## Listens on [param p_port], or on the next ones when it is taken (0: any free port). Returns the
## error of the last try.
func start(p_protocol: MDSMcpProtocol, p_port: int, p_token: String, tries := 10) -> Error:
	protocol = p_protocol
	token = p_token
	var err := ERR_CANT_CREATE
	for i in tries:
		err = _server.listen(p_port + i if p_port > 0 else 0, BIND_ADDRESS)
		if err == OK:
			port = _server.get_local_port()
			return OK
	return err

func stop() -> void:
	_server.stop()
	for c in _connections:
		c.peer.disconnect_from_host()
	_connections.clear()
	if _idle_sleep >= 0 and OS.low_processor_usage_mode_sleep_usec == ACTIVE_SLEEP_USEC:
		OS.low_processor_usage_mode_sleep_usec = _idle_sleep
	_idle_sleep = -1

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _connections.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		_connections.append({"peer": peer, "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	for peer in _closing:
		peer.poll()
		peer.disconnect_from_host()
	_closing.clear()
	for c in _connections.duplicate():
		_poll_connection(c)
	_update_responsiveness()

func _update_responsiveness() -> void:
	if not Engine.is_editor_hint():
		return
	if not _connections.is_empty():
		_last_activity = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _last_activity < ACTIVE_LINGER_MSEC:
		if OS.low_processor_usage_mode_sleep_usec > ACTIVE_SLEEP_USEC:
			_idle_sleep = OS.low_processor_usage_mode_sleep_usec
			OS.low_processor_usage_mode_sleep_usec = ACTIVE_SLEEP_USEC
	elif _idle_sleep >= 0:
		if OS.low_processor_usage_mode_sleep_usec == ACTIVE_SLEEP_USEC:
			OS.low_processor_usage_mode_sleep_usec = _idle_sleep
		_idle_sleep = -1

func _poll_connection(c: Dictionary) -> void:
	var peer: StreamPeerTCP = c.peer
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_connections.erase(c)
		return
	var n := peer.get_available_bytes()
	if n > 0:
		c.buf.append_array(peer.get_data(n)[1])
		c.since = Time.get_ticks_msec()
	elif Time.get_ticks_msec() - c.since > IDLE_LIMIT_MSEC:
		_connections.erase(c)
		peer.disconnect_from_host()
		return
	var end := find_header_end(c.buf)
	if end < 0:
		if c.buf.size() > MAX_HEADER_BYTES:
			_reject(c, 431, "Request headers too large")
		return
	var request := parse_request(c.buf.slice(0, end))
	var problem := _request_problem(request)
	if problem.has("status"):
		_reject(c, problem.status, problem.message)
		return
	var length := int(request.headers.get("content-length", "-1"))
	if length < 0:
		_reject(c, 411, "Content-Length required")
		return
	if length > MAX_BODY_BYTES:
		_reject(c, 413, "Request too large")
		return
	if c.buf.size() < end + 4 + length:
		return
	_connections.erase(c)
	_serve(peer, request, c.buf.slice(end + 4, end + 4 + length))

## Index of the blank line ending the headers in [param buf], or -1.
static func find_header_end(buf: PackedByteArray) -> int:
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1

## {method, path, headers: lower-case name -> value}.
static func parse_request(head: PackedByteArray) -> Dictionary:
	var lines := head.get_string_from_utf8().split("\r\n")
	var first := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var at := lines[i].find(":")
		if at > 0:
			headers[lines[i].substr(0, at).strip_edges().to_lower()] = lines[i].substr(at + 1).strip_edges()
	return {"method": first[0] if first.size() > 0 else "", "path": first[1] if first.size() > 1 else "", "headers": headers}

## The status to refuse [param request] with, from its headers alone, or {}.
func _request_problem(request: Dictionary) -> Dictionary:
	var headers: Dictionary = request.headers
	if not str(headers.get("host", "")) in _allowed_hosts():
		return {"status": 403, "message": "Host not allowed"}
	if headers.has("origin") and not str(headers.origin) in _allowed_origins():
		return {"status": 403, "message": "Origin not allowed"}
	if request.path != ENDPOINT:
		return {"status": 404, "message": "Not found"}
	if request.method != "POST":
		return {"status": 405, "message": "Method not allowed"}
	if not same_token(str(headers.get("authorization", "")), "Bearer " + token):
		return {"status": 401, "message": "Unauthorized"}
	return {}

func _allowed_hosts() -> Array:
	return ["127.0.0.1:%d" % port, "localhost:%d" % port]

func _allowed_origins() -> Array:
	return ["http://127.0.0.1:%d" % port, "http://localhost:%d" % port]

## Compares in constant time, so a wrong token says nothing about how close it was.
static func same_token(given: String, wanted: String) -> bool:
	var a := given.to_utf8_buffer()
	var b := wanted.to_utf8_buffer()
	var diff := a.size() ^ b.size()
	for i in b.size():
		diff |= (a[i] if i < a.size() else 0) ^ b[i]
	return diff == 0

func _serve(peer: StreamPeerTCP, request: Dictionary, body: PackedByteArray) -> void:
	requests += 1
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		_respond_json(peer, 400, MDSMcpProtocol.error_response(null, MDSMcpProtocol.PARSE_ERROR, "The body must be one JSON-RPC message."))
		return
	var msg: Dictionary = MDSMcpSchema.clean(json.data)
	if str(msg.get("method", "")) == "tools/call" and msg.get("params") is Dictionary:
		last_tool = str(msg.params.get("name", ""))
	var mismatch := headers_mismatch(request.headers, msg)
	if not mismatch.is_empty():
		_respond_json(peer, 400, MDSMcpProtocol.error_response(msg.get("id"), MDSMcpProtocol.HEADER_MISMATCH, "Header mismatch: %s" % mismatch))
		return
	var wants_stream := str(request.headers.get("accept", "")).contains("text/event-stream") and _has_progress_token(msg)
	var progress := Callable()
	if wants_stream:
		_start_stream(peer)
		progress = func(note: Dictionary) -> void: _send_event(peer, note)
	var answer: Dictionary = await protocol.handle(msg, progress)
	if answer.is_empty():
		_respond_raw(peer, 202, "text/plain", PackedByteArray())
	elif wants_stream:
		_send_event(peer, answer)
		_closing.append(peer)
	else:
		_respond_json(peer, _status_of(answer), answer)

static func _has_progress_token(msg: Dictionary) -> bool:
	var params: Variant = msg.get("params")
	return params is Dictionary and params.get("_meta") is Dictionary and params._meta.has("progressToken")

## 2026-07-28 requests must repeat these in their headers. Why they don't match, or "".
static func headers_mismatch(headers: Dictionary, msg: Dictionary) -> String:
	var params: Variant = msg.get("params", {})
	var meta: Variant = params.get("_meta") if params is Dictionary else null
	if not meta is Dictionary or not meta.has(MDSMcpProtocol.META_VERSION):
		return ""
	if not headers.has("mcp-protocol-version"):
		return "MCP-Protocol-Version is missing"
	if headers["mcp-protocol-version"] != str(meta[MDSMcpProtocol.META_VERSION]):
		return "MCP-Protocol-Version doesn't match the body"
	if not msg.has("id"):
		return ""
	if not headers.has("mcp-method"):
		return "Mcp-Method is missing"
	if headers["mcp-method"] != str(msg.get("method", "")):
		return "Mcp-Method doesn't match the body"
	var named: Variant = _named_value(msg)
	if named != null:
		if not headers.has("mcp-name"):
			return "Mcp-Name is missing"
		if decode_header(str(headers["mcp-name"])) != str(named):
			return "Mcp-Name doesn't match the body"
	return ""

## The value Mcp-Name repeats, for the methods that have one.
static func _named_value(msg: Dictionary) -> Variant:
	var params: Variant = msg.get("params", {})
	if not params is Dictionary:
		return null
	match str(msg.get("method", "")):
		"tools/call", "prompts/get":
			return params.get("name")
		"resources/read":
			return params.get("uri")
	return null

## A header value, decoding the =?base64?...?= form used for values that aren't plain ASCII.
static func decode_header(value: String) -> String:
	if value.begins_with("=?base64?") and value.ends_with("?="):
		return Marshalls.base64_to_utf8(value.trim_prefix("=?base64?").trim_suffix("?="))
	return value

## The headers a 2026-07-28 request needs (for forwarding one), each with its line end.
static func request_headers(msg: Variant) -> String:
	if not msg is Dictionary:
		return ""
	var out := ""
	var params: Variant = msg.get("params", {})
	var meta: Variant = params.get("_meta") if params is Dictionary else null
	if meta is Dictionary and meta.has(MDSMcpProtocol.META_VERSION):
		out += "MCP-Protocol-Version: %s\r\n" % meta[MDSMcpProtocol.META_VERSION]
		if msg.has("method"):
			out += "Mcp-Method: %s\r\n" % msg.method
		var named: Variant = _named_value(msg)
		if named != null:
			out += "Mcp-Name: =?base64?%s?=\r\n" % Marshalls.utf8_to_base64(str(named))
	return out

## 2026-07-28 ties some errors to HTTP statuses.
static func _status_of(answer: Dictionary) -> int:
	if answer.has("error"):
		match int(answer.error.code):
			MDSMcpProtocol.UNSUPPORTED_VERSION:
				return 400
			MDSMcpProtocol.METHOD_NOT_FOUND:
				return 404
	return 200

func _reject(c: Dictionary, status: int, message: String) -> void:
	_connections.erase(c)
	_respond_json(c.peer, status, MDSMcpProtocol.error_response(null, MDSMcpProtocol.INVALID_REQUEST, message))

func _respond_json(peer: StreamPeerTCP, status: int, value: Dictionary) -> void:
	_respond_raw(peer, status, "application/json", MDSMcpSchema.to_json(value).to_utf8_buffer())

func _respond_raw(peer: StreamPeerTCP, status: int, content_type: String, body: PackedByteArray) -> void:
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, _reason(status), content_type, body.size()]
	peer.put_data(head.to_utf8_buffer())
	if not body.is_empty():
		peer.put_data(body)
	# Closed a frame later: closing now could cut off what is on its way.
	_closing.append(peer)

func _start_stream(peer: StreamPeerTCP) -> void:
	peer.put_data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nX-Accel-Buffering: no\r\nConnection: close\r\n\r\n".to_utf8_buffer())

func _send_event(peer: StreamPeerTCP, message: Dictionary) -> void:
	peer.poll()
	peer.put_data(("data: %s\n\n" % MDSMcpSchema.to_json(message)).to_utf8_buffer())

static func _reason(status: int) -> String:
	match status:
		200:
			return "OK"
		202:
			return "Accepted"
		400:
			return "Bad Request"
		401:
			return "Unauthorized"
		403:
			return "Forbidden"
		404:
			return "Not Found"
		405:
			return "Method Not Allowed"
		411:
			return "Length Required"
		413:
			return "Content Too Large"
		431:
			return "Request Header Fields Too Large"
	return "Error"
