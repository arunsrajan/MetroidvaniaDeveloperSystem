extends "res://tests/test_case.gd"
## The Room view's layers (MDSRoomLayers): which layer each item is on, showing and hiding them
## on the canvas (nothing saved hidden, hidden items not picked), Solo in the Room view, and
## effects' Background / Foreground depth.

const Fixture := preload("res://tests/game_fixture.gd")

func _run() -> void:
	_depth()
	await _canvas_layers()
	await _room_view_solo()
	_save_shown_layers()
	await _room_view_save()

# --- Effect depth -----------------------------------------------------------------------------------

func _depth() -> void:
	var fog := MDSEnvironment.create("fog") as MDSFog
	add_child(fog)
	check(fog.depth == MDSEnvironmentEffect.Depth.AUTO and fog.z_index == 25 and not fog.is_background(), "fog draws in front by itself (z %d)" % fog.z_index)
	fog.depth = MDSEnvironmentEffect.Depth.BACKGROUND
	check(fog.z_index == MDSEnvironmentEffect.DEPTH_BACK_Z and fog.is_background(), "Background puts it behind the tiles (z %d)" % fog.z_index)
	check(MDSRoomLayers.of_effect(fog) == "effects_back", "on the Background effects layer")
	var copy := MDSEnvironmentEffect.from_data(fog.to_data())
	check(copy.depth == MDSEnvironmentEffect.Depth.BACKGROUND and copy.z_index == MDSEnvironmentEffect.DEPTH_BACK_Z, "its depth is kept in its data (undo, saving)")
	copy.free()
	fog.depth = MDSEnvironmentEffect.Depth.AUTO
	check(fog.z_index == 25, "Auto gives it back its own z (%d)" % fog.z_index)
	var falls := MDSEnvironment.create("waterfall")
	add_child(falls)
	check(falls.is_background() and MDSRoomLayers.of_effect(falls) == "effects_back", "a waterfall is behind the terrain by itself")
	falls.depth = MDSEnvironmentEffect.Depth.FOREGROUND
	check(falls.z_index == MDSEnvironmentEffect.DEPTH_FRONT_Z and MDSRoomLayers.of_effect(falls) == "effects_fore", "Foreground puts it in front")
	falls.free()
	fog.free()
	var spec := MDSEnvironment.build("fog(depth=back), rain(depth=front), embers", Rect2(0, 0, 400, 300))
	var fx := MDSEnvironment.effects_in(spec)
	check(fx.size() == 3 and fx[0].depth == MDSEnvironmentEffect.Depth.BACKGROUND and fx[1].depth == MDSEnvironmentEffect.Depth.FOREGROUND and fx[2].depth == MDSEnvironmentEffect.Depth.AUTO, "a weather spec sets depth=back / front")
	spec.free()
	check(MDSEnvironment.check("fog(depth=back)").is_empty() and MDSEnvironment.check("fog(depth=sideways)").contains("depth"), "a wrong depth is reported")

# --- The canvas ---------------------------------------------------------------------------------

