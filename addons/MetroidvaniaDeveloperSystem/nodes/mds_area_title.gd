@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSAreaTitle
extends Control
## An area's name, faded in near the top of the screen when the player enters the area (the
## way Hollow Knight and Silksong title their areas), held, and faded out. Put it in the UI
## (a CanvasLayer) of an [MDSWorldGame] scene.
##
## The text is the area's [code]title[/code] in the world file (else its name) and its
## [code]subtitle[/code] under it.

## Emitted as a title starts showing.
signal shown(area: String)

## The game whose areas are titled. Empty: [member MDSWorldGame.instance].
@export var game: MDSWorldGame
## Only the first time each area is entered.
@export var first_visit_only := false
@export var fade_time := 0.8
@export var hold_time := 2.5
@export var title_size := 44
@export var subtitle_size := 18
@export var title_color := Color(0.95, 0.92, 0.84)
## Where the title sits, as a share of the screen's height from its top.
@export_range(0.0, 1.0) var height := 0.14

## The area last titled (for your own UI or tests).
var shown_area := ""
var _title: Label
var _subtitle: Label
var _tween: Tween

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.anchor_top = height
	box.anchor_bottom = height
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _label(title_size, title_color)
	box.add_child(_title)
	_subtitle = _label(subtitle_size, title_color.darkened(0.2))
	box.add_child(_subtitle)
	_connect.call_deferred()

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", maxi(4, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _connect() -> void:
	if not game:
		game = MDSWorldGame.instance
	if game and not game.area_changed.is_connected(_on_area_changed):
		game.area_changed.connect(_on_area_changed)

func _on_area_changed(_from: String, area: String) -> void:
	if area.is_empty():
		return
	if first_visit_only and int(game.area_visits.get(area, 0)) > 1:
		return
	show_title(area)

## Shows [param area]'s title now.
func show_title(area: String) -> void:
	var data: Dictionary = game.world.get_areas().get(area, {}) if game and game.world else {}
	var title := str(data.get("title", ""))
	_title.text = (title if not title.is_empty() else area).to_upper()
	_subtitle.text = str(data.get("subtitle", ""))
	_subtitle.visible = not _subtitle.text.is_empty()
	shown_area = area
	shown.emit(area)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_time).from(0.0)
	_tween.tween_interval(hold_time)
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
