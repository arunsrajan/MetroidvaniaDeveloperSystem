extends "res://tests/test_case.gd"
## Changes made to a room's scene in the editor (the 2D editor, the Inspector) show in the Room
## view: MDSRoomView.sync_from_scene() takes in the scene as the editor has it (the editor calls
## it a moment after each change there, and before the Room view saves).
## - nothing unsaved in the Room view: it shows the scene as it is now: a stamp moved, a tile
##   painted, an effect removed, a stamp added; the view and the selection stay;
## - with changes not saved yet in the Room view: both are kept, merged tile by tile and item by
##   item; where both changed the same tile, the editor's change wins; undo undoes the Room
##   view's own changes, not the editor's; saving writes them all;
## - no change in the editor: nothing happens;
## - the Room view's items go on as the same objects, changed in place, never leaving the tree:
##   the Inspector showing one keeps showing it (it lets go of a node that leaves the tree, and
##   a new object would show its sections folded), and a sync never takes the Inspector over.
## (Headless there is no editor: the test changes a copy of the scene, as the editor's scene tab
## would have it.)

const ROOM := TMP + "/editor_sync_room.tscn"
const TILES := TMP + "/editor_sync_tiles.tres"
const STAMPS := "res://asset_packs/mossgrove/freeform/mossgrove.stamps.tres"

var view: MDSRoomView
var stamps: MDSStampSet
## The scene open in the "editor": changed there between the syncs, as a scene tab is.
var live: Node

func _run() -> void:
	stamps = load(STAMPS)
	_make_room()
	var world := MDSWorld.new()
	world.path = TMP + "/editor_sync.mdsworld.json"
	world.add_room("Hall", Rect2(0, 0, 1152, 648))
	world.set_room_scene("Hall", ROOM)
	view = MDSRoomView.new()
	view.size = Vector2(1300, 800)
	add_child(view)
	await get_tree().process_frame
	check(view.open_room(world, "Hall").is_empty(), "the Room view opens the room")
	live = _live()
	_clean()
	_unsaved()
	_saved()
	live.free()
	view.close_room(false)
	view.queue_free()
	await get_tree().process_frame

func _make_room() -> void:
	var ts := MDSTilesetFactory.get_or_create(TILES)
	var root := Node2D.new()
	root.name = "SyncRoom"
	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = ts
	root.add_child(terrain)
	for x in 10:
		terrain.set_cell(Vector2i(x, 15), 0, Vector2i(0, 0))
	var front := Node2D.new()
	front.name = "StampsFront"
	root.add_child(front)
	var s := stamps.make_sprite(0)
	s.name = "Moss"
	s.position = Vector2(200, 400)
	front.add_child(s)
	var shapes := Node2D.new()
	shapes.name = "Freeform"
	root.add_child(shapes)
	var f := MDSFreeform.new()
	f.name = "Ledge"
	f.points = PackedVector2Array([Vector2(500, 300), Vector2(700, 300), Vector2(700, 340), Vector2(500, 340)])
	shapes.add_child(f)
	var enemy := Node2D.new()
	enemy.name = "Enemy"
	enemy.position = Vector2(900, 450)
	root.add_child(enemy)
	var effects := Node2D.new()
	effects.name = "Effects"
	root.add_child(effects)
	var rain := MDSEnvironment.create("rain")
	rain.name = "Rain"
	effects.add_child(rain)
	save_scene(root, ROOM)
	root.free()
	load_fresh(ROOM)

## The scene as the editor would have it: opened from its file, owned for packing.
func _live() -> Node:
	return (load_fresh(ROOM) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)

func _item(group: String, item_name: String) -> Node2D:
	for n in view.painter.items(group):
		if String(n.name) == item_name:
			return n
	return null