func _canvas_layers() -> void:
	var world := Fixture.build()
	var painter := MDSRoomPainter.open(world.get_scene_path("Garden_01"))
	var canvas := MDSRoomCanvas.new()
	canvas.size = Vector2(800, 500)
	add_child(canvas)
	canvas.open(world, "Garden_01", painter)
	painter.layers["Terrain"].set_cell(Vector2i(2, 2), 0, Vector2i.ZERO)
	painter.layers["Background"].set_cell(Vector2i(3, 3), 0, Vector2i.ZERO)
	var stamps := MDSStampSet.new()
	stamps.texture = PlaceholderTexture2D.new()
	(stamps.texture as PlaceholderTexture2D).size = Vector2(64, 64)
	stamps.regions = [Rect2(0, 0, 32, 32)]
	var back := painter.add_stamp(stamps, 0, Vector2(200, 200), Vector2.ONE, 0.0, "StampsBack")
	var front := painter.add_stamp(stamps, 0, Vector2(300, 200), Vector2.ONE, 0.0, "StampsFront")
	var fog := painter.add_effect("fog", Vector2(500, 300))
	var falls := painter.add_effect("waterfall", Vector2(900, 300))
	var piece := painter.add_tile_piece("Decor", {Vector2i.ZERO: [0, Vector2i.ZERO, 0]}, Transform2D(0.0, Vector2(400, 400)))
	canvas.refresh_layers()
	check(MDSRoomLayers.of_item(back) == "stamps_back" and MDSRoomLayers.of_item(front) == "stamps", "stamps are on their depth's layer")
	check(MDSRoomLayers.of_item(fog) == "effects_fore" and MDSRoomLayers.of_item(falls) == "effects_back", "effects are on the layer of their depth")
	check(MDSRoomLayers.of_item(piece) == "decor", "free tiles are on their tile layer's")
	canvas.set_layer_visible("decor", false)
	check(not piece.visible and not painter.pickable_items().has(piece), "hiding Decor hides its free tiles")
	canvas.set_layer_visible("decor", true)
	check(piece.visible and not painter.view_hidden.has(piece), "and shows them again")
	check(MDSRoomLayers.IDS.size() == MDSRoomLayers.LABELS.size() and MDSRoomLayers.IDS.size() == MDSRoomLayers.TIPS.size(), "every layer has a name and a tooltip")

	canvas.set_layer_visible("stamps_back", false)
	check(not painter.items_root.get_node("StampsBack").visible and front.is_visible_in_tree(), "hiding Stamps (back) hides only those stamps")
	check(not painter.pickable_items().has(back) and painter.pickable_items().has(front), "a hidden stamp can't be picked")
	canvas.set_layer_visible("effects_fore", false)
	check(not fog.visible and falls.visible and painter.view_hidden.has(fog), "hiding Foreground effects hides the fog, not the waterfall")
	check(painter.effect_at(fog.position + fog.get_effect_rect().get_center()) != fog, "a hidden effect can't be selected")
	canvas.set_layer_visible("terrain", false)
	check(not painter.layers["Terrain"].visible and painter.layers["Background"].visible, "hiding Terrain hides its tiles")
	check(canvas.pick_at(painter.cell_rect("Terrain", Vector2i(2, 2)).get_center()).get("layer", "") != "Terrain", "hidden tiles are not picked")
	canvas.set_layer_visible("objects", false)
	check(painter.objects_hidden, "Objects hides the scene's other nodes")

	# Nothing is saved hidden: undo snapshots and the scene.
	painter.checkpoint()
	painter.undo()
	var fog_again: Node = painter.items(MDSRoomPainter.EFFECTS_GROUP).filter(func(n: Node) -> bool: return n is MDSFog).front()
	check(fog_again != null and fog_again.visible, "an undo gives back the effect shown (the layer hides it again)")
	canvas.refresh_layers()
	check(not fog_again.visible, "and refreshing the layers hides it")
	check(painter.save() == OK, "saved")
	var packed := load_fresh(painter.scene_path) as PackedScene
	var saved := packed.instantiate()
	var saved_fog: Node = saved.get_node("Effects").get_children().filter(func(n: Node) -> bool: return n is MDSFog).front()
	check(saved_fog != null and (saved_fog as CanvasItem).visible, "the saved scene has the fog shown")
	var saved_stamps := saved.get_node_or_null("StampsBack")
	check(saved_stamps == null or (saved_stamps as CanvasItem).visible, "and its stamps' group")
	saved.free()

	canvas.set_layers(MDSRoomLayers.solo("background"))
	check(painter.layers["Background"].visible and not painter.layers["Terrain"].visible and not painter.layers["Foreground"].visible, "solo Background shows only the Background tiles")
	check(not canvas.is_layer_visible("guides"), "solo hides the guides too (the Room view keeps them)")
	canvas.set_layers(MDSRoomLayers.all(true))
	check(painter.layers["Terrain"].visible and fog_again.visible and painter.items_root.get_node("StampsBack").visible and not painter.objects_hidden, "All shows everything again")
	canvas.close()
	canvas.queue_free()
	painter.free_instance()
	await get_tree().process_frame

