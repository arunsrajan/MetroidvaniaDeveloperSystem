@tool
class_name MDSMcpToolsObjects
extends MDSMcpTools
## Everything the plugin has that is set up through exports: any of its resources (items,
## abilities, equipment, enemy data, attacks, dialogue, shops, movement, moves, styles...) and any
## of its nodes in any scene (pickups, doors, NPCs, weather, backgrounds, cameras, the game itself).
## The tools read a class's exports, so a project's own class extending one of these works too.

const RESOURCE_EXTENSIONS: PackedStringArray = ["tres", "res"]
const SET_HELP := "Property -> value. Vectors [x, y], colors #rrggbb, enums by name, a resource as a res:// path or {class, set}, a node as its path in the scene. mds_class_info lists a class's properties."
const META_NAME := "^[A-Za-z_][A-Za-z0-9_]*$"
const LONGEST_TREE := 200

func _register() -> void:
	var where := _where_schema()
	_add("mds_class_list", "The classes that resources and nodes can be made of, with what each extends. kind: node or resource. base: only those extending this class. contains: only names with this in them.", READ,
		{"kind": S.choice(["node", "resource"]), "base": S.text(), "contains": S.text()}, [], _class_list)
	_add("mds_class_info", "A class's properties: name, type, default, and the choices of an enum. native adds what Godot's own class has, such as a node's position.", READ,
		{"class": S.text(), "native": S.boolean("Default false")}, ["class"], _class_info)
	_add("mds_resource_create", "Makes a resource file of a class: an item, ability, enemy data, dialogue, shop, movement config, move, style...", AUTHOR,
		{"path": S.text("res://....tres"), "class": S.text(), "set": S.any_object(SET_HELP), "overwrite": S.boolean("Default false")}, ["path", "class"], _resource_create)
	_add("mds_resource_copy", "Copies a resource file, such as a ready-made ability under addons/, to make your own from.", AUTHOR,
		{"from": S.text(), "path": S.text("res://....tres"), "overwrite": S.boolean("Default false")}, ["from", "path"], _resource_copy)
	_add("mds_resource_get", "A resource file: its class, and the properties that differ from the class's defaults.", READ, {"path": S.text()}, ["path"], _resource_get)
	_add("mds_resource_update", "Sets properties of a resource file.", AUTHOR, {"path": S.text(), "set": S.any_object(SET_HELP)}, ["path", "set"], _resource_update)
	_add("mds_resource_find", "The resource files of a class or anything extending it, anywhere in the project. Paged.", READ,
		{"class": S.text(), "folder": S.text("Default res://"), "cursor": S.integer("", 0)}, ["class"], _resource_find)
	_add("mds_scene_create", "Makes a scene: a root of a class, or a scene that inherits from another, such as your own enemy from a template.", AUTHOR,
		{"path": S.text("res://....tscn"), "class": S.text("The root's class"), "inherits": S.text("Or a scene to inherit from"), "name": S.text(), "set": S.any_object(SET_HELP)}, ["path"], _scene_create)
	_add("mds_scene_tree", "The nodes of a room's scene or any scene, with their paths and classes. Paged.", READ,
		where.merged({"node": S.text("Only under this node"), "depth": S.integer("Levels down, default all", 1), "cursor": S.integer("", 0)}), [], _scene_tree)
	_add("mds_node_get", "A node of a scene: class, position, groups, metadata, and the properties that differ from its class's defaults.", READ,
		where.merged({"node": S.text("Path from the scene's root; . is the root")}), ["node"], _node_get)
	_add("mds_node_add", "Adds a node to a scene: a new one of a class, or an instance of a scene. mds_class_list has the classes.", AUTHOR,
		where.merged({
			"class": S.text(), "instance": S.text("Or a scene, res://....tscn"), "parent": S.text("Default the root"), "name": S.text(), "pos": S.point("In its parent"),
			"set": S.any_object(SET_HELP), "groups": S.array(S.text()), "meta": S.any_object("Metadata, such as mds_grants"), "on_unsaved": _unsaved_schema(),
		}), [], _node_add)
	_add("mds_node_update", "Changes a node of a scene: properties, name, position, parent, order among its siblings, groups, metadata (null removes a key).", AUTHOR,
		where.merged({
			"node": S.text(), "set": S.any_object(SET_HELP), "name": S.text(), "pos": S.point("In its parent"), "parent": S.text("Moves it there"), "index": S.integer("Among its siblings", 0),
			"groups_add": S.array(S.text()), "groups_remove": S.array(S.text()), "meta": S.any_object(), "on_unsaved": _unsaved_schema(),
		}), ["node"], _node_update)
	_add("mds_node_remove", "Removes a node from a scene, with what is under it.", AUTHOR, where.merged({"node": S.text(), "on_unsaved": _unsaved_schema()}), ["node"], _node_remove, {"destructive": true})

