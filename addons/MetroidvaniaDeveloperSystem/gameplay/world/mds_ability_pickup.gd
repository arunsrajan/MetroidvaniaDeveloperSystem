@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_ability_pickup.svg")
class_name MDSAbilityPickup
extends Area2D
## An ability to pick up (the dash, the double jump...): touching it (or pressing interact at it,
## without [member auto_collect]) grants [member ability] ([method MDSWorldGame.grant_ability]) and
## it is gone for good ([method MDSWorldGame.store_object]: not there when its room loads again, nor
## after a save and load). [MDSGameplay] then shows the [MDSAbilityPopup], if the game has one.
##
## It writes [code]mds_grants = [ability id][/code] metadata (in the editor too), so the Progress
## and Issues tabs know where the ability is found, and it is in the [code]pickup[/code] group.

signal collected(ability: String)

@export var ability: MDSAbilityData:
	set(v):
		ability = v
		_update_meta()
		queue_redraw()
## Touching it collects it; off: interact at it.
@export var auto_collect := true
@export var radius := 22.0:
	set(v):
		radius = v
		queue_redraw()
@export var glow_color := Color(1.0, 0.85, 0.45)

var _time := 0.0
var _inside := false

func _init() -> void:
	add_to_group(&"pickup")

func _ready() -> void:
	_update_meta()
	if Engine.is_editor_hint():
		return
	collision_layer = MDSGameplaySetup.bit("interact")
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = radius
		cs.shape = c
		add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(b: Node) -> void:
		if b.is_in_group(&"player"):
			_inside = false)
	var game := MDSWorldGame.instance
	if game and game.is_object_stored(self):
		queue_free()

## The id it grants ("" without an ability).
func get_ability_id() -> String:
	return MDSGameplay.normalize_id(ability.id) if ability else ""

func _update_meta() -> void:
	var id := get_ability_id()
	if id.is_empty():
		if has_meta(&"mds_grants"):
			remove_meta(&"mds_grants")
	else:
		set_meta(&"mds_grants", PackedStringArray([id]))

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return
	_inside = true
	if auto_collect:
		collect()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or auto_collect or not _inside:
		return
	if InputMap.has_action(&"interact") and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		collect()

## Grants the ability and is gone for good.
func collect() -> void:
	var id := get_ability_id()
	var game := MDSWorldGame.instance
	if id.is_empty() or is_queued_for_deletion():
		return
	if game:
		var kit := MDSGameplay.find(game)
		if kit and ability:
			kit.register_ability(ability)
		game.store_object(self)
		game.grant_ability(id)
	collected.emit(id)
	queue_free()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var bob := sin(_time * 2.4) * 4.0
	var c := Vector2(0, bob)
	draw_circle(c, radius * 1.9, Color(glow_color, 0.12 + 0.05 * sin(_time * 3.0)))
	draw_circle(c, radius * 1.2, Color(glow_color, 0.25))
	if ability and ability.icon:
		var s := Vector2(radius, radius) * 1.6
		draw_texture_rect(ability.icon, Rect2(c - s * 0.5, s), false)
	else:
		draw_circle(c, radius * 0.7, glow_color)
		draw_circle(c, radius * 0.35, Color(1, 1, 1, 0.9))
	if Engine.is_editor_hint() and not ability:
		draw_string(ThemeDB.fallback_font, Vector2(-radius * 2.0, -radius - 8), "no ability", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.4, 0.4))