# --- The Room view ------------------------------------------------------------------------------

func _room_view_solo() -> void:
	var world := Fixture.build()
	var view := MDSRoomView.new()
	view.size = Vector2(1400, 900)
	add_child(view)
	await get_tree().process_frame
	view.open_room(world, "Garden_01")
	var canvas := view.canvas
	check(view.layer_checks.size() == MDSRoomLayers.IDS.size(), "a checkbox per layer")
	view.set_layer_visible("decor", false)
	check(not canvas.is_layer_visible("decor") and not (view.layer_checks["decor"] as CheckBox).button_pressed, "a checkbox hides its layer")
	view.set_solo("terrain")
	check(view.get_solo() == "terrain" and canvas.is_layer_visible("terrain") and not canvas.is_layer_visible("background"), "Solo shows the layer alone")
	check(canvas.is_layer_visible("guides"), "keeping the guides")
	check(canvas.tool == MDSRoomCanvas.Tool.TERRAIN, "and points the brush at it")
	check((view.layer_solos["terrain"] as Button).button_pressed and not (view.layer_checks["background"] as CheckBox).button_pressed, "the buttons show it")
	view.set_solo("stamps_fore")
	check(canvas.tool == MDSRoomCanvas.Tool.STAMP and canvas.stamp_group == "StampsForeground", "solo foreground stamps places stamps in front")
	view.set_solo("effects_back")
	check(canvas.tool == MDSRoomCanvas.Tool.EFFECT and canvas.effect_depth == MDSEnvironmentEffect.Depth.BACKGROUND, "solo background effects places background effects")
	var e := canvas.place_effect("fog", Vector2(400, 300)) as MDSEnvironmentEffect
	check(e.depth == MDSEnvironmentEffect.Depth.BACKGROUND and e.visible, "a new effect gets the depth and shows")
	view.set_solo("")
	check(view.get_solo() == "" and canvas.is_layer_visible("terrain") and not canvas.is_layer_visible("decor") and canvas.is_layer_visible("background"), "Solo again gives back the layers as they were")
	view.set_effect_depth(MDSEnvironmentEffect.Depth.FOREGROUND)
	check(e.depth == MDSEnvironmentEffect.Depth.FOREGROUND and painter_dirty(view), "Depth changes the selected effect")
	view.set_layers(MDSRoomLayers.all(true))
	view.queue_free()
	await get_tree().process_frame

func painter_dirty(view: MDSRoomView) -> bool:
	return view.painter != null and view.painter.dirty

# --- Saving only the layers shown ---------------------------------------------------------------

func _saved_root(path: String) -> Node:
	return (load_fresh(path) as PackedScene).instantiate()

func _saved_layer(root: Node, layer_name: String) -> TileMapLayer:
	return root.find_children(layer_name, "TileMapLayer", true, false).front() if not root.find_children(layer_name, "TileMapLayer", true, false).is_empty() else null

func _effect_names(root: Node) -> Array:
	var fx := root.get_node_or_null("Effects")
	return fx.get_children().map(func(n: Node) -> String: return String(n.name)) if fx else []

