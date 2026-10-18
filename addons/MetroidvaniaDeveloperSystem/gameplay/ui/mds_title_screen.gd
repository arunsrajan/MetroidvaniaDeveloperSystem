@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_title_screen.svg")
class_name MDSTitleScreen
extends MDSGameplayScreen
## The title and save slot selection screen: Continue or New game for 3 slots,
## via [method MDSWorldGame.has_save_game], [method MDSWorldGame.read_save_game],
## [method MDSWorldGame.load_game] and [method MDSWorldGame.new_game].

signal slot_selected(slot_index: int, is_new: bool)

## Number of save slots (default 3).
@export var slot_count := 3
## Title text displayed on the screen (empty: uses world name).
@export var title_text := ""

var _slots_container: VBoxContainer
var _title_label: Label
var _confirm_dialog: ConfirmationDialog

func _init() -> void:
	super._init()
	add_to_group(&"mds_title_screen")

func _ready() -> void:
	super._ready()
	_build_ui()

## Opens the title screen and presents save slots.
func show_title() -> void:
	open_screen()

func get_slot_path(slot_index: int) -> String:
	var game := MDSGameplayUi.game_for(self)
	var stem := "world"
	if game and game.world:
		stem = game.world.get_world_name().to_snake_case().validate_filename()
		if stem.is_empty():
			stem = "world"
	elif game and not game.save_file.is_empty():
		var base := game.save_file.get_file().get_basename()
		for i in range(1, 10):
			base = base.trim_suffix("_slot%d" % i)
		base = base.trim_suffix("_save")
		stem = base
	return "user://%s_slot%d.json" % [stem, slot_index]

## Reads the save data of [param slot_index] ({} if none or invalid), through the game's
## [method MDSWorldGame.read_save_game] with the slot's file.
func read_slot(slot_index: int) -> Dictionary:
	return _ask_slot(slot_index, func(g: MDSWorldGame) -> Variant: return g.read_save_game(), {})

## Whether [param slot_index] has existing save data ([method MDSWorldGame.has_save_game]).
func has_slot_save(slot_index: int) -> bool:
	return _ask_slot(slot_index, func(g: MDSWorldGame) -> Variant: return g.has_save_game(), false)

## [param ask] called with the game while its [member MDSWorldGame.save_file] is the slot's;
## the game's own file is put back after. [param otherwise] without a game.
func _ask_slot(slot_index: int, ask: Callable, otherwise: Variant) -> Variant:
	var game := MDSGameplayUi.game_for(self)
	if not game:
		return otherwise
	var own := game.save_file
	game.save_file = get_slot_path(slot_index)
	var answer: Variant = ask.call(game)
	game.save_file = own
	return answer

## Loads and continues from [param slot_index].
func select_slot_continue(slot_index: int) -> void:
	var game := MDSGameplayUi.game_for(self)
	if not game:
		return
	var path := get_slot_path(slot_index)
	game.save_file = path
	var stem := path.get_file().get_basename()
	game.exploration_file = "user://%s_exploration.json" % stem
	close()
	slot_selected.emit(slot_index, false)
	game.load_game()

## Starts a new game on [param slot_index].
func select_slot_new(slot_index: int) -> void:
	var game := MDSGameplayUi.game_for(self)
	if not game:
		return
	var path := get_slot_path(slot_index)
	game.save_file = path
	var stem := path.get_file().get_basename()
	game.exploration_file = "user://%s_exploration.json" % stem
	close()
	slot_selected.emit(slot_index, true)
	game.new_game()

## Deletes [param slot_index]'s save file ([method MDSWorldGame.delete_save_game]) and its
## explored map.
func delete_slot(slot_index: int) -> void:
	var path := get_slot_path(slot_index)
	_ask_slot(slot_index, func(g: MDSWorldGame) -> Variant:
		g.delete_save_game()
		return null, null)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var stem := path.get_file().get_basename()
	var exp_path := "user://%s_exploration.json" % stem
	if FileAccess.file_exists(exp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(exp_path))
	_refresh_slots()

func _on_open() -> void:
	_refresh_slots()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 400)
	box.add_theme_constant_override(&"separation", 16)
	center.add_child(box)

	var game := MDSGameplayUi.game_for(self)
	var title := title_text
	if title.is_empty():
		title = game.world.get_world_name() if game and game.world and not game.world.get_world_name().is_empty() else "Metroidvania"
	_title_label = MDSGameplayUi.label(box, title, 32, MDSGameplayUi.GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_slots_container = VBoxContainer.new()
	_slots_container.add_theme_constant_override(&"separation", 10)
	box.add_child(_slots_container)

	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override(&"separation", 16)
	box.add_child(bottom_row)

	var opt_btn := MDSGameplayUi.button(bottom_row, "Options", func() -> void:
		var opts := get_tree().get_first_node_in_group(&"mds_options_menu") as MDSOptionsMenu
		if opts:
			opts.open_screen())
	opt_btn.custom_minimum_size = Vector2(140, 36)

	var quit_btn := MDSGameplayUi.button(bottom_row, "Quit", func() -> void:
		get_tree().quit())
	quit_btn.custom_minimum_size = Vector2(140, 36)

func _refresh_slots() -> void:
	if not _slots_container:
		return
	MDSGameplayUi.clear(_slots_container)

	for i in range(1, slot_count + 1):
		var card := PanelContainer.new()
		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override(&"separation", 4)
		card.add_child(card_box)
		_slots_container.add_child(card)

		var data := read_slot(i)
		var has_data := not data.is_empty()

		var header_row := HBoxContainer.new()
		card_box.add_child(header_row)

		MDSGameplayUi.label(header_row, "Slot %d" % i, 20, MDSGameplayUi.GOLD)

		if has_data:
			var room_name: String = str(data.get("room", "Unknown"))
			var ext: Dictionary = data.get("ext", {}).get("gameplay", {}) if data.get("ext") is Dictionary else {}
			var hp: int = int(ext.get("health", 5))
			var max_hp: int = int(ext.get("max_health", 5))
			var time_sec: float = float(ext.get("play_time", 0.0))
			var time_str := MDSGameplayUi.format_time(time_sec)

			var info_label := MDSGameplayUi.label(card_box, "%s  ·  HP %d/%d  ·  Time %s" % [room_name, hp, max_hp, time_str], 15, MDSGameplayUi.TEXT)
			info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override(&"separation", 8)
			card_box.add_child(btn_row)

			var cont_btn := MDSGameplayUi.button(btn_row, "Continue", func() -> void:
				select_slot_continue(i))
			cont_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var del_btn := MDSGameplayUi.button(btn_row, "Delete", func() -> void:
				delete_slot(i))
			del_btn.add_theme_color_override(&"font_color", Color(0.9, 0.4, 0.4))
		else:
			MDSGameplayUi.label(card_box, "Empty Slot", 15, MDSGameplayUi.DIM)
			var new_btn := MDSGameplayUi.button(card_box, "Start New Game", func() -> void:
				select_slot_new(i))
			new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
