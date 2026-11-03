@tool
class_name MDSMcpEditor
extends Node
## The MCP server's life in the editor, a child of the plugin. Off until the user turns it on: the
## choice is kept per user and machine in the project's metadata, not in project.godot, so a cloned
## project can't open a port by itself. While the editor runs, the endpoint file says so (port 0
## when off), which keeps other MCP processes from writing behind its back.

signal status_changed

const SECTION := "metroidvania_developer_system"
const KEY_ENABLED := "mcp_enabled"
const KEY_TIER := "mcp_tier"
const KEY_TOKEN := "mcp_token"
const FIRST_PORT := 6590
const MAIN_SCRIPT := "res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_main.gd"

## The running editor's, for the panel to find.
static var current: MDSMcpEditor

var http: MDSMcpHttp
var problem := ""

var _panel_getter: Callable

func _init(panel_getter: Callable) -> void:
	_panel_getter = panel_getter
	name = "MDSMcp"

func _enter_tree() -> void:
	current = self
	_apply()
	var refresh := Timer.new()
	refresh.wait_time = MDSMcpEndpoint.REFRESH_SEC
	refresh.timeout.connect(_write_endpoint)
	add_child(refresh)
	refresh.start()

func _exit_tree() -> void:
	_stop()
	MDSMcpEndpoint.remove()
	if current == self:
		current = null

static func _meta(key: String, default: Variant) -> Variant:
	return EditorInterface.get_editor_settings().get_project_metadata(SECTION, key, default)

static func _set_meta_value(key: String, value: Variant) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(SECTION, key, value)

func is_enabled() -> bool:
	return bool(_meta(KEY_ENABLED, false))

func set_enabled(on: bool) -> void:
	_set_meta_value(KEY_ENABLED, on)
	_apply()

func get_tier() -> MDSMcpGuard.Tier:
	return MDSMcpGuard.tier_from_name(str(_meta(KEY_TIER, "author")))

func set_tier(tier: MDSMcpGuard.Tier) -> void:
	_set_meta_value(KEY_TIER, MDSMcpGuard.TIER_NAMES[tier])
	_apply()

## The bearer token, made the first time it is needed: 256 random bits.
func token() -> String:
	var t := str(_meta(KEY_TOKEN, ""))
	if t.is_empty():
		t = Crypto.new().generate_random_bytes(32).hex_encode()
		_set_meta_value(KEY_TOKEN, t)
	return t

func port() -> int:
	return http.port if http else 0

func _stop() -> void:
	if http:
		http.stop()
		remove_child(http)
		http.free()
		http = null

func _apply() -> void:
	_stop()
	problem = ""
	if is_enabled():
		http = MDSMcpHttp.new()
		http.name = "Http"
		add_child(http)
		var err := http.start(MDSMcpProtocol.new(MDSMcpEditorHost.new(_panel_getter), get_tier()), FIRST_PORT, token())
		if err != OK:
			problem = "No free port from %d on: %s" % [FIRST_PORT, error_string(err)]
			_stop()
	_write_endpoint()
	status_changed.emit()

func _write_endpoint() -> void:
	MDSMcpEndpoint.write(port(), token() if http else "")

## The command every client runs, its arguments quoted for a terminal.
func stdio_args() -> PackedStringArray:
	return ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://").trim_suffix("/"), "--script", MAIN_SCRIPT]

## Text to paste to set up a client: "claude" (the command), "json" (for mcpServers), "http" (the
## command for connecting straight to this editor, with its token: never commit it).
func config_for(kind: String) -> String:
	var exe := OS.get_executable_path()
	match kind:
		"claude":
			var parts := PackedStringArray()
			for a in stdio_args():
				parts.append("\"%s\"" % a if a.contains(" ") else a)
			return "claude mcp add --transport stdio mds -- \"%s\" %s" % [exe, " ".join(parts)]
		"http":
			return "claude mcp add --transport http mds http://127.0.0.1:%d%s --header \"Authorization: Bearer %s\"" % [port(), MDSMcpHttp.ENDPOINT, token()]
	return JSON.stringify({"mcpServers": {"mds": {"command": exe, "args": Array(stdio_args())}}}, "  ")