func _save_shown_layers() -> void:
	check(MDSRoomLayers.unsaved({"terrain": false, "guides": false, "parallax_back": false, "decor": true}) == {"terrain": true}, "the guides and previews are never what Save leaves out")
	var world := Fixture.build()
	var path := world.get_scene_path("Garden_01")
	var painter := MDSRoomPainter.open(path)
	# Saved first: a fog (foreground effects) and a Background tile.
	var old_fog := painter.add_effect("fog", Vector2(300, 300))
	painter.layers["Background"].set_cell(Vector2i(1, 1), 0, Vector2i.ZERO)
	check(painter.save() == OK, "saved with every layer")
	# Then: a Terrain tile, another Background tile, a waterfall (background effects), and the fog deleted.
	painter.checkpoint()
	painter.layers["Terrain"].set_cell(Vector2i(5, 5), 0, Vector2i.ZERO)
	painter.layers["Background"].set_cell(Vector2i(2, 2), 0, Vector2i.ZERO)
	var falls := painter.add_effect("waterfall", Vector2(600, 300))
	painter.remove_item(old_fog)
	var skip := {"background": true, "effects_fore": true}
	check(painter.save_layers(skip) == OK, "saved the layers shown")
	var root := _saved_root(path)
	var terrain := _saved_layer(root, "Terrain")
	var bg := _saved_layer(root, "Background")
	check(terrain != null and terrain.get_cell_source_id(Vector2i(5, 5)) != -1, "a shown layer's change is saved (Terrain)")
	check(bg != null and bg.get_cell_source_id(Vector2i(1, 1)) != -1 and bg.get_cell_source_id(Vector2i(2, 2)) == -1, "an unticked layer keeps what the scene had (Background)")
	var names := _effect_names(root)
	check(names.has(String(falls.name)), "the waterfall (background effects, shown) is saved (%s)" % [names])
	check(names.has(String(old_fog.name)), "the fog deleted on an unticked layer is still in the scene (%s)" % [names])
	root.free()
	check(painter.dirty and painter.layers["Background"].get_cell_source_id(Vector2i(2, 2)) != -1, "the unticked layer's changes stay in the Room view, unsaved")
	check(painter.can_undo(), "and undoable")
	check(painter.save_layers({}) == OK and not painter.dirty, "saving with every layer shown saves them")
	var root2 := _saved_root(path)
	check(_saved_layer(root2, "Background").get_cell_source_id(Vector2i(2, 2)) != -1 and not _effect_names(root2).has(String(old_fog.name)), "then the Background tile and the fog's removal are saved too")
	root2.free()
	# Nothing changed on the layers shown: the scene isn't written.
	painter.layers["Decor"].set_cell(Vector2i(3, 3), 0, Vector2i.ZERO)
	var before := FileAccess.get_file_as_string(path)
	check(painter.save_layers({"decor": true}) == OK and FileAccess.get_file_as_string(path) == before and painter.dirty, "only an unticked layer changed: the scene is left as it is")
	painter.free_instance()

func _room_view_save() -> void:
	var world := Fixture.build()
	var view := MDSRoomView.new()
	view.size = Vector2(1400, 900)
	add_child(view)
	await get_tree().process_frame
	view.open_room(world, "Garden_01")
	var painter := view.painter
	var path := painter.scene_path
	painter.layers["Terrain"].set_cell(Vector2i(6, 6), 0, Vector2i.ZERO)
	painter.layers["Foreground"].set_cell(Vector2i(7, 7), 0, Vector2i.ZERO)
	painter.dirty = true
	view.set_layer_visible("foreground", false)
	check(view.save() == OK, "Save with Foreground unticked")
	var root := _saved_root(path)
	var fg := _saved_layer(root, "Foreground")
	check(_saved_layer(root, "Terrain").get_cell_source_id(Vector2i(6, 6)) != -1 and (fg == null or fg.get_cell_source_id(Vector2i(7, 7)) == -1), "Save writes only the ticked layers")
	root.free()
	check(view.painter.dirty and view.painter.layers["Foreground"].get_cell_source_id(Vector2i(7, 7)) != -1 and not view.painter.layers["Foreground"].visible, "the Foreground change waits, still hidden")
	view.set_layers(MDSRoomLayers.all(true))
	check(view.save() == OK and not view.painter.dirty, "ticked again, Save writes it")
	view.queue_free()
	await get_tree().process_frame
