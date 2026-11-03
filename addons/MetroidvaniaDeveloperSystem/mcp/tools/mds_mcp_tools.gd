@tool
class_name MDSMcpTools
extends RefCounted
## Base of a group of MCP tools. Tools are thin: they check what they're given and call the
## plugin's own classes, holding no game logic of their own.
##
## A handler takes (args: Dictionary, report: Callable) and returns a result Dictionary, or
## [method MDSMcpContext.fail]'s. It may await. [code]report[/code], when valid, takes
## (done, total, message).

const S := preload("res://addons/MetroidvaniaDeveloperSystem/mcp/mds_mcp_schema.gd")
const READ := MDSMcpGuard.Tier.READ
const AUTHOR := MDSMcpGuard.Tier.AUTHOR
const FULL := MDSMcpGuard.Tier.FULL

const WORLD_HELP := "World file (res://...mdsworld.json). May be left out when the editor has one open or the project has only one."
const ON_UNSAVED_HELP := "When the editor holds unsaved changes to the scene: refuse (default), or save_first, which saves them. Ask the user before save_first."

var ctx: MDSMcpContext
## Weak: the protocol holds its tools.
var protocol_ref: WeakRef

func register(p: MDSMcpProtocol) -> void:
	protocol_ref = weakref(p)
	ctx = p.ctx
	_register()

func _register() -> void:
	pass

## Adds a tool. [param properties]: its arguments, [param required]: those it must have.
## [param options]: destructive (needs confirm: true), editor_only, project_file (may write
## project.godot), writes (false: runs without a step though it isn't at the read tier).
func _add(tool_name: String, description: String, tier: MDSMcpGuard.Tier, properties: Dictionary, required: Array, handler: Callable, options: Dictionary = {}) -> void:
	var props := properties.duplicate()
	if options.get("destructive", false):
		props["confirm"] = S.boolean("Must be true: this removes something.")
	protocol_ref.get_ref().add_tool({
		"name": tool_name,
		"description": description,
		"tier": tier,
		"schema": S.object(props, required + (["confirm"] if options.get("destructive", false) else [])),
		"handler": handler,
		"destructive": options.get("destructive", false),
		"editor_only": options.get("editor_only", false),
		"project_file": options.get("project_file", false),
		"writes": options.get("writes", tier != READ),
	})

static func _world_schema() -> Dictionary:
	return S.text(WORLD_HELP)

static func _unsaved_schema() -> Dictionary:
	return S.choice(["refuse", "save_first"], ON_UNSAVED_HELP)

static func _vec2(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))

static func _rect2(value: Dictionary) -> Rect2:
	return Rect2(float(value.x), float(value.y), float(value.w), float(value.h))

static func _cells(value: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Array in value:
		if c.size() == 2:
			out.append(Vector2i(int(c[0]), int(c[1])))
	return out

## The page of [param list] from [param cursor]: {items, next_cursor when there is more}.
static func _page(list: Array, cursor: Variant, size := 100, key := "items") -> Dictionary:
	var from := clampi(int(cursor) if cursor != null else 0, 0, list.size())
	var out := {key: list.slice(from, from + size), "total": list.size()}
	if from + size < list.size():
		out.next_cursor = from + size
	return out

## The room's scene file. "" (see [member MDSMcpContext.error]) if it has none.
func _scene_of(world: MDSWorld, id: String) -> String:
	if not ctx.has_room(world, id):
		return ""
	var path := world.get_scene_path(id)
	if path.is_empty():
		ctx.error = ctx.fail("room_has_no_scene", "Room %s has no scene yet." % id, "mds_room_scene_create or mds_area_generate_caves makes one.")
	return path

## A painter on the room's scene as the file has it now. Null: see [member MDSMcpContext.error].
func _open_room(world: MDSWorld, id: String, tiles: TileSet = null) -> MDSRoomPainter:
	var path := _scene_of(world, id)
	if path.is_empty():
		return null
	var packed := MDSWorldSceneTools.load_fresh(path)
	var painter := MDSRoomPainter.open_packed(packed, path, tiles) if packed else null
	if not painter:
		ctx.error = ctx.fail("scene_not_loaded", "Could not load %s." % path)
	return painter

## A painter to change the room's scene with: see [method _save_room]. A world without a tileset
## gets one (and saves that): rooms have to paint with something.
func _edit_room(world: MDSWorld, id: String, args: Dictionary) -> MDSRoomPainter:
	var path := _scene_of(world, id)
	if path.is_empty() or not ctx.prepare_room_write(path, args):
		return null
	var tiles: TileSet
	if str(world.get_setting("room_tileset", "")).is_empty():
		var to_save := ctx.edit_world({"world": world.path})
		if not to_save:
			return null
		tiles = ctx.room_tiles(to_save)
		world.set_setting("room_tileset", to_save.get_setting("room_tileset", ""))
		var bad := ctx.save_world(to_save)
		if not bad.is_empty():
			ctx.error = bad
			return null
	else:
		tiles = ctx.room_tiles(world)
	return _open_room(world, id, tiles)

static func _default_scene_path(world: MDSWorld, id: String) -> String:
	return str(world.get_setting("scene_folder", "res://rooms")).path_join(id.to_snake_case() + ".tscn")

## Saves and closes a painter from [method _edit_room]. Returns a failure, or {}.
func _save_room(painter: MDSRoomPainter) -> Dictionary:
	var path := painter.scene_path
	var err := painter.save()
	painter.free_instance()
	if err != OK:
		return ctx.fail("save_failed", "Could not save %s: %s." % [path, MDSWorldSceneTools.last_error if not MDSWorldSceneTools.last_error.is_empty() else error_string(err)])
	MDSWorldSceneTools.load_fresh(path)
	ctx.host.room_written(path)
	return {}
