@tool
extends Control
## Interactive Dev Panel host: switches between the two map modes.
##
## - MetSys mode ([IDPMetSysPanel]): works on MetSys' grid MapData.txt.
## - Non-linear mode ([IDPWorldPanel]): free-form world map where scenes are drawn and
##   placed anywhere, connected by Hollow Knight-style named gates, saved as .idpworld.json.
##
## Panels are created on first use, so an unused mode costs nothing.

enum Mode { METSYS, NON_LINEAR }
const MODE_NAMES: PackedStringArray = ["MetSys mode", "Non-linear mode"]
const SETTING_MODE := "interactive_dev_panel/mode"

var mode: int = Mode.METSYS
var mode_switch: OptionButton
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
	set_mode(int(ProjectSettings.get_setting(SETTING_MODE, Mode.METSYS)))

func set_mode(new_mode: int) -> void:
	mode = clampi(new_mode, 0, MODE_NAMES.size() - 1)
	if int(ProjectSettings.get_setting(SETTING_MODE, Mode.METSYS)) != mode:
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

func get_active_panel() -> Control:
	return metsys_panel if mode == Mode.METSYS else world_panel

## Forwarded by the plugin when a scene is saved in the editor.
func on_scene_saved(path: String) -> void:
	for p in [metsys_panel, world_panel]:
		if p:
			p.on_scene_saved(path)
