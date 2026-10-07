extends "res://tests/test_case.gd"
## Briefs 12, 13, 14, 17 and 18: MDSWorldGame's room mood, area titles and music, objectives,
## interactive transitions and persistence, on the fixture world (game_fixture.gd).

const Fixture := preload("res://tests/game_fixture.gd")
const EXPLORATION := "user://idp_test_exploration.json"

var game: MDSWorldGame

func _run() -> void:
	_objectives_in_editor(Fixture.build())
	if FileAccess.file_exists(EXPLORATION):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPLORATION))
	game = Fixture.make_game(EXPLORATION)
	add_child(game)
	await game.room_loaded
	await settle()
	await _titles_and_music()
	await _darkness()
	await _objectives()
	await _barrier_and_doors()
	await _defeated_and_followers()
	var save := game.get_save_data()
	game.queue_free()
	await get_tree().process_frame
	await _save_and_exploration(save)
	await _darkness_auto()

func settle(frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame

func go(room: String, gate := "") -> void:
	game.load_room(room, gate)
	await game.room_loaded
	await settle()

func _title() -> MDSAreaTitle:
	return game.get_node("UI/Title")

func _music() -> MDSMusic:
	return game.get_node("Music")

# --- Brief 13 ---------------------------------------------------------------------------------------

func _titles_and_music() -> void:
	var title := _title()
	var music := _music()
	check(game.current_room == "Garden_01" and game.current_area == "Gardens", "the game starts in the Gardens")
	check(title.shown_area == "Gardens" and title._title.text == "THE SUNKEN GARDENS", "the area's title is shown (%s)" % title._title.text)
	check(title._subtitle.text == "Where the old city drowned", "with its subtitle")
	check(music.current_stream == load(Fixture.MUSIC_A) and music.active_player().playing, "the Gardens music plays")
	var shown := [0]
	title.shown.connect(func(_a: String) -> void: shown[0] += 1)
	var player_before := music.active_player()
	await go("Garden_02", "left1")
	check(shown[0] == 0, "walking within the area shows no title")
	check(music.active_player() == player_before and music.active_player().playing and music.current_stream == load(Fixture.MUSIC_A), "the music keeps playing: no restart, no double play")
	await go("Crypt_01", "left1")
	check(shown[0] == 1 and title.shown_area == "Crypt" and title._title.text == "THE CRYPT", "entering the Crypt shows its title once")
	check(music.current_stream == load(Fixture.MUSIC_B), "the Crypt music takes over")
	var players: Array[AudioStreamPlayer] = music._players
	check(players[0].playing and players[1].playing, "during the crossfade both play (no gap)")
	await get_tree().create_timer(0.4).timeout
	check(not player_before.playing and music.active_player().playing, "after the crossfade only the Crypt music plays")
	check_near(music.active_player().volume_db, 0.0, 0.5, "at the Crypt's volume")
	# Boss music: from silence, safe to call twice, and back.
	music.play_boss()
	var boss_player := music.active_player()
	check(music.current_stream == load(Fixture.BOSS) and boss_player.volume_db < -40.0, "the boss music starts from silence")
	music.play_boss()
	check(music.active_player() == boss_player, "play_boss twice changes nothing")
	await get_tree().create_timer(0.4).timeout
	check(boss_player.volume_db > -1.0, "and rises")
	music.end_boss()
	check(music.current_stream == load(Fixture.MUSIC_B) and not music.boss_active, "end_boss returns to the area's music")
	# first_visit_only: back in the Crypt later, no title.
	await go("Garden_02", "right1")
	check(shown[0] == 2, "back to the Gardens: their title again (first_visit_only is off)")
	title.first_visit_only = true
	await go("Crypt_01", "left1")
	check(shown[0] == 2, "with first_visit_only, the Crypt's second visit shows no title")
	check(game.area_visits.Crypt == 2 and game.area_visits.Gardens == 2, "area visits are counted (%s)" % game.area_visits)

# --- Brief 12 ---------------------------------------------------------------------------------------

func _darkness() -> void:
	check(game.current_room == "Crypt_01", "sanity: in the Crypt")
	var dark := game.room_node.get_node_or_null("MDSDarkness") as DirectionalLight2D
	check(dark != null and dark.blend_mode == Light2D.BLEND_MODE_SUB and is_equal_approx(dark.energy, 0.6), "the dark Crypt is dimmed by a subtractive light")
	var plight := game.player.get_node_or_null("MDSLight") as PointLight2D
	check(plight != null and plight.enabled, "the player carries a light in the dark")
	var bat := game.room_node.get_node("Bat")
	var blight := bat.get_node_or_null("MDSLight") as PointLight2D
	check(blight != null and blight.enabled, "enemies carry a light too")
	await go("Garden_02", "right1")
	check(game.room_node.get_node_or_null("MDSDarkness") == null and is_zero_approx(game.darkness), "leaving it restores full light")
	check(not plight.enabled, "the player's light goes out")

# --- Brief 14 ---------------------------------------------------------------------------------------

func _objectives() -> void:
	var banner: MDSObjectiveBanner = game.get_node("UI/Banner")
	check(banner.shown_text == "Find the crypt key" and not banner.shown_done, "arriving in the Gardens shows their objective")
	check(game.map_view.objective == "Find the crypt key", "the map shows it too")
	var done: Array = []
	game.objective_completed.connect(func(a: String) -> void: done.append(a))
	game.grant_ability("crypt_key")
	check(done == ["Gardens"] and game.is_objective_complete("Gardens"), "granting the key completes the Gardens' objective")
	check(banner.shown_done and banner.shown_text == "Find the crypt key", "the banner marks it done")
	check(game.map_view.objective_done, "so does the map")
	game.defeat_boss("Warden")
	check(game.is_objective_complete("Crypt"), "defeating the Warden completes the Crypt's")
	check(Array(game.get_save_data().objectives) == ["Gardens", "Crypt"] or Array(game.get_save_data().objectives) == ["Crypt", "Gardens"], "objectives are saved")

## The Stats and Progress tabs list objectives (MDSAnalysis.get_objectives) and the Issues tab
## flags the ones that can never complete.
func _objectives_in_editor(world: MDSWorld) -> void:
	var never := func() -> Array:
		var analysis := MDSAnalysis.new(MDSGraph.from_world(world, {}), world, {}).run()
		var issues := MDSWorldValidator.run(world, analysis, {})
		return [analysis.get_objectives(), issues.filter(func(i: Dictionary) -> bool: return str(i.message).contains("can never complete"))]
	var r: Array = never.call()
	check(r[0].size() == 2, "both areas' objectives are listed")
	check(r[1].size() == 2, "nothing grants the key and no room has the Warden: both flagged (%s)" % [r[1].map(func(i: Dictionary) -> String: return i.message)])
	world.set_room_value("Garden_02", "grants", ["crypt_key"])
	world.set_room_value("Crypt_01", "boss", "Warden")
	r = never.call()
	check(r[1].is_empty(), "with a room granting the key and a Warden room nothing is flagged")
	var gardens: Dictionary = r[0].filter(func(o: Dictionary) -> bool: return o.area == "Gardens")[0]
	check(gardens.kind == "ability" and gardens.rooms == ["Garden_02"] and gardens.sphere == 0, "the Gardens' objective completes in Garden_02, sphere 0 (%s)" % [gardens])
	world.set_area_value("Crypt", "objective_done_when", "object:Nowhere_09/Chest")
	r = never.call()
	check(r[1].size() == 1, "a stored object in a room that doesn't exist is flagged")
	world.set_area_value("Crypt", "objective_done_when", "boss:Warden")
	world.set_room_value("Garden_02", "grants", [])
	world.set_room_value("Crypt_01", "boss", "")

# --- Brief 17 ---------------------------------------------------------------------------------------

func _barrier_and_doors() -> void:
	# The key was granted above: the barrier on right1 is open, and stays open.
	var barrier := game.room_node.get_node("Barrier") as MDSGateBarrier
	await settle()
	check(barrier.is_open, "the barrier opened when its ability was granted")
	check(game.is_object_stored(game.object_id(barrier)), "its opening is remembered")
	# Leave and come back: open from the start.
	await go("Garden_01", "right1")
	await go("Garden_02", "left1")
	barrier = game.room_node.get_node("Barrier") as MDSGateBarrier
	await settle()
	check(barrier.is_open and not barrier.visible, "it starts open after coming back")
	# A shut one: a new barrier needing an ability the player hasn't.
	var shut := MDSGateBarrier.new()
	shut.requires = PackedStringArray(["double_jump"])
	var bs := CollisionShape2D.new()
	bs.shape = RectangleShape2D.new()
	shut.add_child(bs)
	game.room_node.add_child(shut)
	await settle()
	check(not shut.is_open and not bs.disabled, "a barrier whose ability is missing stays shut and solid")
	game.grant_ability("double_jump")
	await settle(4)
	check(shut.is_open and bs.disabled, "it opens when the ability is granted")
	# Interact door (link): standing in it does nothing until Interact.
	await go("Crypt_01", "left1")
	var door := MDSGate.find_gate(game.room_node, "door1")
	check(door.mode == MDSGate.Mode.INTERACT and door.link, "sanity: door1 is an interact link door")
	var t := door.get_transition()
	check(t.get("room") == "Garden_01" and t.get("gate") == "door1" and t.get("link"), "the link leads to Garden_01's door (%s)" % t)
	check(door.destination_name() == "Gardens", "its prompt names where it leads (%s)" % door.destination_name())
	game.player.global_position = door.global_position
	await physics_frames(4)
	check(game.current_room == "Crypt_01", "standing in the door doesn't go through it")
	check(door._prompt and door._prompt.visible and door._prompt.text.contains("Gardens"), "the prompt shows")
	Input.action_press(&"ui_up")
	await settle(2)
	Input.action_release(&"ui_up")
	if game.changing_room:
		await game.room_loaded
	await settle()
	check(game.current_room == "Garden_01", "Interact takes the player through the link")
	check(game.player.global_position.distance_to(MDSGate.find_gate(game.room_node, "door1").global_position) < 2.0, "arriving at the other door")
	# A cinematic between rooms.
	var cine := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar played := false\nfunc play(_t: Dictionary) -> void:\n\tplayed = true\n\tawait get_tree().process_frame\n"
	script.reload()
	cine.set_script(script)
	var packed := PackedScene.new()
	packed.pack(cine)
	cine.free()
	await game.play_cinematic(packed)
	check(game._cinema.get_child_count() == 0 or game._cinema.get_child(0).is_queued_for_deletion(), "a cinematic plays and goes")

# --- Brief 18 ---------------------------------------------------------------------------------------

func _defeated_and_followers() -> void:
	await go("Garden_01", "")
	var guard := game.room_node.get_node("Guard")
	game.mark_defeated(guard)
	guard.queue_free()
	await go("Garden_02", "left1")
	await go("Garden_01", "right1")
	check(game.room_node.get_node_or_null("Guard") == null, "a defeated enemy stays gone after leaving and coming back")
	# The follower by Garden_02's right1 follows the player into the Crypt.
	await go("Garden_02", "left1")
	var follower := game.room_node.get_node("Follower") as Node2D
	var exit := MDSGate.find_gate(game.room_node, "right1")
	check(follower.global_position.distance_to(exit.global_position) < game.carry_over_distance, "sanity: the follower is near right1")
	game.player.global_position = exit.global_position
	for i in 30:
		await get_tree().physics_frame
		if game.changing_room or game.current_room != "Garden_02":
			break
	if game.changing_room:
		await game.room_loaded
	await settle()
	check(game.current_room == "Crypt_01", "the player went through right1")
	var came := game.room_node.get_node_or_null("Follower") as Node2D
	check(came != null and came.has_meta(&"idp_carried"), "the follower came along into the next room")
	if came:
		var entry := MDSGate.find_gate(game.room_node, "left1")
		check(came.global_position.distance_to(entry.global_position) < 140.0, "it appears by the gate it came through (%s)" % came.global_position)
	await go("Garden_02", "right1")
	var back := game.room_node.get_node_or_null("Follower")
	check(back == null, "it is no longer in the room it left")

func _save_and_exploration(save: Dictionary) -> void:
	# A fresh game with no save: the exploration file still knows the rooms visited.
	var fresh := Fixture.make_game(EXPLORATION)
	add_child(fresh)
	await fresh.room_loaded
	check(fresh.is_room_visited("Crypt_01") and fresh.is_room_visited("Garden_02"), "the exploration file keeps the visited rooms without a save")
	check(fresh.map_view.visited_rooms.has("Crypt_01"), "and the map shows them")
	# Loading the save: defeated enemies stay gone, objectives stay done.
	fresh.set_save_data(save)
	await fresh.room_loaded
	await settle()
	check(fresh.is_defeated("Garden_01/Guard"), "defeated enemies are restored")
	check(fresh.is_objective_complete("Gardens") and fresh.is_objective_complete("Crypt"), "completed objectives are restored")
	fresh.load_room("Garden_01")
	await fresh.room_loaded
	check(fresh.room_node.get_node_or_null("Guard") == null, "the defeated guard stays gone after loading")
	fresh.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPLORATION))

func _darkness_auto() -> void:
	var world := MDSWorld.get_cached(Fixture.WORLD)
	var g := MDSWorldGame.new()
	g.world = world
	check(is_zero_approx(g.get_darkness("Garden_01")), "rooms are lit unless set")
	check(is_equal_approx(g.get_darkness("Crypt_01"), 0.6), "an area's darkness applies to its rooms")
	world.set_room_value("Crypt_01", "darkness", 0.0)
	check(is_zero_approx(g.get_darkness("Crypt_01")), "a room can force itself lit")
	world.set_setting("dark_room_share", 1.0)
	var d := g.get_darkness("Garden_01")
	check(d >= 0.35 and d <= 0.55 and g.get_darkness("Garden_01") == d, "automatic darkness is picked from the room, the same every time (%.2f)" % d)
	world.set_setting("dark_room_share", 0.0)
	world.set_room_value("Crypt_01", "darkness", null)
	g.free()
