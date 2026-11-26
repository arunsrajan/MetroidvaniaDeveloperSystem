@tool
class_name MDSHiddenLayers
extends Resource
## What a room's unticked layers hold, kept out of its scene: the Room view's Save writes only
## the layers ticked in its Layers list into the room scene (so the game, Play from here and
## Godot's 2D editor show only those), and keeps the others here, in
## [code]<scene>.mds_hidden.tres[/code] next to it ([method path_for]).
##
## [MDSRoomPainter] puts them back as it opens the room, so they can be edited again, in this
## session or the next one; a Save with their layers ticked writes them into the scene and
## deletes this file. See [method MDSRoomPainter.save_layers].

const SUFFIX := ".mds_hidden.tres"

## The layer ids ([MDSRoomLayers]) unticked when the room was saved.
@export var layers: PackedStringArray = []
## Tile layer name ("Background"...) -> its cells (TileMapLayer.tile_map_data).
@export var tiles: Dictionary = {}
## Tile layer name -> the cells of its hidden tiles ("<Layer>Blockout" layer).
@export var blockout: Dictionary = {}
## Item group ([constant MDSRoomPainter.ITEM_GROUPS]) -> the data of its items there.
@export var items: Dictionary = {}

## Where the unticked layers of the room scene [param scene_path] are kept.
static func path_for(scene_path: String) -> String:
	return scene_path.get_basename() + SUFFIX

## The unticked layers kept for [param scene_path], or null when there are none.
static func load_for(scene_path: String) -> MDSHiddenLayers:
	var path := path_for(scene_path)
	if scene_path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MDSHiddenLayers

## Whether it holds anything.
func is_empty() -> bool:
	if not tiles.is_empty() or not blockout.is_empty():
		return false
	for g in items:
		if not (items[g] as Array).is_empty():
			return false
	return true

## Writes it for [param scene_path] (or deletes the file when it holds nothing).
func save_for(scene_path: String) -> Error:
	var path := path_for(scene_path)
	if is_empty():
		return remove_for(scene_path)
	take_over_path(path)
	return ResourceSaver.save(self, path)

## Deletes the file of [param scene_path]'s unticked layers, if there is one.
static func remove_for(scene_path: String) -> Error:
	var path := path_for(scene_path)
	if scene_path.is_empty() or not FileAccess.file_exists(path):
		return OK
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err == OK and Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var fs: Object = Engine.get_singleton(&"EditorInterface").get_resource_filesystem()
		if fs:
			fs.call(&"update_file", path)
	return err
