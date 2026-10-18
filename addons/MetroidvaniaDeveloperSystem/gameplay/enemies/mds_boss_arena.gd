@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/icons/gameplay/mds_boss_arena.svg")
class_name MDSBossArena
extends Area2D
## Where a boss fight happens: when the player walks into it ([member size], centred on the node),
## its [member doors] close, the boss music starts ([method MDSMusic.play_boss]: [member music],
## else the boss's, else the area's [code]boss_music[/code]), the camera director frames the boss
## ([method MDSCameraDirector.frame_threat], or shows [member frame_area]), the HUD shows the boss's
## health ([signal MDSGameplay.boss_started]) and the boss starts ([method MDSBoss.start_fight]).
##
## When the boss falls it is recorded by name ([method MDSWorldGame.mark_defeated]), the music
## goes back to the area's ([method MDSMusic.end_boss]), the director lets go, the doors open,
## [member grants] (an ability) is granted, and [signal MDSGameplay.boss_ended] reports the win. If
## the player dies the arena resets when the room loads again, the boss at its first phase. A
## boss already defeated leaves the arena idle and its doors open.
##
## Doors that should stay shut until the boss is beaten are [MDSGateBarrier]s with
## [code]requires = ["boss:<name>"][/code].

signal fight_started(boss: MDSBoss)
signal fight_won(boss: MDSBoss)

@export var boss: MDSBoss
@export var doors: Array[MDSArenaDoor] = []
## What the camera shows when the fight starts (world px). Empty: the boss (and the player).
@export var frame_area := Rect2()
@export var size := Vector2(900, 480):
	set(v):
		size = v.max(Vector2(16, 16))
		queue_redraw()
## An ability granted for winning (empty: none).
@export var grants := ""
@export var music: AudioStream

var fighting := false
var won := false

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	collision_layer = 0
	collision_mask = MDSGameplaySetup.player_detect_mask()
	if get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).is_empty():
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = size
		cs.shape = r
		add_child(cs)
	body_entered.connect(func(b: Node) -> void:
		if b.is_in_group(&"player"):
			start())
	var game := MDSWorldGame.instance
	if not is_instance_valid(boss) or boss.is_queued_for_deletion() or (game and boss and not boss.boss_name.is_empty() and game.is_boss_defeated(boss.boss_name)):
		won = true
	var kit := MDSGameplay.find(game) if game else null
	if kit:
		kit.boss_ended.connect(_on_boss_ended)

## Starts the fight (the player walked in).
func start() -> void:
	if fighting or won or not is_instance_valid(boss) or boss.dying:
		return
	fighting = true
	for d in doors:
		if is_instance_valid(d):
			d.close()
	var game := MDSWorldGame.instance
	var m := _music(game)
	if m:
		m.play_boss(music if music else boss.music)
	var dir := _director(game)
	if dir:
		if frame_area.has_area():
			dir.reveal(frame_area)
		else:
			dir.frame_threat(boss)
	var kit := MDSGameplay.find(game) if game else null
	if kit:
		kit.current_boss = boss.boss_name
		kit.boss_node = boss
		kit.boss_started.emit(boss.boss_name)
	if not boss.died.is_connected(_on_boss_died):
		boss.died.connect(_on_boss_died)
	boss.start_fight()
	fight_started.emit(boss)

func _on_boss_died() -> void:
	if not fighting:
		return
	fighting = false
	won = true
	var game := MDSWorldGame.instance
	var m := _music(game)
	if m:
		m.end_boss()
	var dir := _director(game)
	if dir and dir.is_overriding():
		dir.release()
	for d in doors:
		if is_instance_valid(d):
			d.open()
	if game and not grants.is_empty():
		game.grant_ability(MDSGameplay.normalize_id(grants))
	var kit := MDSGameplay.find(game) if game else null
	if kit:
		var n := boss.boss_name if is_instance_valid(boss) else ""
		kit.current_boss = ""
		kit.boss_node = null
		kit.boss_ended.emit(n, true)
	fight_won.emit(boss)

## The player fell in the fight: the arena lets go (the room loads anew after).
func _on_boss_ended(_boss: String, was_won: bool) -> void:
	if was_won or not fighting:
		return
	fighting = false
	var m := _music(MDSWorldGame.instance)
	if m:
		m.end_boss()

static func _music(game: MDSWorldGame) -> MDSMusic:
	if not game:
		return null
	for c in game.get_children():
		if c is MDSMusic:
			return c
	return null

static func _director(game: MDSWorldGame) -> MDSCameraDirector:
	return game.room_camera.get_director() if game and game.room_camera else null

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := Rect2(-size * 0.5, size)
	draw_rect(r, Color(0.9, 0.3, 0.3, 0.07))
	draw_rect(r, Color(0.9, 0.3, 0.3, 0.8), false, 2.0)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(8, 18), "Boss arena" + (": " + boss.boss_name if is_instance_valid(boss) and not boss.boss_name.is_empty() else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.6, 0.6))
