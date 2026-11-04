extends "res://tests/test_case.gd"
## Gameplay Kit: a fight with moves in the real game, with the real player. A pair of bosses in
## Crypt_01: killing the first brings the second and the fight goes on; dying then resets all of it;
## killing both wins, records the boss by name once, opens the doors, and it is gone for good.

const Fixture := preload("res://tests/game_fixture.gd")

var game: MDSWorldGame
var kit: MDSGameplay
var player: MDSPlayer
var started: Array = []
var ended: Array = []

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	Fixture.build()
	_add_arena()
	game = Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	kit.death_delay = 0.1
	game.add_child(kit)
	game.remove_child(game.player)
	game.player.free()
	player = load(MDSPlayer.SCENE).instantiate()
	game.add_child(player)
	game.player = player
	kit.boss_started.connect(func(b: String) -> void: started.append(b))
	kit.boss_ended.connect(func(b: String, won: bool) -> void: ended.append([b, won]))
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	await _lost_fight()
	await _won_fight()
	game.queue_free()
	await get_tree().process_frame

func _add_arena() -> void:
	var path := Fixture.DIR + "/crypt_01.tscn"
	var root: Node = (load(path) as PackedScene).instantiate()
	var boss := MDSMoveBoss.new()
	boss.name = "Warden"
	boss.boss_name = "Warden"
	boss.recipe = "twin_swooper"
	boss.position = Vector2(760, 400)
	root.add_child(boss)
	var door := MDSArenaDoor.new()
	door.name = "Door"
	door.position = Vector2(1000, 486)
	root.add_child(door)
	var arena := MDSBossArena.new()
	arena.name = "Arena"
	arena.position = Vector2(600, 400)
	arena.size = Vector2(700, 400)
	root.add_child(arena)
	arena.boss = boss
	arena.doors = [door] as Array[MDSArenaDoor]
	check(save_scene(root, path) == OK, "Crypt_01 saved with the fight")
	root.free()
	load_fresh(path)

func _boss() -> MDSMoveBoss:
	var b := game.room_node.get_node_or_null("Warden") as MDSMoveBoss
	return b if b and not b.is_queued_for_deletion() else null

func _arena() -> MDSBossArena:
	return game.room_node.get_node_or_null("Arena") as MDSBossArena

func _door() -> MDSArenaDoor:
	return game.room_node.get_node_or_null("Door") as MDSArenaDoor

func _enter_crypt() -> void:
	game.load_room("Crypt_01", "left1")
	await game.room_loaded
	player.health.invulnerable = true
	await physics_frames(5)
	player.global_position = game.world.get_origin("Crypt_01") + Vector2(500, 540)
	await physics_frames(5)

func _kill(e: MDSEnemy) -> void:
	var hit := MDSDamageInfo.make(9999)
	hit.ignores_iframes = true
	e.health.apply_damage(hit)

func _lost_fight() -> void:
	await _enter_crypt()
	var boss := _boss()
	check(boss != null and boss.fighting and _arena().fighting, "walking in starts the fight")
	check(started == ["Warden"], "the kit reports it")
	await physics_frames(120)
	check(boss.fight._current != null, "it runs its moves in the real game")
	_kill(boss)
	await physics_frames(3)
	check(boss.partners.size() == 1, "the second comes when the first falls")
	var second := boss.partners[0] as MDSMoveBoss
	check(second.fighting, "and fights")
	check(_arena().fighting and _door().is_closed, "the fight goes on, the doors shut")
	check(kit.boss_node == second, "the kit follows the survivor")
	check(not game.is_boss_defeated("Warden"), "not defeated yet")
	check(ended.is_empty(), "not ended yet")
	# The player falls.
	player.health.invulnerable = false
	var kill := MDSDamageInfo.make(99)
	kill.ignores_iframes = true
	player.health.apply_damage(kill)
	await physics_frames(2)
	check(ended == [["Warden", false]], "dying ends the fight lost (%s)" % [ended])
	await game.room_loaded
	await physics_frames(30)
	check(not game.is_boss_defeated("Warden"), "and it isn't recorded as beaten")

func _won_fight() -> void:
	started.clear()
	ended.clear()
	await _enter_crypt()
	var boss := _boss()
	check(boss != null and boss.health.current == boss.health.get_max(), "back in the crypt the first is back, whole")
	check(boss != null and boss.partners.is_empty(), "alone")
	if not boss:
		return
	check(started == ["Warden"], "and the fight starts again")
	_kill(boss)
	await physics_frames(3)
	check(boss.partners.size() == 1, "the second comes again")
	if boss.partners.is_empty():
		return
	var second := boss.partners[0] as MDSMoveBoss
	await physics_frames(100)
	check(not is_instance_valid(boss) or boss.dying, "the first stays down")
	check(_arena().fighting, "the fight still goes on")
	_kill(second)
	await physics_frames(3)
	check(game.is_boss_defeated("Warden"), "both beaten, it is recorded by name")
	check(ended == [["Warden", true]], "the fight ends won, even with the first long gone (%s)" % [ended])
	check(not _door().is_closed, "the doors open")
	await physics_frames(90)
	game.load_room("Garden_02", "right1")
	await game.room_loaded
	await physics_frames(3)
	await _enter_crypt()
	check(_boss() == null, "it is gone when the room loads again")
	check(not _arena().fighting, "and the arena stays quiet")
