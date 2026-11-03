extends "res://tests/mcp_test_case.gd"
## The MCP room tools: generating, painting, placing, enemies. Reopens the scenes to check.

func _run() -> void:
	start_server()
	await make_world()

	var made: Dictionary = await ok("mds_room_scene_create", {"world": WORLD, "room": "R1"})
	check(FileAccess.file_exists(made.scene), "the scene is there")
	check(MDSWorld.load_world(WORLD).get_scene_path("R1") == made.scene, "the world knows it")
	await refused("mds_room_scene_create", {"world": WORLD, "room": "R1"}, "already_exists")
	var painter := MDSRoomPainter.open_packed(MDSWorldSceneTools.load_fresh(made.scene), made.scene)
	check("right1" in painter.gate_nodes(), "the scene has the gate's node")
	painter.free_instance()

	# Generating.
	var one: Dictionary = await ok("mds_room_generate", {"world": WORLD, "room": "R1", "style": "cave", "seed": 7})
	check(one.paths_joined and one.warnings.is_empty(), "the gates are joined")
	var first := _terrain_of(one.scene)
	check(first.size() > 100, "terrain was painted: %d" % first.size())
	await refused("mds_room_generate", {"world": WORLD, "room": "R1", "seed": 7}, "room_already_painted")
	await ok("mds_room_generate", {"world": WORLD, "room": "R1", "style": "cave", "seed": 7, "overwrite": true})
	check(_terrain_of(one.scene) == first, "the same seed makes the same room")
	await ok("mds_room_generate", {"world": WORLD, "room": "R1", "style": "cave", "seed": 8, "overwrite": true})
	check(_terrain_of(one.scene) != first, "another seed makes another room")

	var caves: Dictionary = await ok("mds_area_generate_caves", {"world": WORLD, "area": "A", "cave": {"style": "linear"}, "seed": 3})
	check(caves.skipped == ["R1"] and caves.generated == ["R2"] and caves.made == ["R2"], "painted rooms are left alone: %s" % caves)
	check(MDSWorld.load_world(WORLD).get_scene_path("R2").length() > 0, "the world knows the new scene")
	await refused("mds_area_generate_caves", {"world": WORLD}, "bad_arguments")

	# Painting.
	var scene: String = one.scene
	await ok("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "fill", "cells": [[1, 1], [2, 1]], "fill": {"type": "color", "color": "#ff0000"}})
	check(_cells_of(scene, "Decor").has(Vector2i(1, 1)), "a color fill")
	await ok("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "erase", "rect": {"x": 1, "y": 1, "w": 1, "h": 1}})
	check(not _cells_of(scene, "Decor").has(Vector2i(1, 1)) and _cells_of(scene, "Decor").has(Vector2i(2, 1)), "erase")
	await ok("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "clear"})
	check(_cells_of(scene, "Decor").is_empty(), "clear")
	await refused("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Decor", "op": "erase"}, "bad_arguments")
	await refused("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Nope", "op": "clear"}, "bad_arguments")
	var decorated: Dictionary = await ok("mds_room_decorate", {"world": WORLD, "room": "R1", "seed": 2})
	check(decorated.placed > 0 and not _cells_of(scene, "Decor").is_empty(), "decorated")

	# Placing.
	var catalog: Dictionary = await ok("mds_catalog", {"kind": "enemy_templates"})
	check(catalog.items.size() >= 5, "enemy templates are listed")
	var placed: Dictionary = await ok("mds_room_place", {"world": WORLD, "room": "R1", "kind": "enemy", "template": "walker", "pos": {"x": 400, "y": 300}, "name": "Walky"})
	check(placed.node == "Walky", "placed as asked: %s" % placed)
	await refused("mds_room_place", {"world": WORLD, "room": "R1", "kind": "enemy", "template": "nope", "pos": {"x": 0, "y": 0}}, "not_found")
	await refused("mds_room_place", {"world": WORLD, "room": "R1", "kind": "effect", "template": "nope", "pos": {"x": 0, "y": 0}}, "not_found")
	var effect_id: String = MDSEnvironment.effect_ids()[0]
	var effect: Dictionary = await ok("mds_room_place", {"world": WORLD, "room": "R1", "kind": "effect", "template": effect_id, "pos": {"x": 100, "y": 100}})
	check(not effect.node.is_empty(), "an effect")
	var items: Dictionary = await ok("mds_room_items", {"world": WORLD, "room": "R1"})
	var kinds: Array = items.items.map(func(i: Dictionary) -> String: return i.kind)
	check("enemy" in kinds and "effect" in kinds and "gate" in kinds, "items are listed: %s" % [kinds])

	# An enemy's look survives the save.
	await ok("mds_enemy_configure", {"world": WORLD, "room": "R1", "node": "Walky", "damage_type": "fire", "attack_color": "#ff8800", "hurt_particles": "embers", "particle_palette": ["#ff0000", "#ffff00"], "particle_size": 2.0, "contact_damage": 3, "facing": 1, "respawn": "never"})
	var instance := MDSWorldSceneTools.load_fresh(scene).instantiate()
	var walky := instance.get_node("Walky") as MDSEnemy
	check(walky.damage_type == "fire" and walky.hurt_particles == "embers" and walky.contact_damage == 3 and walky.facing == 1, "enemy values reloaded")
	check(walky.attack_color.is_equal_approx(Color("#ff8800")) and walky.particle_palette.size() == 2 and walky.particle_size == 2.0 and walky.respawn == MDSEnemy.Respawn.NEVER, "colors and respawn reloaded")
	instance.free()
	await refused("mds_enemy_configure", {"world": WORLD, "room": "R1", "node": "Walky", "damage_type": "nope"}, "bad_id")
	await refused("mds_enemy_configure", {"world": WORLD, "room": "R1", "node": "Walky", "hurt_particles": "nope"}, "bad_id")
	await refused("mds_enemy_configure", {"world": WORLD, "room": "R1", "node": "Nope"}, "node_not_found")
	await refused("mds_enemy_configure", {"world": WORLD, "room": "R1", "node": "Walky", "attack_color": "nope"}, "bad_arguments")

	# Objects, and removing.
	var fit: Dictionary = await ok("mds_room_fit_objects", {"world": WORLD, "room": "R1", "mode": "floor"})
	check(fit.edits >= 0, "fit to the floor runs")
	await refused("mds_room_remove_item", {"world": WORLD, "room": "R1", "node": "Walky"}, "bad_arguments")
	await refused("mds_room_remove_item", {"world": WORLD, "room": "R1", "node": "Terrain", "confirm": true}, "node_not_found")
	await ok("mds_room_remove_item", {"world": WORLD, "room": "R1", "node": "Walky", "confirm": true})
	instance = MDSWorldSceneTools.load_fresh(scene).instantiate()
	check(not instance.has_node("Walky"), "removed")
	instance.free()

	# Seeing it.
	var text: Dictionary = await ok("mds_room_ascii", {"world": WORLD, "room": "R1"})
	check(text.rows.size() > 0 and "#" in "".join(text.rows), "ascii has rock")
	check("g" in "".join(text.rows), "ascii shows the gate")
	var scaled: Dictionary = await ok("mds_room_ascii", {"world": WORLD, "room": "R1", "scale": 4})
	check(scaled.rows.size() < text.rows.size(), "scale shrinks it")
	var answer: Dictionary = await server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "mds_room_preview", "arguments": {"world": WORLD, "room": "R1"}}})
	var image: Dictionary = answer.result.content[0]
	check(image.type == "image" and image.mimeType == "image/png", "preview is an image")
	var png := Image.new()
	check(png.load_png_from_buffer(Marshalls.base64_to_raw(image.data)) == OK and png.get_width() > 0, "preview is a real PNG")

	# A failed tool leaves the files as they were.
	var before := FileAccess.get_file_as_bytes(scene)
	await refused("mds_room_paint", {"world": WORLD, "room": "R1", "layer": "Terrain", "op": "tile"}, "bad_arguments")
	check(FileAccess.get_file_as_bytes(scene) == before, "the scene is unchanged")
	end_server()

func _terrain_of(path: String) -> Dictionary:
	return _cells_of(path, "Terrain")

func _cells_of(path: String, layer_name: String) -> Dictionary:
	var painter := MDSRoomPainter.open_packed(MDSWorldSceneTools.load_fresh(path), path)
	var out := {}
	for c in painter.layer(layer_name).get_used_cells():
		out[c] = true
	painter.free_instance()
	return out