## The arguments that say which scene: a room's, or a file.
static func _where_schema() -> Dictionary:
	return {"world": _world_schema(), "room": S.text("A room, for its scene"), "scene": S.text("Or a scene file, res://....tscn")}

func _class_list(args: Dictionary, _report: Callable) -> Dictionary:
	var all := MDSMcpValues.classes()
	var out := []
	for name: String in all:
		var c: Dictionary = all[name]
		if args.has("kind") and c.kind != args.kind:
			continue
		if args.has("contains") and not name.containsn(args.contains):
			continue
		if args.has("base") and not _extends(name, args.base, all):
			continue
		out.append({"class": name, "base": c.base, "kind": c.kind})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["class"] < b["class"])
	var native := {}
	if not args.has("base") and not args.has("contains"):
		if args.get("kind", "node") == "node":
			native.nodes = MDSMcpValues.NATIVE_NODES
		if args.get("kind", "resource") == "resource":
			native.resources = MDSMcpValues.NATIVE_RESOURCES
	return {"classes": out, "godot_classes": native}

static func _extends(name: String, base: String, all: Dictionary) -> bool:
	var at := name
	while all.has(at):
		if at == base:
			return true
		at = all[at].base
	return at == base

func _class_info(args: Dictionary, _report: Callable) -> Dictionary:
	var out := MDSMcpValues.describe(args["class"], args.get("native", false))
	if out.is_empty():
		return ctx.fail("bad_class", "%s is not a class tools can make." % args["class"], "mds_class_list lists them.")
	return out

# --- Resources -------------------------------------------------------------------------------

## The file a resource goes in. "" (see [member MDSMcpContext.error]) if it can't be written.
func _new_resource_path(args: Dictionary) -> String:
	var path := MDSMcpGuard.normalize(str(args.path))
	if path.is_empty() or not path.get_extension() in RESOURCE_EXTENSIONS:
		ctx.error = ctx.fail("bad_arguments", "%s must be a .tres or .res path inside res://." % args.path)
		return ""
	if FileAccess.file_exists(path) and not args.get("overwrite", false):
		ctx.error = ctx.fail("already_exists", "%s already exists." % path, "Pass overwrite: true to replace it.")
		return ""
	if not ctx.touch(path):
		return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return path

