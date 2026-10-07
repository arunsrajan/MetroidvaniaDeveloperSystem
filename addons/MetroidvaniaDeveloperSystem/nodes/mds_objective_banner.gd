@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSObjectiveBanner
extends Control
## A banner with the area's objective ([code]areas[name].objective[/code] in the world
## file), shown when the player arrives in an area whose objective isn't done, and again,
## marked done, when it is completed ([signal MDSWorldGame.objective_completed]). Put it in
## the UI (a CanvasLayer) of an [MDSWorldGame] scene.

## The game whose objectives are shown. Empty: [member MDSWorldGame.instance].
@export var game: MDSWorldGame
## Show it every time an area is entered, done or not (off: only while it isn't done).
@export var every_visit := false
@export var heading := "Objective"
@export var done_heading := "Objective complete"
@export var fade_time := 0.5
@export var hold_time := 4.0
@export var text_color := Color(0.95, 0.9, 0.75)
@export var done_color := Color(0.65, 1.0, 0.6)

## What the banner shows (or last showed).
var shown_text := ""
var shown_done := false
var _head: Label
var _body: Label
var _tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.03, 0.72)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_top = 0.82
	panel.anchor_bottom = 0.82
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_head = Label.new()
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.add_theme_font_size_override("font_size", 14)
	box.add_child(_head)
	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_theme_font_size_override("font_size", 20)
	box.add_child(_body)
	_connect.call_deferred()

func _connect() -> void:
	if not game:
		game = MDSWorldGame.instance
	if game and not game.area_changed.is_connected(_on_area_changed):
		game.area_changed.connect(_on_area_changed)
		game.objective_completed.connect(_on_completed)

func _on_area_changed(_from: String, area: String) -> void:
	var text := game.get_objective(area)
	if text.is_empty():
		return
	var done := game.is_objective_complete(area)
	if every_visit or not done:
		show_objective(text, done)

func _on_completed(area: String) -> void:
	if area == game.current_area or every_visit:
		show_objective(game.get_objective(area), true)

## Shows [param text] (marked done with [param done]) now.
func show_objective(text: String, done := false) -> void:
	shown_text = text
	shown_done = done
	_head.text = (done_heading if done else heading).to_upper()
	_head.add_theme_color_override("font_color", done_color if done else text_color.darkened(0.25))
	_body.text = ("✓ " if done else "") + text
	_body.add_theme_color_override("font_color", done_color if done else text_color)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_time)
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
