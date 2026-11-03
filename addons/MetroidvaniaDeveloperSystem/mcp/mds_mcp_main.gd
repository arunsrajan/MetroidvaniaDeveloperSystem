@tool
extends SceneTree
## The MCP server's command, the one every client is given:
##   godot --headless --no-header --path <project> --script res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_main.gd [-- --tier=read|author|full --show-errors]
##
## Reads MCP messages from stdin and answers on stdout. With an editor open on the project and MCP
## on, each message goes to the editor; otherwise it is answered here. The check is made per message,
## so the editor can open and close during a session.
##
## This script names no class of the plugin: on a fresh clone Godot hasn't registered them yet
## (that takes an --import), and it has to be able to say so.

const STDIO := "res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_stdio.gd"
const SERVER_PATH := "res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_stdio_server.gd"
const NEEDED_CLASS := &"MDSMcpProtocol"

var _stdio: RefCounted
var _server: RefCounted
var _not_ready := ""
var _queue: Array[String] = []
var _working := false

func _init() -> void:
	if not OS.has_feature("editor"):
		printerr("The MCP server only runs with the Godot editor's executable, not in an exported game.")
		quit(2)
		return
	# Stdout is only for MCP: what a scene's script prints stays out of it (see MDSMcpStdio.send).
	# Stderr stays quiet too: a client may never read it, and a pipe nobody reads stops the process.
	Engine.print_to_stdout = false
	Engine.print_error_messages = "--show-errors" in OS.get_cmdline_user_args()
	_stdio = load(STDIO).new()
	_stdio.start()
	if _class_registered():
		_server = load(SERVER_PATH).new()
	else:
		_not_ready = "Godot hasn't imported this project yet, or not since the plugin changed. Run once: godot --headless --path \"%s\" --import" % ProjectSettings.globalize_path("res://")
	process_frame.connect(_tick)

func _class_registered() -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c.class == NEEDED_CLASS:
			return true
	return false

func _tick() -> void:
	for line: String in _stdio.take_lines():
		_queue.append(line)
	if _working:
		return
	if not _queue.is_empty():
		_working = true
		await _answer(_queue.pop_front())
		_working = false
	elif _stdio.eof:
		quit(0)

func _answer(line: String) -> void:
	if _server:
		await _server.answer(line)
		return
	var parsed: Variant = JSON.parse_string(line)
	if parsed is Dictionary and parsed.has("id"):
		_stdio.send(JSON.stringify({"jsonrpc": "2.0", "id": int(parsed.id) if parsed.id is float else parsed.id, "error": {"code": -32603, "message": _not_ready}}))
