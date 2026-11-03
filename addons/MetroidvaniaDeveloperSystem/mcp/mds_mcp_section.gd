@tool
class_name MDSMcpSection
extends VBoxContainer
## The panel's MCP section: on or off, how much it may do, and what to paste into a client.

var _on: CheckBox
var _tier: OptionButton
var _status: Label
var _copy: MenuButton
var _timer: Timer

func _ready() -> void:
	_on = CheckBox.new()
	_on.text = "Let AI tools connect"
	_on.tooltip_text = "Serves MCP to AI tools (Claude Code, Cursor...) on this computer only.\nOff, they can still work on the project's files while the editor is closed."
	_on.toggled.connect(func(on: bool) -> void:
		if MDSMcpEditor.current:
			MDSMcpEditor.current.set_enabled(on))
	add_child(_on)

	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = "Allow"
	row.add_child(label)
	_tier = OptionButton.new()
	_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier.add_item("Reading only", MDSMcpGuard.Tier.READ)
	_tier.add_item("Building (default)", MDSMcpGuard.Tier.AUTHOR)
	_tier.add_item("Building and project settings", MDSMcpGuard.Tier.FULL)
	_tier.item_selected.connect(func(index: int) -> void:
		if MDSMcpEditor.current:
			MDSMcpEditor.current.set_tier(_tier.get_item_id(index) as MDSMcpGuard.Tier))
	row.add_child(_tier)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_copy = MenuButton.new()
	_copy.text = "Copy config"
	_copy.flat = false
	var menu := _copy.get_popup()
	menu.add_item("Claude Code command", 0)
	menu.add_item("JSON (Cursor, VS Code, Claude Desktop...)", 1)
	menu.add_item("Direct to this editor (has the token)", 2)
	menu.id_pressed.connect(func(id: int) -> void:
		if MDSMcpEditor.current:
			DisplayServer.clipboard_set(MDSMcpEditor.current.config_for(["claude", "json", "http"][id])))
	add_child(_copy)

	_timer = Timer.new()
	_timer.wait_time = 2.0
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	_timer.start()
	_refresh()

func _refresh() -> void:
	var mcp := MDSMcpEditor.current
	visible = mcp != null
	if not mcp:
		return
	_on.set_pressed_no_signal(mcp.is_enabled())
	_tier.select(_tier.get_item_index(mcp.get_tier()))
	_copy.get_popup().set_item_disabled(2, mcp.http == null)
	if not mcp.problem.is_empty():
		_status.text = mcp.problem
	elif mcp.http:
		_status.text = "On, port %d. %d request(s)%s." % [mcp.port(), mcp.http.requests, ", last tool %s" % mcp.http.last_tool if not mcp.http.last_tool.is_empty() else ""]
	else:
		_status.text = "Off."
