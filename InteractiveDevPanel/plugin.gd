@tool
extends EditorPlugin

const MET_SYS_PLUGIN_NAME = "MetSys"
const MET_SYS_PLUGIN = "MetroidvaniaSystem"
## When true (default) the panel is a main screen tab next to 2D/3D/Script/MetSys;
## otherwise it is docked on the right like before. Re-enable the plugin after changing it.
const SETTING_MAIN_SCREEN = "interactive_dev_panel/use_main_screen"

var dock_instance: Control
var _in_main_screen := false
var _metsys_check_timer: Timer

func _enter_tree() -> void:
	if not ProjectSettings.has_setting(SETTING_MAIN_SCREEN):
		ProjectSettings.set_setting(SETTING_MAIN_SCREEN, true)
	ProjectSettings.set_initial_value(SETTING_MAIN_SCREEN, true)
	ProjectSettings.add_property_info({"name": SETTING_MAIN_SCREEN, "type": TYPE_BOOL})
	# Game scene "Play from here" boots (empty: detected per room).
	if not ProjectSettings.has_setting(IDPPlayHere.SETTING_PLAY_SCENE):
		ProjectSettings.set_setting(IDPPlayHere.SETTING_PLAY_SCENE, "")
	ProjectSettings.set_initial_value(IDPPlayHere.SETTING_PLAY_SCENE, "")
	ProjectSettings.add_property_info({"name": IDPPlayHere.SETTING_PLAY_SCENE, "type": TYPE_STRING, "hint": PROPERTY_HINT_FILE, "hint_string": "*.tscn,*.scn"})
	_init_plugin()
	scene_saved.connect(_on_scene_saved)

func _exit_tree() -> void:
	_clean_plugin()

func _has_main_screen() -> bool:
	return ProjectSettings.get_setting(SETTING_MAIN_SCREEN, true)

func _get_plugin_name() -> String:
	return "Map Dev"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"TileMapLayer", &"EditorIcons")

func _make_visible(visible: bool) -> void:
	if dock_instance and _in_main_screen:
		dock_instance.visible = visible

func _on_scene_saved(path: String) -> void:
	if dock_instance and dock_instance.has_method("on_scene_saved"):
		dock_instance.on_scene_saved(path)

func _init_plugin() -> void:
	if dock_instance:
		return
	_in_main_screen = _has_main_screen()
	dock_instance = preload("res://addons/InteractiveDevPanel/dock.tscn").instantiate()
	if _in_main_screen:
		dock_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
		EditorInterface.get_editor_main_screen().add_child(dock_instance)
		dock_instance.hide()
	else:
		dock_instance.custom_minimum_size = Vector2(420, 480)
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
	_check_metsys()

## The panel works from MapData.txt alone, but room sizes, the default map path and theme
## colors come from MetSys, so keep reminding until it is enabled.
func _check_metsys() -> void:
	# Non-linear mode doesn't use MetSys.
	if int(ProjectSettings.get_setting("interactive_dev_panel/mode", 0)) != 0:
		_clear_check_timer()
		return
	if EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN_NAME) or EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN):
		_clear_check_timer()
		return
	EditorInterface.get_editor_toaster().push_toast("MetSys plugin should be installed and enabled in project settings for InteractiveDevPanel to work.", EditorToaster.SEVERITY_WARNING)
	if not _metsys_check_timer:
		_metsys_check_timer = Timer.new()
		_metsys_check_timer.wait_time = 30.0
		_metsys_check_timer.timeout.connect(_check_metsys)
		_metsys_check_timer.autostart = true
		add_child(_metsys_check_timer)

func _clean_plugin() -> void:
	_clear_check_timer()
	if dock_instance:
		if _in_main_screen:
			dock_instance.get_parent().remove_child(dock_instance)
		else:
			remove_control_from_docks(dock_instance)
		dock_instance.free()
		dock_instance = null

func _clear_check_timer() -> void:
	if _metsys_check_timer:
		remove_child(_metsys_check_timer)
		_metsys_check_timer.queue_free()
		_metsys_check_timer = null
