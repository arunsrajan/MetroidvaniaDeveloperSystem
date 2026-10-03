@tool
extends Control
## Interactive Dev Panel host: switches between the two map modes.
##
## - MetSys mode ([IDPMetSysPanel]): works on MetSys' grid MapData.txt.
## - Non-linear mode ([IDPWorldPanel]): free-form world map where scenes are drawn and
##   placed anywhere, connected by Hollow Knight-style named gates, saved as .idpworld.json.
##
## Panels are created on first use, so an unused mode costs nothing.
##
## The window menu (in the tool panel's title row) detaches the panel into a floating
## window or docks it in the main screen, the right dock or the bottom panel; the plugin
## does the move.

## Asks the plugin to move the panel (see the plugin's Placement enum).
signal placement_requested(placement: int)

enum Mode { METSYS, NON_LINEAR }
const MODE_NAMES: PackedStringArray = ["MetSys mode", "Non-linear mode"]
const SETTING_MODE := "interactive_dev_panel/mode"
const PLACEMENT_ITEMS: PackedStringArray = ["Dock in main screen (Map Dev tab)", "Detach to floating window", "Dock on the right", "Dock in bottom panel"]

var mode: int = Mode.METSYS
var mode_switch: OptionButton
var placement_menu: MenuButton
var placement := 0
var metsys_panel: IDPMetSysPanel
var world_panel: IDPWorldPanel

func _ready() -> void:
	if is_part_of_edited_scene():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mode_switch = OptionButton.new()
	for i in MODE_NAMES.size():
		mode_switch.add_item(MODE_NAMES[i], i)
	mode_switch.tooltip_text = "MetSys mode: MetSys' grid map (MapData.txt).\nNon-linear mode: draw and place scenes freely on a world map (.idpworld.json)."
	mode_switch.item_selected.connect(func(idx: int) -> void: set_mode(mode_switch.get_item_id(idx)))
	placement_menu = MenuButton.new()
	placement_menu.flat = true
	placement_menu.text = "⧉"
	placement_menu.tooltip_text = "Detach Map Dev into its own window, or dock it in the editor"
	var pm := placement_menu.get_popup()
	for i in PLACEMENT_ITEMS.size():
		pm.add_radio_check_item(PLACEMENT_ITEMS[i], i)
	pm.id_pressed.connect(func(id: int) -> void: placement_requested.emit(id))
	set_mode(saved_mode())

## The mode chosen last; without one, MetSys mode when MetSys is installed, else non-linear.
static func saved_mode() -> int:
	var fallback := Mode.METSYS if DirAccess.dir_exists_absolute("res://addons/MetroidvaniaSystem") else Mode.NON_LINEAR
	return int(ProjectSettings.get_setting(SETTING_MODE, fallback))

func set_mode(new_mode: int) -> void:
	mode = clampi(new_mode, 0, MODE_NAMES.size() - 1)
	if not ProjectSettings.has_setting(SETTING_MODE) or int(ProjectSettings.get_setting(SETTING_MODE)) != mode:
		ProjectSettings.set_setting(SETTING_MODE, mode)
		ProjectSettings.save()
	var panel := get_active_panel()
	if not panel:
		if mode == Mode.METSYS:
			metsys_panel = IDPMetSysPanel.new()
			panel = metsys_panel
		else:
			world_panel = IDPWorldPanel.new()
			panel = world_panel
		panel.name = "MetSysPanel" if mode == Mode.METSYS else "WorldPanel"
		add_child(panel)
	for p in [metsys_panel, world_panel]:
		if p:
			p.visible = p == panel
	# One switch, living at the start of the active panel's toolbar.
	if mode_switch.get_parent():
		mode_switch.get_parent().remove_child(mode_switch)
	panel.toolbar.add_child(mode_switch)
	panel.toolbar.move_child(mode_switch, 0)
	mode_switch.select(mode_switch.get_item_index(mode))
	# The window menu sits in the tool panel's title row, before the collapse button.
	if placement_menu.get_parent():
		placement_menu.get_parent().remove_child(placement_menu)
	panel.side_panel.header.add_child(placement_menu)
	panel.side_panel.header.move_child(placement_menu, 1)

## Updates the window menu's checkmarks (called by the plugin after a move).
func set_placement_state(current: int, main_screen_available: bool) -> void:
	placement = current
	var pm := placement_menu.get_popup()
	for i in pm.item_count:
		pm.set_item_checked(i, pm.get_item_id(i) == current)
	pm.set_item_disabled(pm.get_item_index(0), not main_screen_available)
	placement_menu.tooltip_text = "Map Dev is in the %s. Detach it into its own window, or dock it in the editor" % ["main screen", "floating window", "right dock", "bottom panel"][current]

func get_active_panel() -> Control:
	return metsys_panel if mode == Mode.METSYS else world_panel

## Forwarded by the plugin when a scene is saved in the editor.
func on_scene_saved(path: String) -> void:
	for p in [metsys_panel, world_panel]:
		if p:
			p.on_scene_saved(path)
