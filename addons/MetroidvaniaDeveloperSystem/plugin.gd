@tool
extends EditorPlugin

const MET_SYS_PLUGIN_NAME = "MetSys"
const MET_SYS_PLUGIN = "MetroidvaniaSystem"
## When true (default) the plugin has a "Map Dev" main screen tab next to
## 2D/3D/Script/MetSys; otherwise the panel starts in the right dock. Re-enable the plugin
## after changing it.
const SETTING_MAIN_SCREEN = "interactive_dev_panel/use_main_screen"
## Where the panel is: see [enum Placement]. Changed from the panel's window menu.
const SETTING_PLACEMENT = "interactive_dev_panel/placement"
const METADATA_SECTION = "interactive_dev_panel"

## Where the panel lives. The panel can be detached into its own window (e.g. on a second
## monitor) and docked back at any time.
enum Placement { MAIN_SCREEN, WINDOW, RIGHT_DOCK, BOTTOM_PANEL }
const PLACEMENT_NAMES: PackedStringArray = ["Main screen (Map Dev tab)", "Floating window", "Right dock", "Bottom panel"]

var dock_instance: Control
var placement: int = -1
var _in_main_screen := false ## the plugin has a main screen tab
var _main_visible := false ## the Map Dev tab is the current main screen
var _window: Window
var _placeholder: Control
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
	_main_visible = visible
	if not dock_instance:
		return
	if placement == Placement.MAIN_SCREEN:
		dock_instance.visible = visible
	if _placeholder:
		_placeholder.visible = visible and placement != Placement.MAIN_SCREEN

func _on_scene_saved(path: String) -> void:
	if dock_instance and dock_instance.has_method("on_scene_saved"):
		dock_instance.on_scene_saved(path)

func _init_plugin() -> void:
	if dock_instance:
		return
	_in_main_screen = _has_main_screen()
	dock_instance = preload("res://addons/MetroidvaniaDeveloperSystem/dock.tscn").instantiate()
	dock_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _in_main_screen:
		_placeholder = _build_placeholder()
		EditorInterface.get_editor_main_screen().add_child(_placeholder)
		_placeholder.hide()
	var saved := int(ProjectSettings.get_setting(SETTING_PLACEMENT, Placement.MAIN_SCREEN if _in_main_screen else Placement.RIGHT_DOCK))
	set_placement(saved, false)
	if dock_instance.has_signal(&"placement_requested"):
		dock_instance.placement_requested.connect(set_placement)
	_check_metsys()

## Moves the panel: into the main screen tab, a floating window, the right dock or the
## bottom panel. The choice is remembered for the project.
func set_placement(new_placement: int, focus := true) -> void:
	new_placement = clampi(new_placement, 0, Placement.size() - 1)
	if new_placement == Placement.MAIN_SCREEN and not _in_main_screen:
		new_placement = Placement.RIGHT_DOCK
	if new_placement == placement and dock_instance.get_parent():
		if placement == Placement.WINDOW and _window:
			_window.grab_focus()
		return
	_detach()
	placement = new_placement
	match placement:
		Placement.MAIN_SCREEN:
			dock_instance.custom_minimum_size = Vector2.ZERO
			EditorInterface.get_editor_main_screen().add_child(dock_instance)
			dock_instance.visible = _main_visible
			if focus and not _main_visible:
				EditorInterface.set_main_screen_editor(_get_plugin_name())
		Placement.WINDOW:
			_open_window()
		Placement.RIGHT_DOCK:
			dock_instance.custom_minimum_size = Vector2(420, 480)
			add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock_instance)
			dock_instance.show()
			_focus_dock_tab.call_deferred()
		Placement.BOTTOM_PANEL:
			dock_instance.custom_minimum_size = Vector2(0, 360)
			add_control_to_bottom_panel(dock_instance, _get_plugin_name())
			dock_instance.show()
			make_bottom_panel_item_visible(dock_instance)
	if _placeholder:
		_placeholder.visible = _main_visible and placement != Placement.MAIN_SCREEN
		_placeholder.get_node("Box/Text").text = "Map Dev is in the %s." % ["main screen", "floating window", "right dock", "bottom panel"][placement]
	if dock_instance.has_method("set_placement_state"):
		dock_instance.set_placement_state(placement, _in_main_screen)
	if int(ProjectSettings.get_setting(SETTING_PLACEMENT, -1)) != placement:
		ProjectSettings.set_setting(SETTING_PLACEMENT, placement)
		ProjectSettings.save()

