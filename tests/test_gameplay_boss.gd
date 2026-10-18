extends "res://tests/test_case.gd"
## Gameplay Kit, phase 5: a boss fight. The Warden in Crypt_01: walking into the arena shuts its
## doors, starts the boss music (MDSMusic.play_boss), frames the boss and reports the fight; phase 2
## starts at half health; defeated, it is recorded by name (is_boss_defeated, the boss:Warden
## objective completes), the music and the doors go back, the arena's ability is granted, and the
## boss is gone when the room loads again. Dying in the fight resets it: the boss is back at phase 1.

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
	game = _game()
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	await _lost_fight()
	await _won_fight()
	game.queue_free()
	await get_tree().process_frame

func _game() -> MDSWorldGame:
	var g := Fixture.make_game()
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	kit.death_delay = 0.1
	g.add_child(kit)
	g.remove_child(g.player)
	g.player.free()
	player = load(MDSPlayer.SCENE).instantiate()
	g.add_child(player)
	g.player = player
	kit.boss_started.connect(func(b: String) -> void: started.append(b))
	kit.boss_ended.connect(func(b: String, won: bool) -> void: ended.append([b, won]))
	return g

## Crypt_01 gets the Warden, an arena over the middle of the room and two doors.
func _add_arena() -> void:
	var path := Fixture.DIR + "/crypt_01.tscn"
	var root: Node = (load(path) as PackedScene).instantiate()
	var boss := MDSBoss.new()
	boss.name = "Warden"
	boss.boss_name = "Warden"
	boss.position = Vector2(760, 528)
	root.add_child(boss)
	var doors: Array[MDSArenaDoor] = []
	for x in [180, 1000]:
		var d := MDSArenaDoor.new()
		d.name = "Door%d" % x
		d.position = Vector2(x, 486)
		root.add_child(d)
		doors.append(d)
	var arena := MDSBossArena.new()
	arena.name = "Arena"
	arena.position = Vector2(600, 400)
	arena.size = Vector2(700, 400)
	arena.grants = "warden_seal"
	root.add_child(arena)
	arena.boss = boss
	arena.doors = doors
	check(save_scene(root, path) == OK, "Crypt_01 saved with the Warden's arena")
	root.free()
	load_fresh(path)

func _boss() -> MDSBoss:
	var b := game.room_node.get_node_or_null("Warden") as MDSBoss
	return b if b and not b.is_queued_for_deletion() else null

func _arena() -> MDSBossArena:
	return game.room_node.get_node_or_null("Arena") as MDSBossArena

func _enter_crypt() -> void:
	game.load_room("Crypt_01", "left1")
	await game.room_loaded
	player.health.invulnerable = true
	await physics_frames(5)
	player.global_position = game.world.get_origin("Crypt_01") + Vector2(500, 540)
	await physics_frames(5)

func _music() -> MDSMusic:
	return game.get_node("Music")

func _doors_closed() -> bool:
	return (game.room_node.get_node("Door180") as MDSArenaDoor).is_closed and (game.room_node.get_node("Door1000") as MDSArenaDoor).is_closed

func _lost_fight() -> void:
	await _enter_crypt()
	var boss := _boss()
	check(boss != null and _arena().fighting and boss.fighting, "walking into the arena starts the fight")
	check(_doors_closed(), "its doors shut")
	check(_music().boss_active and _music().current_stream == load(Fixture.BOSS), "the boss music plays (the area's boss_music)")
	check(started == ["Warden"] and kit.current_boss == "Warden" and kit.boss_node == boss, "the kit reports the fight (the HUD's boss bar)")
	var hit := MDSDamageInfo.make(int(boss.health.get_max() * 0.5) + 1)
	hit.ignores_iframes = true
	boss.health.apply_damage(hit)
	await physics_frames(2)
	check(boss.phase_index == 1 and boss.machine.is_in(&"Stagger"), "at half health phase 2 starts (it staggers)")
	# The player falls in the fight.
	player.health.invulnerable = false
	var kill := MDSDamageInfo.make(99)
	kill.ignores_iframes = true
	player.health.apply_damage(kill)
	await physics_frames(2)
	check(ended == [["Warden", false]], "dying ends the fight lost (%s)" % [ended])
	await game.room_loaded
	await physics_frames(5)
	check(not _music().boss_active, "the boss music stops")
	check(game.current_room == "Garden_01" and player.health.current == player.health.get_max(), "the player is back at the start, healed")
	await physics_frames(30)

func _won_fight() -> void:
	started.clear()
	ended.clear()
	await _enter_crypt()
	var boss := _boss()
	check(boss != null and boss.phase_index == 0 and boss.health.current == boss.health.get_max(), "back in the crypt the boss is whole again, at phase 1")
	check(started == ["Warden"], "and the fight starts again")
	var kill := MDSDamageInfo.make(999)
	kill.ignores_iframes = true
	boss.health.apply_damage(kill)
	await physics_frames(3)
	check(game.is_boss_defeated("Warden"), "defeated, the Warden is recorded by name")
	check(game.is_objective_complete("Crypt"), "the Crypt's objective (boss:Warden) is complete")
	check(ended == [["Warden", true]] and kit.current_boss.is_empty(), "the fight ends won")
	check(not _music().boss_active, "the music goes back to the area's")
	check(not _doors_closed(), "the doors open")
	check(game.has_ability("warden_seal"), "the arena grants its ability")
	await physics_frames(90)
	await _go_and_back()
	check(_boss() == null, "the boss is gone when the room loads again")
	check(not _arena().fighting and not _doors_closed(), "and the arena stays quiet, its doors open")

func _go_and_back() -> void:
	game.load_room("Garden_02", "right1")
	await game.room_loaded
	await physics_frames(3)
	await _enter_crypt()