func _clean() -> void:
	var canvas := view.canvas
	canvas.zoom = 0.75
	canvas.pan = Vector2(30, 40)
	canvas._apply_view()
	canvas.set_selection([_item("Freeform", "Ledge")])
	var ledge := _item("Freeform", "Ledge")
	var moss := _item("StampsFront", "Moss")
	var exits := [0]
	for n in [ledge, moss]:
		n.tree_exiting.connect(func() -> void: exits[0] += 1)
	var inspected: Array = []
	# (Null, nothing selected while the room is opened anew, shows nothing.)
	canvas.effect_selected.connect(func(e: MDSEnvironmentEffect) -> void:
		if e:
			inspected.append(e))
	(live.get_node("StampsFront/Moss") as Node2D).position = Vector2(260, 380)
	(live.get_node("Terrain") as TileMapLayer).set_cell(Vector2i(4, 10), 0, Vector2i(1, 0))
	var rain := live.get_node("Effects/Rain")
	rain.get_parent().remove_child(rain)
	rain.free()
	var added := stamps.make_sprite(1)
	added.name = "Fern"
	added.position = Vector2(800, 420)
	live.get_node("StampsFront").add_child(added)
	added.owner = live
	check(view.sync_from_scene(live), "a change in the editor is taken in")
	var p := view.painter
	check(_item("StampsFront", "Moss") != null and _item("StampsFront", "Moss").position == Vector2(260, 380), "a stamp moved there is moved here")
	check(p.layers["Terrain"].get_cell_source_id(Vector2i(4, 10)) == 0 and p.layers["Terrain"].get_cell_atlas_coords(Vector2i(4, 10)) == Vector2i(1, 0), "a tile painted there is painted here")
	check(p.effects().is_empty(), "an effect removed there is gone here")
	check(_item("StampsFront", "Fern") != null, "a stamp added there is here")
	check(not p.dirty, "nothing to save: it is the scene as it is")
	check(is_equal_approx(canvas.zoom, 0.75) and canvas.pan == Vector2(30, 40), "the view stays where it was")
	check(canvas.selection.size() == 1 and canvas.selection[0] == _item("Freeform", "Ledge"), "and so does the selection")
	check(not view.sync_from_scene(live), "the same scene again changes nothing")
	check(_item("Freeform", "Ledge") == ledge and _item("StampsFront", "Moss") == moss and exits[0] == 0, "the items go on as the same objects, never leaving the tree (%d left it)" % exits[0])
	check(inspected.is_empty(), "and the sync sent nothing to the Inspector")
	# A node that is no tile or item (an enemy) moved there: the Room view shows it moved.
	(live.get_node("Enemy") as Node2D).position = Vector2(950, 420)
	check(view.sync_from_scene(live), "an enemy moved in the editor is taken in")
	var shown := canvas._display_scene.get_node_or_null("Enemy") as Node2D
	check(shown != null and shown.position == Vector2(950, 420), "and shown moved")

func _unsaved() -> void:
	var p := view.painter
	# Here, not saved yet: a tile painted, one changed, the ledge moved.
	p.checkpoint()
	p.layers["Terrain"].set_cell(Vector2i(20, 12), 0, Vector2i(2, 0))
	p.layers["Terrain"].set_cell(Vector2i(0, 15), 0, Vector2i(3, 0))
	_item("Freeform", "Ledge").position = Vector2(0, -60)
	p.dirty = true
	# There: the same tile changed differently, another one painted, the moss moved again.
	var terrain := live.get_node("Terrain") as TileMapLayer
	terrain.set_cell(Vector2i(4, 10), 0, Vector2i(1, 0))
	terrain.set_cell(Vector2i(0, 15), 0, Vector2i(5, 0))
	terrain.set_cell(Vector2i(30, 5), 0, Vector2i(6, 0))
	(live.get_node("StampsFront/Moss") as Node2D).position = Vector2(300, 360)
	check(view.sync_from_scene(live), "a change in the editor is taken in while the Room view has changes not saved")
	p = view.painter
	var t: TileMapLayer = p.layers["Terrain"]
	check(t.get_cell_atlas_coords(Vector2i(20, 12)) == Vector2i(2, 0), "the tile painted here stays")
	check(t.get_cell_atlas_coords(Vector2i(30, 5)) == Vector2i(6, 0), "the one painted there comes in")
	check(t.get_cell_atlas_coords(Vector2i(0, 15)) == Vector2i(5, 0), "a tile changed on both sides: the editor's change wins")
	check(_item("Freeform", "Ledge").position == Vector2(0, -60), "the ledge moved here stays moved")
	check(_item("StampsFront", "Moss").position == Vector2(300, 360), "the moss moved there is moved")
	check(p.dirty, "and there is something to save")
	check(p.undo(), "undo")
	t = p.layers["Terrain"]
	check(t.get_cell_source_id(Vector2i(20, 12)) == -1 and _item("Freeform", "Ledge").position == Vector2.ZERO, "undo undoes the Room view's changes")
	check(t.get_cell_atlas_coords(Vector2i(30, 5)) == Vector2i(6, 0) and _item("StampsFront", "Moss").position == Vector2(300, 360), "not the editor's")
	check(p.redo(), "redo")
	check(p.layers["Terrain"].get_cell_atlas_coords(Vector2i(20, 12)) == Vector2i(2, 0) and _item("Freeform", "Ledge").position == Vector2(0, -60), "redo does them again")

func _saved() -> void:
	check(view.save() == OK, "the room saves")
	var root := _live()
	var t := root.get_node("Terrain") as TileMapLayer
	check(t.get_cell_atlas_coords(Vector2i(20, 12)) == Vector2i(2, 0) and t.get_cell_atlas_coords(Vector2i(30, 5)) == Vector2i(6, 0) and t.get_cell_atlas_coords(Vector2i(4, 10)) == Vector2i(1, 0), "the scene has the tiles of both")
	check((root.get_node("StampsFront/Moss") as Node2D).position == Vector2(300, 360) and (root.get_node("Freeform/Ledge") as Node2D).position == Vector2(0, -60) and root.has_node("StampsFront/Fern") and not root.has_node("Effects/Rain"), "and the items of both")
	check((root.get_node("Enemy") as Node2D).position == Vector2(950, 420), "and the editor's other changes")
	root.free()