## Takes the panel out of wherever it is.
func _detach() -> void:
	if not dock_instance.get_parent():
		return
	match placement:
		Placement.RIGHT_DOCK:
			remove_control_from_docks(dock_instance)
		Placement.BOTTOM_PANEL:
			remove_control_from_bottom_panel(dock_instance)
		Placement.WINDOW:
			_save_window_rect()
			_window.remove_child(dock_instance)
			_window.queue_free()
			_window = null
		_:
			dock_instance.get_parent().remove_child(dock_instance)
	# Godot 4.6 wraps docked controls in an EditorDock that it frees after removal: take
	# the panel out of it so it survives.
	if dock_instance.get_parent():
		dock_instance.get_parent().remove_child(dock_instance)

func _open_window() -> void:
	_window = Window.new()
	_window.title = "Map Dev - Interactive Dev Panel"
	_window.theme = EditorInterface.get_editor_theme()
	_window.min_size = Vector2i(640, 420)
	_window.wrap_controls = false
	_window.transient = false
	_window.exclusive = false
	_window.close_requested.connect(func() -> void:
		set_placement(Placement.MAIN_SCREEN if _in_main_screen else Placement.RIGHT_DOCK))
	var backdrop := Panel.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(backdrop)
	dock_instance.custom_minimum_size = Vector2.ZERO
	dock_instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(dock_instance)
	dock_instance.show()
	EditorInterface.get_base_control().add_child(_window)
	var rect: Rect2i = EditorInterface.get_editor_settings().get_project_metadata(METADATA_SECTION, "window_rect", Rect2i())
	if rect.size.x >= 320 and rect.size.y >= 240 and _rect_on_screen(rect):
		_window.position = rect.position
		_window.size = rect.size
		_window.show()
	else:
		var scale := EditorInterface.get_editor_scale()
		_window.popup_centered(Vector2i(Vector2(1280, 800) * scale))

func _rect_on_screen(rect: Rect2i) -> bool:
	for i in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)).intersects(rect):
			return true
	return false

func _save_window_rect() -> void:
	if _window and _window.visible:
		EditorInterface.get_editor_settings().set_project_metadata(METADATA_SECTION, "window_rect", Rect2i(_window.position, _window.size))

## Shown in the Map Dev tab while the panel is somewhere else.
func _build_placeholder() -> Control:
	var root := CenterContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.name = "Box"
	root.add_child(box)
	var text := Label.new()
	text.name = "Text"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	var back := Button.new()
	back.text = "Dock Map Dev back here"
	back.pressed.connect(func() -> void: set_placement(Placement.MAIN_SCREEN))
	box.add_child(back)
	var show_it := Button.new()
	show_it.text = "Show it"
	show_it.pressed.connect(_show_panel)
	box.add_child(show_it)
	return root

## Selects the panel's tab in the dock it was added to.
func _focus_dock_tab() -> void:
	var child: Node = dock_instance
	var parent := child.get_parent()
	while parent and not parent is TabContainer:
		child = parent
		parent = parent.get_parent()
	if parent is TabContainer:
		var tabs := parent as TabContainer
		tabs.current_tab = tabs.get_tab_idx_from_control(child)

## Brings the panel into view wherever it is.
func _show_panel() -> void:
	match placement:
		Placement.RIGHT_DOCK:
			_focus_dock_tab()
		Placement.WINDOW:
			if _window:
				_window.grab_focus()
		Placement.BOTTOM_PANEL:
			make_bottom_panel_item_visible(dock_instance)

## The panel works from MapData.txt alone, but room sizes, the default map path and theme
## colors come from MetSys, so keep reminding until it is enabled.
func _check_metsys() -> void:
	# Non-linear mode doesn't use MetSys.
	if preload("res://addons/MetroidvaniaDeveloperSystem/dock.gd").saved_mode() != 0:
		_clear_check_timer()
		return
	if EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN_NAME) or EditorInterface.is_plugin_enabled(MET_SYS_PLUGIN):
		_clear_check_timer()
		return
	EditorInterface.get_editor_toaster().push_toast("MetSys plugin should be installed and enabled in project settings for the Metroidvania Developer System MetSys mode to work.", EditorToaster.SEVERITY_WARNING)
	if not _metsys_check_timer:
		_metsys_check_timer = Timer.new()
		_metsys_check_timer.wait_time = 30.0
		_metsys_check_timer.timeout.connect(_check_metsys)
		_metsys_check_timer.autostart = true
		add_child(_metsys_check_timer)

func _clean_plugin() -> void:
	_clear_check_timer()
	if dock_instance:
		_detach()
		dock_instance.free()
		dock_instance = null
	if is_instance_valid(_window):
		_window.free()
	_window = null
	if is_instance_valid(_placeholder):
		_placeholder.get_parent().remove_child(_placeholder)
		_placeholder.free()
	_placeholder = null

func _clear_check_timer() -> void:
	if _metsys_check_timer:
		remove_child(_metsys_check_timer)
		_metsys_check_timer.queue_free()
		_metsys_check_timer = null