func _save_resource(res: Resource, path: String) -> Dictionary:
	res.take_over_path(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return ctx.fail("save_failed", "Could not save %s: %s." % [path, error_string(err)])
	ctx.host.resource_written(path)
	return {}

func _resource_create(args: Dictionary, _report: Callable) -> Dictionary:
	if not MDSMcpValues.can_make(args["class"], "resource"):
		return ctx.fail("bad_class", "%s is not a resource class tools can make." % args["class"], "mds_class_list with kind resource lists them.")
	var path := _new_resource_path(args)
	if path.is_empty():
		return ctx.error
	var res := MDSMcpValues.make(args["class"]) as Resource
	var values := MDSMcpValues.new()
	if not values.set_all(res, args.get("set", {})):
		return ctx.fail("bad_value", values.error, "mds_class_info lists its properties.")
	var bad := _save_resource(res, path)
	return bad if not bad.is_empty() else {"path": path, "class": args["class"]}

func _resource_copy(args: Dictionary, _report: Callable) -> Dictionary:
	var from := MDSMcpGuard.normalize(str(args.from))
	if from.is_empty() or not from.get_extension() in RESOURCE_EXTENSIONS or not FileAccess.file_exists(from):
		return ctx.fail("not_found", "%s isn't a resource file in the project." % args.from)
	var path := _new_resource_path(args)
	if path.is_empty():
		return ctx.error
	var res := (ResourceLoader.load(from, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource)
	if not res:
		return ctx.fail("not_loaded", "Could not load %s." % from)
	var bad := _save_resource(res.duplicate(true), path)
	return bad if not bad.is_empty() else {"path": path, "from": from}

## The resource file [param args] names, as it is now. Null: see [member MDSMcpContext.error].
func _open_resource(path_arg: String) -> Resource:
	var path := MDSMcpGuard.normalize(path_arg)
	if path.is_empty() or not path.get_extension() in RESOURCE_EXTENSIONS or not FileAccess.file_exists(path):
		ctx.error = ctx.fail("not_found", "%s isn't a resource file in the project." % path_arg, "mds_resource_find finds them.")
		return null
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Resource
	if not res:
		ctx.error = ctx.fail("not_loaded", "Could not load %s." % path)
	return res

func _resource_get(args: Dictionary, _report: Callable) -> Dictionary:
	var res := _open_resource(args.path)
	if not res:
		return ctx.error
	return {"path": res.resource_path, "class": MDSMcpValues.class_of(res), "values": MDSMcpValues.new().changed_values(res)}

func _resource_update(args: Dictionary, _report: Callable) -> Dictionary:
	var res := _open_resource(args.path)
	if not res:
		return ctx.error
	var path := res.resource_path
	if not ctx.touch(path):
		return ctx.error
	var values := MDSMcpValues.new()
	if not values.set_all(res, args.set):
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		return ctx.fail("bad_value", values.error, "mds_class_info lists its properties.")
	var err := ResourceSaver.save(res, path)
	if err != OK:
		return ctx.fail("save_failed", "Could not save %s: %s." % [path, error_string(err)])
	ctx.host.resource_written(path)
	return {"path": path, "set": args.set.keys()}

func _resource_find(args: Dictionary, _report: Callable) -> Dictionary:
	var folder := MDSMcpGuard.normalize(str(args.get("folder", "res://")))
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return ctx.fail("not_found", "%s isn't a folder in the project." % args.get("folder", ""))
	var all := MDSMcpValues.classes()
	var found := []
	for path in _text_resources(folder):
		var head := _class_in_header(path)
		if not head.is_empty() and _extends(head, args["class"], all):
			found.append({"path": path, "class": head})
	return _page(found, args.get("cursor"), 100, "resources")

static func _text_resources(folder: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(folder):
		if f.get_extension() == "tres":
			out.append(folder.path_join(f))
	for d in DirAccess.get_directories_at(folder):
		if not d.begins_with("."):
			out.append_array(_text_resources(folder.path_join(d)))
	return out

## The class a text resource says it is, from its first line, without loading it.
static func _class_in_header(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var line := f.get_line()
	for key in ["script_class=\"", "type=\""]:
		var at := line.find(key)
		if at >= 0:
			return line.substr(at + key.length()).get_slice("\"", 0)
	return ""

# --- Scenes and nodes ------------------------------------------------------------------------

## The scene [param args] means: "scene", or a "room" of a "world". "": see [member MDSMcpContext.error].
func _scene_path(args: Dictionary) -> String:
	if args.has("scene"):
		var p := MDSMcpGuard.normalize(str(args.scene))
		if p.is_empty() or not p.get_extension() in ["tscn", "scn"] or not FileAccess.file_exists(p):
			ctx.error = ctx.fail("not_found", "%s isn't a scene in the project." % args.scene)
			return ""
		return p
	if not args.has("room"):
		ctx.error = ctx.fail("bad_arguments", "Give room, or scene.")
		return ""
	var world := ctx.read_world(args)
	return _scene_of(world, args.room) if world else ""

## The scene at [param path] to look at or change: {packed, root}. Empty: see [member MDSMcpContext.error].
func _open_scene(path: String) -> Dictionary:
	var packed := MDSWorldSceneTools.load_fresh(path)
	var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if packed else null
	if not root:
		ctx.error = ctx.fail("scene_not_loaded", "Could not load %s." % path)
		return {}
	MDSLegacy.upgrade_nodes(root)
	return {"packed": packed, "root": root, "path": path}

## The scene [param args] means, to change. Empty: see [member MDSMcpContext.error].
func _edit_scene(args: Dictionary) -> Dictionary:
	var path := _scene_path(args)
	if path.is_empty() or not ctx.prepare_room_write(path, args):
		return {}
	return _open_scene(path)

## Saves a scene from [method _edit_scene] and frees it. Returns a failure, or {}.
func _save_scene(opened: Dictionary) -> Dictionary:
	var err := MDSWorldSceneTools.repack_safely(opened.root, opened.packed, opened.path)
	opened.root.free()
	if err != OK:
		return ctx.fail("save_failed", MDSWorldSceneTools.last_error if not MDSWorldSceneTools.last_error.is_empty() else "Could not save %s: %s." % [opened.path, error_string(err)])
	MDSWorldSceneTools.load_fresh(opened.path)
	ctx.host.room_written(opened.path)
	return {}

## Frees a scene from [method _edit_scene] without saving, and returns [param failure].
static func _drop_scene(opened: Dictionary, failure: Dictionary) -> Dictionary:
	opened.root.free()
	return failure

func _scene_create(args: Dictionary, _report: Callable) -> Dictionary:
	var path := MDSMcpGuard.normalize(str(args.path))
	if path.is_empty() or path.get_extension() != "tscn":
		return ctx.fail("bad_arguments", "%s must be a .tscn path inside res://." % args.path)
	if args.has("class") == args.has("inherits"):
		return ctx.fail("bad_arguments", "Give class, or inherits.")
	if FileAccess.file_exists(path):
		return ctx.fail("already_exists", "%s already exists." % path)
	if not ctx.touch(path):
		return ctx.error
	var root: Node
	if args.has("inherits"):
		var base := MDSGuardedLoad.scene(str(args.inherits))
		if not base:
			return ctx.fail("not_found", "%s isn't a scene in the project." % args.inherits)
		root = base.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
	elif MDSMcpValues.can_make(args["class"], "node"):
		root = MDSMcpValues.make(args["class"]) as Node
	if not root:
		return ctx.fail("bad_class", "%s can't be the root of a scene." % args.get("class", args.get("inherits")), "mds_class_list with kind node lists the classes.")
	root.name = str(args.get("name", path.get_file().get_basename().to_pascal_case()))
	var values := MDSMcpValues.new()
	values.scene_root = root
	if not values.set_all(root, args.get("set", {})):
		root.free()
		return ctx.fail("bad_value", values.error, "mds_class_info lists its properties.")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var out := PackedScene.new()
	var err := out.pack(root)
	if err == OK:
		err = ResourceSaver.save(out, path)
	root.free()
	if err != OK:
		return ctx.fail("save_failed", "Could not save %s: %s." % [path, error_string(err)])
	MDSWorldSceneTools.load_fresh(path)
	ctx.host.room_written(path)
	return {"scene": path}

func _scene_tree(args: Dictionary, _report: Callable) -> Dictionary:
	var path := _scene_path(args)
	if path.is_empty():
		return ctx.error
	var opened := _open_scene(path)
	if opened.is_empty():
		return ctx.error
	var root: Node = opened.root
	var from: Node = root.get_node_or_null(NodePath(str(args.get("node", "."))))
	if not from:
		return _drop_scene(opened, ctx.fail("node_not_found", "%s has no node %s." % [path, args.node]))
	var out := []
	_list_nodes(from, root, int(args.get("depth", 0)), 0, out)
	var page := _page(out, args.get("cursor"), LONGEST_TREE, "nodes")
	page.scene = path
	root.free()
	return page

static func _list_nodes(node: Node, root: Node, depth: int, level: int, out: Array) -> void:
	var entry := {"node": str(root.get_path_to(node)), "class": MDSMcpValues.class_of(node)}
	if node is Node2D:
		entry.pos = (node as Node2D).position
	if node != root and not node.scene_file_path.is_empty():
		entry.instance = node.scene_file_path
	if node is TileMapLayer:
		entry.tiles = (node as TileMapLayer).get_used_cells().size()
	out.append(entry)
	if depth > 0 and level >= depth:
		return
	for c in node.get_children():
		if c.owner == root or (c.owner == null and node == root):
			_list_nodes(c, root, depth, level + 1, out)

func _node_get(args: Dictionary, _report: Callable) -> Dictionary:
	var path := _scene_path(args)
	if path.is_empty():
		return ctx.error
	var opened := _open_scene(path)
	if opened.is_empty():
		return ctx.error
	var root: Node = opened.root
	var node := root.get_node_or_null(NodePath(args.node))
	if not node:
		return _drop_scene(opened, ctx.fail("node_not_found", "%s has no node %s." % [path, args.node], "mds_scene_tree lists them."))
	var values := MDSMcpValues.new()
	values.scene_root = root
	var out := {"scene": path, "node": str(root.get_path_to(node)), "class": MDSMcpValues.class_of(node), "groups": node.get_groups().filter(func(g: StringName) -> bool: return not String(g).begins_with("_")), "values": values.changed_values(node)}
	if node is Node2D:
		out.pos = (node as Node2D).position
	if node != root and not node.scene_file_path.is_empty():
		out.instance = node.scene_file_path
	var meta := {}
	for key in node.get_meta_list():
		if not String(key).begins_with("_"):
			meta[String(key)] = values.encode(node.get_meta(key))
	if not meta.is_empty():
		out.meta = meta
	root.free()
	return out

## Applies metadata to [param node]: null removes a key. Returns why not, or "".
static func _apply_meta(node: Node, meta: Dictionary) -> String:
	var name_rule := RegEx.create_from_string(META_NAME)
	for key: String in meta:
		if not name_rule.search(key):
			return "%s is not a metadata name." % key
		if meta[key] == null:
			if node.has_meta(key):
				node.remove_meta(key)
		else:
			node.set_meta(key, meta[key])
	return ""

func _node_add(args: Dictionary, _report: Callable) -> Dictionary:
	if args.has("class") == args.has("instance"):
		return ctx.fail("bad_arguments", "Give class, or instance.")
	if args.has("class") and not MDSMcpValues.can_make(args["class"], "node"):
		return ctx.fail("bad_class", "%s is not a node class tools can make." % args["class"], "mds_class_list with kind node lists them.")
	var instance: PackedScene = null
	if args.has("instance"):
		instance = MDSGuardedLoad.scene(str(args.instance))
		if not instance:
			return ctx.fail("not_found", "%s isn't a scene in the project." % args.instance)
	var opened := _edit_scene(args)
	if opened.is_empty():
		return ctx.error
	var root: Node = opened.root
	var parent := root.get_node_or_null(NodePath(str(args.get("parent", "."))))
	if not parent:
		return _drop_scene(opened, ctx.fail("node_not_found", "The scene has no node %s." % args.parent, "mds_scene_tree lists them."))
	if opened.path == str(args.get("instance", "")):
		return _drop_scene(opened, ctx.fail("bad_arguments", "A scene can't hold itself."))
	var node: Node = instance.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if instance else MDSMcpValues.make(args["class"]) as Node
	if not node:
		return _drop_scene(opened, ctx.fail("not_made", "Could not make it."))
	node.name = str(args.get("name", instance.resource_path.get_file().get_basename().to_pascal_case() if instance else str(args["class"]).trim_prefix("MDS")))
	parent.add_child(node, true)
	node.owner = root
	var problem := _apply_common(node, root, args)
	if not problem.is_empty():
		return _drop_scene(opened, ctx.fail("bad_value", problem, "mds_class_info lists its properties."))
	for g: String in args.get("groups", []):
		node.add_to_group(g, true)
	var at := str(root.get_path_to(node))
	var bad := _save_scene(opened)
	return bad if not bad.is_empty() else {"scene": opened.path, "node": at}

## What adding and changing a node share: properties, position, metadata. Returns why not, or "".
static func _apply_common(node: Node, root: Node, args: Dictionary) -> String:
	var values := MDSMcpValues.new()
	values.scene_root = root
	if not values.set_all(node, args.get("set", {})):
		return values.error
	if args.has("pos"):
		if not node is Node2D:
			return "%s isn't a 2D node: it has no position." % node.name
		(node as Node2D).position = _vec2(args.pos)
	return _apply_meta(node, args.get("meta", {}))

func _node_update(args: Dictionary, _report: Callable) -> Dictionary:
	var opened := _edit_scene(args)
	if opened.is_empty():
		return ctx.error
	var root: Node = opened.root
	var node := root.get_node_or_null(NodePath(args.node))
	if not node:
		return _drop_scene(opened, ctx.fail("node_not_found", "The scene has no node %s." % args.node, "mds_scene_tree lists them."))
	var problem := _apply_common(node, root, args)
	if not problem.is_empty():
		return _drop_scene(opened, ctx.fail("bad_value", problem, "mds_class_info lists its properties."))
	for g: String in args.get("groups_add", []):
		node.add_to_group(g, true)
	for g: String in args.get("groups_remove", []):
		node.remove_from_group(g)
	if args.has("parent"):
		var parent := root.get_node_or_null(NodePath(args.parent))
		if not parent or node == root or node == parent or node.is_ancestor_of(parent):
			return _drop_scene(opened, ctx.fail("bad_arguments", "%s can't go under %s." % [args.node, args.parent]))
		node.reparent(parent, false)
		_own_again(node, root)
	if args.has("index"):
		if node == root:
			return _drop_scene(opened, ctx.fail("bad_arguments", "The root has no siblings."))
		node.get_parent().move_child(node, mini(int(args.index), node.get_parent().get_child_count() - 1))
	if args.has("name"):
		if node != root and node.get_parent().has_node(NodePath(str(args.name))):
			return _drop_scene(opened, ctx.fail("already_exists", "Its parent already has a node %s." % args.name))
		node.name = str(args.name)
	var at := str(root.get_path_to(node))
	var bad := _save_scene(opened)
	return bad if not bad.is_empty() else {"scene": opened.path, "node": at}

## Reparenting clears owners below what moved. Nodes of an instanced scene keep theirs.
static func _own_again(node: Node, root: Node) -> void:
	node.owner = root
	if not node.scene_file_path.is_empty():
		return
	for c in node.get_children():
		_own_again(c, root)

func _node_remove(args: Dictionary, _report: Callable) -> Dictionary:
	var opened := _edit_scene(args)
	if opened.is_empty():
		return ctx.error
	var root: Node = opened.root
	var node := root.get_node_or_null(NodePath(args.node))
	if not node or node == root:
		return _drop_scene(opened, ctx.fail("node_not_found", "%s isn't a node that can be removed." % args.node, "mds_scene_tree lists them."))
	node.get_parent().remove_child(node)
	node.free()
	var bad := _save_scene(opened)
	return bad if not bad.is_empty() else {"scene": opened.path, "removed": args.node}

## Loading a scene the arguments name, from inside the project only.
class MDSGuardedLoad:
	static func scene(path: String) -> PackedScene:
		var p := MDSMcpGuard.normalize(path)
		if p.is_empty() or not p.get_extension() in ["tscn", "scn"] or not FileAccess.file_exists(p):
			return null
		return load(p) as PackedScene
