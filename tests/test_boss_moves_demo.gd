extends "res://tests/test_case.gd"
## The boss moves demo (examples/boss_moves_demo, built by build_boss_moves_demo.gd), played: each
## room's fight starts when the player is there, runs in the room and can be won.

const DEMO := "res://examples/boss_moves_demo"
const Builder := preload("res://examples/boss_moves_demo/build_boss_moves_demo.gd")

func _run() -> void:
	MDSGameplaySetup.ensure_runtime_actions()
	var world := MDSWorld.get_cached(DEMO + "/boss_moves_demo.mdsworld.json")
	check(world != null, "the world loads")
	if not world:
		return
	check(world.get_room_ids().size() == Builder.FIGHTS.size(), "a room for each fight")
	check(_gates_ok(world), "its gates connect")
	var game := (load(DEMO + "/game.tscn") as PackedScene).instantiate() as MDSWorldGame
	game.save_file = TMP + "/boss_moves_demo_save.json"
	game.exploration_file = TMP + "/boss_moves_demo_exploration.json"
	add_child(game)
	await game.room_loaded
	await physics_frames(5)
	for id: String in Builder.FIGHTS:
		await _fight(game, id)
	game.queue_free()
	await get_tree().process_frame

func _gates_ok(world: MDSWorld) -> bool:
	var ids := world.get_room_ids()
	for i in ids.size():
		if world.get_gates(ids[i]).is_empty():
			return false
	return true

func _fight(game: MDSWorldGame, id: String) -> void:
	if game.current_room != id:
		game.load_room(id, "left1")
		await game.room_loaded
	game.player.health.invulnerable = true
	await physics_frames(10)
	var boss := game.room_node.get_node_or_null("Boss") as MDSMoveBoss
	check(boss != null, "%s has its boss" % id)
	if not boss:
		return
	var arena := game.room_node.get_node("Arena") as MDSBossArena
	check(arena.fighting and boss.fighting, "%s: the fight starts when the player is there" % id)
	check(boss.recipe == Builder.FIGHTS[id][0], "%s: it has its recipe" % id)
	await physics_frames(180)
	var room := Rect2(game.world.get_origin(id), Builder.ROOM).grow(60.0)
	check(room.has_point(boss.global_position), "%s: it stays in the room (%s)" % [id, boss.global_position])
	var hit := MDSDamageInfo.make(99999)
	hit.ignores_iframes = true
	boss.health.apply_damage(hit)
	await physics_frames(3)
	for partner in boss.partners:
		if is_instance_valid(partner) and not partner.dying:
			partner.health.apply_damage(hit)
	await physics_frames(3)
	check(arena.won and game.is_boss_defeated(Builder.FIGHTS[id][1]), "%s can be won" % id)
