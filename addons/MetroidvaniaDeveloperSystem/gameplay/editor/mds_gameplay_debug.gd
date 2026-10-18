@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_gameplay_debug.svg")
class_name MDSGameplayDebug
extends Node
## Runtime debug hotkeys (debug builds only, when project setting debug_keys is true):
## F1: overlay (state names, hitboxes, velocity)
## F2: grant all abilities in the world file
## F3: invulnerability toggle
## F4: noclip toggle
## F6: print get_save_data()
## F7: 25% speed toggle

var enabled := true
var show_overlay := false
var noclip := false
var _saved_mask := 0
var _saved_layer := 0
var _overlay_canvas: CanvasLayer
var _overlay_label: Label
var _overlay_draw: Control

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process_unhandled_key_input(false)
		set_process(false)
		return
	enabled = OS.is_debug_build() and bool(MDSGameplaySetup.setting("debug_keys", true))
	if not enabled:
		set_process_unhandled_key_input(false)
		set_process(false)
		return
	_build_overlay()

func _build_overlay() -> void:
	_overlay_canvas = CanvasLayer.new()
	_overlay_canvas.layer = 120
	_overlay_canvas.visible = false
	add_child(_overlay_canvas)

	_overlay_draw = Control.new()
	_overlay_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_draw.draw.connect(_on_overlay_draw)
	_overlay_canvas.add_child(_overlay_draw)

	_overlay_label = Label.new()
	_overlay_label.position = Vector2(16, 16)
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_canvas.add_child(_overlay_label)

func _unhandled_key_input(event: InputEvent) -> void:
	if not enabled or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_F1:
			_toggle_overlay()
		KEY_F2:
			_grant_all_abilities()
		KEY_F3:
			_toggle_invulnerable()
		KEY_F4:
			_toggle_noclip()
		KEY_F6:
			_print_save_data()
		KEY_F7:
			_toggle_speed()

func _process(delta: float) -> void:
	if not enabled:
		return
	var p := _get_player()
	if noclip and p:
		var dir := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
			dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
			dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
			dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
			dir.y += 1.0
		p.global_position += dir.normalized() * (700.0 * delta)
		p.velocity = Vector2.ZERO

	if show_overlay and _overlay_canvas and _overlay_canvas.visible:
		_update_overlay_info()
		if _overlay_draw:
			_overlay_draw.queue_redraw()

func _toggle_overlay() -> void:
	show_overlay = not show_overlay
	if _overlay_canvas:
		_overlay_canvas.visible = show_overlay

func _update_overlay_info() -> void:
	_overlay_label.text = "\n".join(overlay_lines())

## The overlay's text: the player's state, velocity, position and health, the kit's mana,
## currency and equipment, and the room.
func overlay_lines() -> Array[String]:
	var p := _get_player()
	var game := MDSWorldGame.instance
	var gp := MDSGameplay.find(game) if game else null
	var lines: Array[String] = ["[DEBUG OVERLAY] (F1 toggle)"]
	if p:
		var st_name := String(p.machine.get_state()) if p.machine and p.machine.current else "None"
		lines.append("State: %s" % st_name)
		lines.append("Vel: (%d, %d)" % [roundi(p.velocity.x), roundi(p.velocity.y)])
		lines.append("Pos: (%d, %d)" % [roundi(p.global_position.x), roundi(p.global_position.y)])
		if p.health:
			lines.append("HP: %d/%d (Invulnerable: %s)" % [p.health.current, p.health.get_max(), str(p.health.invulnerable)])
		lines.append("Noclip: %s" % str(noclip))
	if gp:
		lines.append("Mana: %d/%d | Currency: %d" % [gp.mana, gp.player_max_mana(), gp.currency])
		lines.append("Equipped: %s" % ", ".join(gp.equipped))
	if game:
		lines.append("Room: %s" % game.current_room)
	return lines

## Outlines every hitbox (red while active) and hurtbox (green) on screen.
func _on_overlay_draw() -> void:
	if not show_overlay or not is_inside_tree():
		return
	var canvas_xform := get_viewport().get_canvas_transform()
	for n in get_tree().get_nodes_in_group(MDSHitbox.GROUP):
		var hb := n as MDSHitbox
		if hb and hb.is_visible_in_tree():
			_draw_area(hb, canvas_xform, Color(1.0, 0.2, 0.2, 0.9) if hb.active and hb.monitoring else Color(1.0, 0.2, 0.2, 0.25))
	for n in get_tree().get_nodes_in_group(MDSHurtbox.GROUP):
		var hu := n as MDSHurtbox
		if hu and hu.is_visible_in_tree():
			_draw_area(hu, canvas_xform, Color(0.2, 1.0, 0.2, 0.8 if hu.enabled else 0.25))

func _draw_area(area: Area2D, canvas_xform: Transform2D, color: Color) -> void:
	for c in area.get_children():
		var cs := c as CollisionShape2D
		if not cs or not cs.shape or cs.disabled:
			continue
		var r := cs.shape.get_rect()
		var xf := canvas_xform * cs.global_transform
		var pts := PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y), xf * r.position])
		_overlay_draw.draw_polyline(pts, color, 2.0)

## The abilities the world file names (room grants and gate requirements; not items, flags,
## bosses or objects).
static func world_abilities(game: MDSWorldGame) -> PackedStringArray:
	var out: PackedStringArray = []
	if not game or not game.world:
		return out
	for r in game.world.get_known_abilities():
		var c := MDSAnnotations.parse_condition(r)
		var id := MDSGameplay.normalize_id(str(c[1]))
		if c[0] == "ability" and not id.is_empty() and not id in out:
			out.append(id)
	return out

func _grant_all_abilities() -> void:
	var game := MDSWorldGame.instance
	if not game:
		return
	var all := world_abilities(game)
	for a in all:
		game.grant_ability(a)
	print("[DEBUG] F2: Granted %d abilities: %s" % [all.size(), ", ".join(all)])

func _toggle_invulnerable() -> void:
	var p := _get_player()
	if p and p.health:
		p.health.invulnerable = not p.health.invulnerable
		print("[DEBUG] F3: Invulnerable = %s" % str(p.health.invulnerable))

func _toggle_noclip() -> void:
	var p := _get_player()
	if not p:
		return
	noclip = not noclip
	if noclip:
		_saved_layer = p.collision_layer
		_saved_mask = p.collision_mask
		p.collision_layer = 0
		p.collision_mask = 0
		print("[DEBUG] F4: Noclip ON")
	else:
		p.collision_layer = _saved_layer
		p.collision_mask = _saved_mask
		print("[DEBUG] F4: Noclip OFF")

func _print_save_data() -> void:
	var game := MDSWorldGame.instance
	if game:
		print("--- MDS SAVE DATA (F6) ---")
		print(JSON.stringify(game.get_save_data(), "  "))

func _toggle_speed() -> void:
	if is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 0.25
		print("[DEBUG] F7: 25% game speed")
	else:
		Engine.time_scale = 1.0
		print("[DEBUG] F7: 100% game speed")

func _get_player() -> MDSPlayer:
	var game := MDSWorldGame.instance
	if game and game.player is MDSPlayer:
		return game.player as MDSPlayer
	var nodes := get_tree().get_nodes_in_group(&"player")
	for n in nodes:
		if n is MDSPlayer:
			return n as MDSPlayer
	return null
