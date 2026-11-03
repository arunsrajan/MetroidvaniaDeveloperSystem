@tool
class_name MDSMcpStdioServer
extends RefCounted
## What [code]mds_mcp_main.gd[/code] does with a message once the plugin's classes are there: sends
## it to the editor if one is listening, otherwise answers it here.

const HTTP_TIMEOUT_MSEC := 600000

var protocol: MDSMcpProtocol

func _init() -> void:
	var tier := MDSMcpGuard.Tier.AUTHOR
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tier="):
			tier = MDSMcpGuard.tier_from_name(a.trim_prefix("--tier="))
	protocol = MDSMcpProtocol.new(MDSMcpHost.new(), tier)

func answer(line: String) -> void:
	var live := MDSMcpEndpoint.read_live()
	if int(live.get("port", 0)) > 0:
		var sent: int = await _forward(line, live)
		if sent != ERR_CANT_CONNECT:
			return
	var reply := await protocol.handle_text(line, _send_notification)
	if not reply.is_empty():
		MDSMcpStdio.send(reply)

func _send_notification(message: Dictionary) -> void:
	MDSMcpStdio.send(MDSMcpSchema.to_json(message))

## Sends [param line] to the editor and passes on what comes back. ERR_CANT_CONNECT: the editor
## wasn't reached, so nothing happened there.
func _forward(line: String, live: Dictionary) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", live.port) != OK:
		return ERR_CANT_CONNECT
	var until := Time.get_ticks_msec() + 3000
	while true:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			break
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE or Time.get_ticks_msec() > until:
			return ERR_CANT_CONNECT
		await tree.process_frame
	var parsed: Variant = JSON.parse_string(line)
	var body := line.to_utf8_buffer()
	var head := "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nContent-Length: %d\r\n%sConnection: close\r\n\r\n" % [live.port, live.token, body.size(), MDSMcpHttp.request_headers(parsed)]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	var buf := PackedByteArray()
	var header_end := -1
	var sse := false
	until = Time.get_ticks_msec() + HTTP_TIMEOUT_MSEC
	while Time.get_ticks_msec() < until:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_data(n)[1])
			if header_end < 0:
				header_end = MDSMcpHttp.find_header_end(buf)
				if header_end >= 0:
					sse = buf.slice(0, header_end).get_string_from_utf8().to_lower().contains("text/event-stream")
					buf = buf.slice(header_end + 4)
			if header_end >= 0 and sse:
				buf = _pass_events(buf)
		else:
			await tree.process_frame
	if header_end < 0:
		_send_lost(parsed)
	elif not sse and not buf.is_empty():
		MDSMcpStdio.send(buf.get_string_from_utf8())
	return OK

## Sends on the whole events in [param buf]; returns what is left of it.
func _pass_events(buf: PackedByteArray) -> PackedByteArray:
	var text := buf.get_string_from_utf8()
	var end := text.rfind("\n\n")
	if end < 0:
		return buf
	for event in text.substr(0, end).split("\n\n", false):
		for l in event.split("\n", false):
			if l.begins_with("data:"):
				MDSMcpStdio.send(l.trim_prefix("data:").strip_edges())
	return text.substr(end + 2).to_utf8_buffer()

func _send_lost(parsed: Variant) -> void:
	if parsed is Dictionary and parsed.has("id"):
		_send_notification(MDSMcpProtocol.error_response(parsed.id, MDSMcpProtocol.INTERNAL_ERROR, "The editor stopped answering during this request. Retry it."))
