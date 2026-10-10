@tool
class_name MDSLegacy
extends RefCounted
## The names the plugin used before 3.1, from its first name, Interactive Dev Panel (IDP), so
## projects made with them keep working. Everything else in the plugin uses the MDS names; the
## old ones are only read, here:
## - node metadata and groups named [code]idp_*[/code] ([code]idp_stamp[/code],
##   [code]idp_stands[/code], [code]idp_blockout[/code]...), read like their [code]mds_*[/code]
##   names ([method has_meta_key], [method get_meta_key], [method in_group]). The Room view
##   renames them in the scenes it opens ([method upgrade_nodes]), so a save writes the new names;
## - world files named [code]*.idpworld.json[/code] or of format [code]idp_world[/code] (saved as
##   [code]mds_world[/code], under the same file name);
## - MetSys map notes in [code]MapData.idp.json[/code] (saved to [code]MapData.mds.json[/code]);
## - the [code]idp_kind[/code] custom data layer of tilesets;
## - the [code]interactive_dev_panel/*[/code] project settings (moved to
##   [code]metroidvania_developer_system/*[/code] when the plugin starts);
## - the starter tileset in [code]res://idp_tiles/[/code], the [code]idp_play_from[/code] hook of
##   a game root and the "IDP colors" tile source.

const PREFIX := "mds_"
const OLD_PREFIX := "idp_"
## Project settings section.
const SETTINGS := "metroidvania_developer_system"
const OLD_SETTINGS := "interactive_dev_panel"
const OLD_WORLD_FORMAT := "idp_world"
const OLD_WORLD_EXTENSION := ".idpworld.json"
const OLD_NOTES_EXTENSION := ".idp.json"
const OLD_KIND_LAYER := "idp_kind"
const OLD_TILESET_PATH := "res://idp_tiles/idp_cave_tileset.tres"
const OLD_EXPORT_DIR := "res://idp_exports"
const OLD_PLAY_HOOK := "idp_play_from"
const OLD_COLOR_SOURCE_NAME := "IDP colors"

# --- Metadata and groups -------------------------------------------------------------------------

## The name an [code]mds_[/code] key had before ([code]mds_blockout[/code] ->
## [code]idp_blockout[/code]); other names stay as they are.
static func old_name(key: StringName) -> StringName:
	var s := String(key)
	return StringName(OLD_PREFIX + s.substr(PREFIX.length())) if s.begins_with(PREFIX) else key

## Whether [param node] has the metadata [param key], under its MDS name or its old one.
static func has_meta_key(node: Object, key: StringName) -> bool:
	return node.has_meta(key) or node.has_meta(old_name(key))

## The metadata [param key] of [param node] (its MDS name first, then its old one), else
## [param default].
static func get_meta_key(node: Object, key: StringName, default: Variant = null) -> Variant:
	if node.has_meta(key):
		return node.get_meta(key)
	var old := old_name(key)
	return node.get_meta(old) if node.has_meta(old) else default

## Removes the metadata [param key] of [param node], under both names.
static func remove_meta_key(node: Object, key: StringName) -> void:
	if node.has_meta(key):
		node.remove_meta(key)
	var old := old_name(key)
	if node.has_meta(old):
		node.remove_meta(old)

## Whether [param node] is in [param group] or in the group's old name.
static func in_group(node: Node, group: StringName) -> bool:
	return node.is_in_group(group) or node.is_in_group(old_name(group))

## Renames the old metadata and groups of [param root] and of the nodes saved in its scene to
## their MDS names (nodes of scenes instanced in it keep theirs: their own scene has them).
## Returns how many it renamed.
static func upgrade_nodes(root: Node) -> int:
	if not root:
		return 0
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var own := n == root or (n.owner == root and n.scene_file_path.is_empty())
		if own:
			for k in n.get_meta_list():
				var s := String(k)
				if not s.begins_with(OLD_PREFIX):
					continue
				var new := StringName(PREFIX + s.substr(OLD_PREFIX.length()))
				if not n.has_meta(new):
					n.set_meta(new, n.get_meta(k))
				n.remove_meta(k)
				count += 1
			for g in n.get_groups():
				var gs := String(g)
				if gs.begins_with(OLD_PREFIX):
					n.remove_from_group(g)
					n.add_to_group(StringName(PREFIX + gs.substr(OLD_PREFIX.length())), true)
					count += 1
		stack.append_array(n.get_children())
	return count

# --- Files ---------------------------------------------------------------------------------------

## Whether [param format] (a world file's "format") is a world: the MDS one or the old one.
static func is_world_format(format: String) -> bool:
	return format == MDSWorld.FORMAT or format == OLD_WORLD_FORMAT

## [param path] without its world file extension, new or old ("res://a.mdsworld.json" ->
## "res://a").
static func trim_world_extension(path: String) -> String:
	if path.ends_with(MDSWorld.EXTENSION):
		return path.trim_suffix(MDSWorld.EXTENSION)
	return path.trim_suffix(OLD_WORLD_EXTENSION)

## The MetSys map notes beside [param map_path] in their old file, when only that one exists
## ("" otherwise).
static func old_notes_path(map_path: String, current: String) -> String:
	var old := map_path.get_basename() + OLD_NOTES_EXTENSION
	return old if not FileAccess.file_exists(current) and FileAccess.file_exists(old) else ""

## [param current], or the old starter tileset when only that one exists (a project made before
## the rename keeps using it).
static func tileset_path(current: String) -> String:
	return OLD_TILESET_PATH if current != OLD_TILESET_PATH and not ResourceLoader.exists(current) and ResourceLoader.exists(OLD_TILESET_PATH) else current

## Whether [param layer_name] is the tile kind custom data layer
## ([constant MDSTilesetFactory.KIND_LAYER], or its old name).
static func is_kind_layer(layer_name: String) -> bool:
	return layer_name == MDSTilesetFactory.KIND_LAYER or layer_name == OLD_KIND_LAYER

# --- Project settings ----------------------------------------------------------------------------

## The project setting [param key] ([code]metroidvania_developer_system/...[/code]), else the
## one it replaced ([code]interactive_dev_panel/...[/code]), else [param default].
static func get_setting(key: String, default: Variant = null) -> Variant:
	if ProjectSettings.has_setting(key):
		return ProjectSettings.get_setting(key)
	var old := OLD_SETTINGS + key.trim_prefix(SETTINGS)
	return ProjectSettings.get_setting(old) if key.begins_with(SETTINGS + "/") and ProjectSettings.has_setting(old) else default

## Moves the [code]interactive_dev_panel/*[/code] project settings to
## [code]metroidvania_developer_system/*[/code] (a setting already there wins). Returns how many
## moved; the caller saves the project settings.
static func upgrade_settings() -> int:
	var count := 0
	for p in ProjectSettings.get_property_list():
		var key := str(p.name)
		if not key.begins_with(OLD_SETTINGS + "/"):
			continue
		var new := SETTINGS + key.substr(OLD_SETTINGS.length())
		if not ProjectSettings.has_setting(new):
			ProjectSettings.set_setting(new, ProjectSettings.get_setting(key))
		ProjectSettings.set_setting(key, null)
		count += 1
	return count
