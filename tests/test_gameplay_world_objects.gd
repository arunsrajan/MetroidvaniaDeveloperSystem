extends "res://tests/test_case.gd"
## Gameplay Kit, phase 3: an ability pickup, a breakable wall and a switch in a room scene. Collected,
## broken and switched, they stay so when the room loads again and after a save and load; the switch's
## flag opens a barrier; an MDSWater with swimmable gets a swim zone. They write the metadata the
## analysis reads.

const Fixture := preload("res://tests/game_fixture.gd")

var game: MDSWorldGame
var kit: MDSGameplay

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	_add_objects()
	game = _game()
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	var pickup := game.room_node.get_node_or_null("Pickup") as MDSAbilityPickup
	var wall := game.room_node.get_node_or_null("Wall") as MDSBreakable
	var lever := game.room_node.get_node_or_null("Lever") as MDSSwitch
	var gate := game.room_node.get_node_or_null("LeverBarrier") as MDSGateBarrier
	check(pickup and wall and lever and gate, "the room has the pickup, the wall, the switch and its barrier")
	check(pickup.get_meta(&"mds_grants") == PackedStringArray(["dash"]) and lever.get_meta(&"mds_grants") == PackedStringArray(["flag:lever"]) and wall.get_meta(&"mds_requires") == PackedStringArray(["double_jump"]), "they carry mds_grants / mds_requires")
	# The pickup: the player touches it.
	game.player.global_position = pickup.global_position
	await physics_frames(4)
	check(game.has_ability("dash") and not is_instance_valid(pickup), "touching the pickup grants dash, and it is gone")
	# The wall: needs double_jump, then breaks with an attack that breaks walls.
	var hit := MDSDamageInfo.make(1)
	hit.breaks = PackedStringArray(["wall"])
	var hb := wall.get_node("Hurtbox") as MDSHurtbox
	check(hb.receive(hit) == 0 and is_instance_valid(wall) and not wall.is_queued_for_deletion(), "the wall holds while its requirement is unmet")
	game.grant_ability("double_jump")
	var floor_hit := MDSDamageInfo.make(1)
	floor_hit.breaks = PackedStringArray(["cracked_floor"])
	check(hb.receive(floor_hit) == 0, "an attack that doesn't break walls does nothing")
	hb.receive(hit)
	check(wall.hits_left == 1 and not wall.is_queued_for_deletion(), "two hits: one done")
	hb.receive(hit)
	check(wall.is_queued_for_deletion(), "it breaks on the second")
	# The switch: struck, it sets its flag and the barrier opens.
	check(not gate.is_open, "the barrier waits for the lever")
	(lever.get_node("Hurtbox") as MDSHurtbox).receive(hit)
	check(kit.get_flag("lever") == true and lever.is_on, "striking the switch sets flag:lever")
	check(gate.is_open, "and the barrier opens")
	await physics_frames(2)
	# Out of the room and back.
	game.load_room("Garden_02", "left1")
	await game.room_loaded
	game.load_room("Garden_01", "right1")
	await game.room_loaded
	await physics_frames(3)
	_check_gone("after leaving the room and coming back")
	# Saved and loaded in a new game.
	var save := game.get_save_data()
	game.queue_free()
	await get_tree().process_frame
	game = _game()
	add_child(game)
	await game.room_loaded
	game.set_save_data(save)
	await game.room_loaded
	await physics_frames(3)
	_check_gone("after a save and a load")
	# Swimmable water.
	var water := MDSWater.new()
	water.swimmable = true
	game.room_node.add_child(water)
	check(water.get_node_or_null(^"SwimZone") is MDSSwimZone, "an MDSWater with swimmable gets a swim zone")
	game.queue_free()
	await get_tree().process_frame

func _check_gone(when: String) -> void:
	var room := game.room_node
	check(room.get_node_or_null("Pickup") == null or room.get_node("Pickup").is_queued_for_deletion(), "the pickup stays collected %s" % when)
	check(room.get_node_or_null("Wall") == null or room.get_node("Wall").is_queued_for_deletion(), "the wall stays broken %s" % when)
	var lever := room.get_node_or_null("Lever") as MDSSwitch
	check(lever != null and lever.is_on, "the switch stays on %s" % when)
	var gate := room.get_node_or_null("LeverBarrier") as MDSGateBarrier
	check(gate != null and gate.is_open, "its barrier stays open %s" % when)
	check(game.has_ability("dash"), "dash is kept %s" % when)

func _game() -> MDSWorldGame:
	var g := Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	g.add_child(kit)
	# The kit's player (on its own layer) instead of the fixture's plain body.
	g.remove_child(g.player)
	g.player.free()
	var p: MDSPlayer = load(MDSPlayer.SCENE).instantiate()
	g.add_child(p)
	g.player = p
	return g

## Garden_01 gets a dash pickup, a two-hit wall that needs double_jump, a lever and a barrier
## needing its flag.
func _add_objects() -> void:
	var path := Fixture.DIR + "/garden_01.tscn"
	var root: Node = (load(path) as PackedScene).instantiate()
	var pickup := MDSAbilityPickup.new()
	pickup.name = "Pickup"
	pickup.ability = load("res://addons/MetroidvaniaDeveloperSystem/gameplay/data/dash.tres")
	pickup.position = Vector2(500, 540)
	root.add_child(pickup)
	var wall := MDSBreakable.new()
	wall.name = "Wall"
	wall.hits = 2
	wall.requires = PackedStringArray(["double_jump"])
	wall.position = Vector2(820, 500)
	root.add_child(wall)
	var lever := MDSSwitch.new()
	lever.name = "Lever"
	lever.flag = "lever"
	lever.position = Vector2(200, 540)
	root.add_child(lever)
	var gate := MDSGateBarrier.new()
	gate.name = "LeverBarrier"
	gate.requires = PackedStringArray(["flag:lever"])
	gate.open_time = 0.01
	gate.position = Vector2(1000, 480)
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(32, 160)
	cs.shape = r
	gate.add_child(cs)
	root.add_child(gate)
	check(save_scene(root, path) == OK, "Garden_01 saved with its objects")
	root.free()
	load_fresh(path)
