extends "res://tests/test_case.gd"
## Gameplay Kit, phase 6: the death flow. Dying sends the player back to the bench it last rested
## on (MDSWorldGame.return_to_save_point), healed, with the death penalty of the project setting:
## CORPSE leaves the currency in an MDSCorpse where it died (kept in the save; touching it gives the
## currency back, dying again first loses it), LOSE_PERCENT takes a share, NONE nothing. With
## death_reverts_to_save the save is loaded instead. A level overview in the game pulls back first.

const Fixture := preload("res://tests/game_fixture.gd")
const SAVE := "user://mds_test_gameplay_death.json"
const P := MDSGameplaySetup.PREFIX

var game: MDSWorldGame
var kit: MDSGameplay
var player: MDSPlayer
var overview_opened := 0

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Fixture.build()
	_add_bench()
	game = _game()
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	await _rest()
	await _corpse()
	await _corpse_lost()
	await _lose_percent()
	await _reverts_to_save()
	for k in ["death_penalty", "death_reverts_to_save"]:
		ProjectSettings.set_setting(P + k, null)
	game.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

func _game() -> MDSWorldGame:
	var g := Fixture.make_game("", SAVE)
	kit = MDSGameplay.new()
	kit.name = "Gameplay"
	kit.death_delay = 0.1
	kit.death_overview_time = 0.2
	g.add_child(kit)
	var ov := MDSLevelOverview.new()
	ov.name = "LevelOverview"
	ov.pull_time = 0.1
	ov.opened.connect(func() -> void: overview_opened += 1)
	g.add_child(ov)
	g.remove_child(g.player)
	g.player.free()
	player = load(MDSPlayer.SCENE).instantiate()
	g.add_child(player)
	g.player = player
	return g

## Garden_02 gets a bench.
func _add_bench() -> void:
	var path := Fixture.DIR + "/garden_02.tscn"
	var root: Node = (load(path) as PackedScene).instantiate()
	var bench := MDSBench.new()
	bench.name = "Bench"
	bench.position = Vector2(400, 576)
	root.add_child(bench)
	bench.owner = root
	check(save_scene(root, path) == OK, "Garden_02 saved with a bench")
	root.free()
	load_fresh(path)

func _bench() -> MDSBench:
	return game.room_node.get_node_or_null("Bench") as MDSBench

func _go(room: String, gate: String) -> void:
	game.load_room(room, gate)
	await game.room_loaded
	await physics_frames(5)

func _rest() -> void:
	await _go("Garden_02", "left1")
	var bench := _bench()
	check(bench != null and bench.rest(player), "the player rests on Garden_02's bench (it saves)")
	bench.leave()
	await physics_frames(3)
	check(str(game.respawn.get("room", "")) == "Garden_02", "the bench is where the player comes back")

## The player dies (in [param room] when given), and is back after the death flow.
func _die(room := "") -> void:
	if not room.is_empty():
		await _go(room, "left1")
		player.global_position = game.world.get_origin(room) + Vector2(560, 540)
		await physics_frames(10)
	player.health.invulnerable = false
	var hit := MDSDamageInfo.make(99)
	hit.ignores_iframes = true
	player.health.apply_damage(hit)
	await physics_frames(2)
	check(player.machine.is_in(&"Dead"), "the player is dead (%s)" % player.machine.get_state())
	await game.room_loaded
	await physics_frames(5)

func _corpses() -> Array:
	return game.room_node.get_children().filter(func(n: Node) -> bool: return n is MDSCorpse and not n.is_queued_for_deletion())

func _corpse() -> void:
	kit.add_currency(100)
	kit.raise_max_mana(0)
	kit.set_mana(5)
	var died := [0]
	kit.player_died.connect(func() -> void: died[0] += 1)
	await _die("Crypt_01")
	check(died[0] == 1 and kit.deaths == 1, "player_died, one death")
	check(overview_opened == 1, "the level overview pulled back over the level")
	check(game.current_room == "Garden_02" and absf(player.global_position.x - (game.world.get_origin("Garden_02").x + 400.0)) < 4.0, "back at the bench (%s %s)" % [game.current_room, player.global_position])
	check(player.health.current == player.health.get_max() and kit.mana == kit.player_max_mana(), "healed, mana full")
	check(not player.machine.is_in(&"Dead"), "up again (%s)" % player.machine.get_state())
	check(kit.currency == 0 and int(kit.corpse.get("currency", 0)) == 100 and kit.corpse.get("room") == "Crypt_01", "CORPSE: the currency lies in Crypt_01 (%s)" % [kit.corpse])
	check(_corpses().is_empty(), "no corpse at the bench")
	# The corpse is kept in the save.
	var data := game.get_save_data()
	check(int(data.ext.gameplay.corpse.get("currency", 0)) == 100, "ext.gameplay.corpse holds it")
	game.set_save_data(data)
	await game.room_loaded
	await physics_frames(3)
	await _go("Crypt_01", "left1")
	var cs := _corpses()
	check(cs.size() == 1 and (cs[0] as MDSCorpse).currency == 100, "the corpse lies in Crypt_01, holding 100")
	var at: Vector2 = (cs[0] as MDSCorpse).global_position
	check(absf(at.x - (game.world.get_origin("Crypt_01").x + 560.0)) < 4.0, "where the player died (%s)" % at)
	player.global_position = at
	await physics_frames(4)
	check(kit.currency == 100 and kit.corpse.is_empty() and _corpses().is_empty(), "touching it gives the currency back")

func _corpse_lost() -> void:
	await _die("Crypt_01")
	check(kit.currency == 0 and int(kit.corpse.get("currency", 0)) == 100, "died again: a new corpse")
	await _die()
	check(kit.corpse.is_empty() and kit.currency == 0, "dying before reaching it loses it")
	check(kit.deaths == 3, "three deaths")

func _lose_percent() -> void:
	ProjectSettings.set_setting(P + "death_penalty", MDSGameplaySetup.DeathPenalty.LOSE_PERCENT)
	kit.add_currency(90)
	await _die()
	check(kit.currency == 45 and kit.corpse.is_empty(), "LOSE_PERCENT takes half (death_penalty_share), no corpse (%d)" % kit.currency)
	ProjectSettings.set_setting(P + "death_penalty", MDSGameplaySetup.DeathPenalty.NONE)
	await _die()
	check(kit.currency == 45, "NONE takes nothing")

func _reverts_to_save() -> void:
	ProjectSettings.set_setting(P + "death_reverts_to_save", true)
	var bench := _bench()
	bench.rest(player)
	bench.leave()
	await physics_frames(3)
	kit.add_item("trinket")
	kit.add_currency(10)
	var deaths := kit.deaths
	await _die("Crypt_01")
	check(kit.get_item_count("trinket") == 0 and kit.currency == 45, "death_reverts_to_save loads the save: what came after it is gone")
	check(kit.deaths == deaths + 1, "the death still counts")
	check(game.current_room == "Garden_02" and player.health.current == player.health.get_max(), "back at the bench, healed")
