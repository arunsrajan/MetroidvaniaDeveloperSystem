@tool
class_name MDSMcpToolsTerrain
extends MDSMcpTools
## The Room view's terrain that isn't plain tile painting: painted shapes, freeform shapes, Convert
## to freeform, Decorate freeform, Trace drawing, tile pieces, tidying a room, and tilesets' sheets.
## Everything goes through [MDSRoomPainter], as the Room view does.

const CURVES: PackedStringArray = ["convex", "concave", "slope", "rounded", "quarter_pipe", "s_curve", "hill", "mesa", "wave", "steps", "spikes"]
const SHAPES: PackedStringArray = ["rect", "irregular", "left", "right", "top", "bottom"]
const STRUCTURES: PackedStringArray = ["column", "arch", "garden_wall", "mound", "stalactites"]
const FREEFORM_GROUPS: PackedStringArray = ["Freeform", "FreeformBack", "FreeformFront"]
const TRACE_LAYERS: PackedStringArray = ["ignore", "terrain", "platform", "background", "foreground"]
const TRACE_OUTPUTS: PackedStringArray = ["styles", "colors", "tiles", "picture"]
const STYLE_HELP := "A freeform style: a res://....tres path, or {class, set}. mds_catalog freeform_styles lists those in the project."
const MOST_CELLS := 250000

func _register() -> void:
	var world := _world_schema()
	var unsaved := _unsaved_schema()
	var room := {"world": world, "room": S.text(), "on_unsaved": unsaved}
	_add("mds_room_paint_shape", "Paints a shape of tiles in the box between two cells, like the Room view's shape brushes. The curved shapes have one curved face. curve and count shape it, rough makes the face irregular. op and its values as in mds_room_paint.", AUTHOR,
		room.merged({
			"layer": S.choice(Array(MDSRoomPainter.LAYER_ORDER)), "op": S.choice(["terrain", "kind", "fill", "erase"]), "shape": S.choice(Array(SHAPES)), "a": S.array(S.integer(), "[x, y] tile cell", 2), "b": S.array(S.integer(), "[x, y] tile cell", 2),
			"curve": S.choice(Array(CURVES)), "rough": S.number("", 0, 1), "mirror": S.boolean(), "count": S.integer("Waves, steps or spikes", 1), "seed": S.integer(), "set": S.integer("", 0), "terrain": S.integer("", 0), "kind": S.text(), "fill": S.any_object(),
		}), ["room", "layer", "op", "shape", "a", "b"], _paint_shape)
	_add("mds_room_freeform_add", "Adds a freeform shape to a room: smooth terrain, a ledge, scenery. From points, or a ready-made structure in box. After that it is a node: mds_node_update changes its points, style, role and the rest.", AUTHOR,
		room.merged({
			"points": S.array(S.array(S.number(), "", 2), "[x, y] in scene pixels"), "structure": S.choice(Array(STRUCTURES)), "box": S.rect("Scene pixels, for structure"), "style": S.any_object(STYLE_HELP), "style_path": S.text("Or the style's path"),
			"group": S.choice(Array(FREEFORM_GROUPS), "Default Freeform"), "solid": S.boolean("Default true"), "smooth": S.boolean(), "seed": S.integer(),
		}), ["room"], _freeform_add)
	_add("mds_room_freeform_repair", "Untwists freeform shapes whose outlines cross themselves: all of the room's, or node.", AUTHOR, room.merged({"node": S.text()}), ["room"], _freeform_repair)
	_add("mds_room_convert", "Convert to freeform: a room blocked out with tiles, collision or straight shapes becomes organic terrain with the same floors and doorways. Report says what it made and any warnings.", AUTHOR,
		room.merged({
			"rock_style": S.text(STYLE_HELP), "ledge_style": S.text(), "back_style": S.text("Background tiles become this. Left out: they stay tiles"), "front_style": S.text("Foreground tiles become this. Left out: they stay tiles"), "fill_outside": S.text("A style that fills what is outside the room's shape"),
			"growth": S.number("0 only rounds corners, 1 normal, 2 wild", 0, 2), "bowl_radius": S.number("", 0), "lip_radius": S.number("", 0), "margin": S.number("", 0), "seed": S.integer(), "keep_old": S.boolean("Default true: old terrain stays hidden. False removes it"), "include_blockout": S.boolean("Default true"),
		}), ["room"], _convert)
	_add("mds_room_fill_outside", "Fills the parts of a room's box outside its shape with a non-solid style. Running it again replaces them.", AUTHOR,
		room.merged({"style": S.text("res://....tres")}), ["room", "style"], _fill_outside)
	_add("mds_room_decorate_freeform", "Decorate freeform: hanging plants, floor plants, structures and framing placed relative to the room's rock, away from doorways and objects. The same seed gives the same room, and running it again replaces it.", AUTHOR,
		room.merged({
			"stamp_set": S.text("res://....stamps.tres"), "hanging": S.boolean("Default true"), "hanging_category": S.text(), "floor_plants": S.boolean("Default true"), "floor_categories": S.array(S.text()),
			"structures": S.boolean("Default true"), "structure_kinds": S.array(S.choice(Array(STRUCTURES))), "structure_style": S.text(), "leaf_category": S.text(), "foreground": S.boolean("Default true"), "foreground_style": S.text(), "density": S.number("1 is normal", 0), "seed": S.integer(),
		}), ["room"], _decorate)
	_add("mds_room_trace", "Trace drawing: turns a picture inside the project into a room's terrain, background and foreground. Each color is a layer. dry_run lists the colors it sees, so colors can set them: [{color, layer, style, fill_color, fill}]. Output: styles (freeform shapes), colors (solid colors), tiles, or picture (the drawing itself, with collision).", AUTHOR,
		room.merged({
			"image": S.text("res://....png"), "dry_run": S.boolean(), "output": S.choice(Array(TRACE_OUTPUTS), "Default styles"), "colors": S.array(S.any_object()),
			"styles": S.object({"terrain": S.text(), "platform": S.text(), "background": S.text(), "foreground": S.text()}, [], "A style for each layer"), "keep_aspect": S.boolean(), "crop": S.boolean("Default true"), "detail": S.number("", 0, 1), "min_size": S.number("Drop specks under this many pixels", 0),
			"smooth": S.boolean(), "bleed": S.number("", 0), "collision": S.boolean("picture: default true"), "cut_paper": S.boolean("picture: default true"), "replace": S.boolean("Default true: replaces the last trace"),
		}), ["room", "image"], _trace)
	_add("mds_room_tile_piece", "Puts tiles anywhere in a room, off the grid, at any angle: the Room view's Place tool. tiles: [[x, y, source, atlas_x, atlas_y], ...] on a grid of their own.", AUTHOR,
		room.merged({"layer": S.choice(Array(MDSRoomPainter.LAYER_ORDER)), "tiles": S.array(S.array(S.integer(), "", 6)), "pos": S.point("Scene pixels"), "rotation": S.number("Degrees"), "scale": S.number("Default 1")}), ["room", "layer", "tiles"], _tile_piece)
	_add("mds_room_tidy", "Takes out what makes a room's scene big or broken. hidden: tiles of layers that are switched off. broken: cells whose tile no longer exists.", AUTHOR,
		room.merged({"ops": S.array(S.choice(["hidden", "broken"]))}), ["room", "ops"], _tidy)
	_add("mds_tileset_get", "A tileset's sheets, terrains and decoration tiles.", READ, {"tileset": S.text("res://....tres")}, ["tileset"], _tileset_get)
	_add("mds_tileset_edit", "Changes a tileset: add_sheet (texture, tile, margin, separation, collision); remove_sheet (source); collision (source, coords, solid); tag (source, coords, kind); terrain (source, region of 3x3 or 4x4 tiles, name, color, collision).", AUTHOR,
		{
			"tileset": S.text("res://....tres"), "op": S.choice(["add_sheet", "remove_sheet", "collision", "tag", "terrain"]), "texture": S.text("res://....png"), "tile": S.array(S.integer("", 1), "[w, h] of a tile in the sheet", 2),
			"margin": S.array(S.integer("", 0), "[x, y]", 2), "separation": S.array(S.integer("", 0), "[x, y]", 2), "collision": S.boolean(), "source": S.integer("", 0), "coords": S.cells("Atlas coords as [x, y]"),
			"solid": S.boolean(), "kind": S.text(), "region": S.cell_box("Atlas coords"), "name": S.text(), "color": S.text("#rrggbb"),
		}, ["tileset", "op"], _tileset_edit)

## A resource of [param types] from a path or {class, set} in the arguments. Null when left out or
## wrong: [member MDSMcpContext.error] says when it was wrong.
func _resource(value: Variant, types: String, at: String) -> Resource:
	if value == null or (value is String and value.is_empty()):
		return null
	var reader := MDSMcpValues.new()
	var res: Variant = reader.decode(value, {"name": at, "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": types})
	if not reader.error.is_empty():
		ctx.error = ctx.fail("bad_value", reader.error)
		return null
	return res

## Opens the room to change, after [param checks] of what is needed have passed. Null: see
## [member MDSMcpContext.error].
func _begin_room(args: Dictionary) -> MDSRoomPainter:
	var world := ctx.read_world(args)
	if not world:
		return null
	return _edit_room(world, args.room, args)

func _world_of(args: Dictionary) -> MDSWorld:
	return ctx.read_world(args)

func _paint_shape(args: Dictionary, _report: Callable) -> Dictionary:
	if args.a.size() != 2 or args.b.size() != 2:
		return ctx.fail("bad_arguments", "a and b are [x, y].")
	var a := Vector2i(args.a[0], args.a[1])
	var b := Vector2i(args.b[0], args.b[1])
	var box := (b - a).abs() + Vector2i.ONE
	if box.x * box.y > MOST_CELLS:
		return ctx.fail("too_many_cells", "A shape may have up to %d cells." % MOST_CELLS)
	var painter := _begin_room(args)
	if not painter:
		return ctx.error
	var kind := SHAPES.find(args.shape) + 1 # After Brush, which is a stroke.
	var curve := CURVES.find(str(args.get("curve", "convex")))
	var cells := MDSTerrainShapes.cells(kind, a, b, curve as MDSTerrainShapes.CurveType, float(args.get("rough", 0.0)), args.get("mirror", false), int(args.get("seed", 0)), int(args.get("count", 3)))
	var layer: String = args.layer
	match args.op:
		"terrain":
			painter.paint_terrain(layer, cells, int(args.get("set", 0)), int(args.get("terrain", 0)))
		"kind":
			painter.place_kind(layer, cells, str(args.get("kind", "")))
		"fill":
			painter.paint_fill(layer, cells, MDSMcpToolsRoom._fill(args.get("fill", {})))
		"erase":
			painter.erase(layer, cells)
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "layer": layer, "cells": cells.size()}

func _freeform_add(args: Dictionary, _report: Callable) -> Dictionary:
	var points := PackedVector2Array()
	for p: Array in args.get("points", []):
		if p.size() == 2:
			points.append(Vector2(p[0], p[1]))
	var smooth: Variant = args.get("smooth")
	if args.has("structure"):
		if not args.has("box"):
			return ctx.fail("bad_arguments", "structure needs box.")
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(int(args.get("seed", 0)))
		var made := MDSShapeGenerators.make(STRUCTURES.find(args.structure), _rect2(args.box), rng)
		points = made.get("points", PackedVector2Array())
		if smooth == null:
			smooth = made.get("smooth", true)
	if points.size() < 3:
		return ctx.fail("bad_arguments", "A shape needs points (three or more), or structure and box.")
	var style := _resource(args.get("style", args.get("style_path")), "MDSFreeformStyle", "style") as MDSFreeformStyle
	if not ctx.error.is_empty() and (args.has("style") or args.has("style_path")) and not style:
		return ctx.error
	var painter := _begin_room(args)
	if not painter:
		return ctx.error
	var group := str(args.get("group", "Freeform"))
	var shape := painter.add_freeform(points, style, group, args.get("solid", true))
	if smooth != null:
		shape.smooth = smooth
	if args.has("seed"):
		shape.seed_value = args.seed
	var at := MDSMcpToolsRoom._path_of(shape, painter)
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "node": at, "points": points.size()}

func _freeform_repair(args: Dictionary, _report: Callable) -> Dictionary:
	var painter := _begin_room(args)
	if not painter:
		return ctx.error
	var out := {"room": args.room}
	if args.has("node"):
		var shape := MDSMcpToolsRoom._node_at(args.node, painter) as MDSFreeform
		if not shape:
			painter.free_instance()
			return ctx.fail("node_not_found", "%s isn't a freeform shape of this room." % args.node, "mds_room_items lists them.")
		out.report = painter.repair_freeform(shape)
	else:
		out.twisted = painter.twisted_freeforms().size()
		out.report = painter.repair_all()
	painter.dirty = true
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else out

func _convert(args: Dictionary, _report: Callable) -> Dictionary:
	var world := _world_of(args)
	if not world:
		return ctx.error
	var conv := MDSFreeformConverter.new()
	for key in ["rock_style", "ledge_style", "back_style", "front_style"]:
		if args.has(key):
			var style := _resource(args[key], "MDSFreeformStyle", key)
			if not style:
				return ctx.error
			conv.set(key, style)
	var fill := _resource(args.get("fill_outside"), "MDSFreeformStyle", "fill_outside") as MDSFreeformStyle
	if args.has("fill_outside") and not fill:
		return ctx.error
	for key in ["growth", "bowl_radius", "lip_radius", "margin", "keep_old", "include_blockout"]:
		if args.has(key):
			conv.set(key, args[key])
	conv.seed_value = int(args.get("seed", 0))
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	conv.use_world_room(world, args.room)
	var report := conv.convert(painter)
	if not str(report.get("error", "")).is_empty():
		painter.free_instance()
		return ctx.fail("cant_convert", str(report.error))
	if fill:
		report.outside = MDSNotchFill.fill(painter, world.get_local_rects(args.room), fill, MDSNotchFill.MARGIN, world.get_local_shape(args.room))
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else report

func _fill_outside(args: Dictionary, _report: Callable) -> Dictionary:
	var style := _resource(args.style, "MDSFreeformStyle", "style") as MDSFreeformStyle
	if not style:
		return ctx.error
	var world := _world_of(args)
	if not world:
		return ctx.error
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var count := MDSNotchFill.fill(painter, world.get_local_rects(args.room), style, MDSNotchFill.MARGIN, world.get_local_shape(args.room))
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "shapes": count}

func _decorate(args: Dictionary, _report: Callable) -> Dictionary:
	var world := _world_of(args)
	if not world:
		return ctx.error
	var deco := MDSFreeformDecorator.new()
	if args.has("stamp_set"):
		deco.stamp_set = _resource(args.stamp_set, "MDSStampSet", "stamp_set")
		if not deco.stamp_set:
			return ctx.error
	for key in ["structure_style", "foreground_style"]:
		if args.has(key):
			var style := _resource(args[key], "MDSFreeformStyle", key)
			if not style:
				return ctx.error
			deco.set(key, style)
	for key in ["hanging", "hanging_category", "floor_plants", "structures", "leaf_category", "foreground", "density"]:
		if args.has(key):
			deco.set(key, args[key])
	if args.has("floor_categories"):
		deco.floor_categories = PackedStringArray(args.floor_categories)
	if args.has("structure_kinds"):
		var kinds: Array[int] = []
		for k: String in args.structure_kinds:
			kinds.append(STRUCTURES.find(k))
		deco.structure_kinds = kinds
	deco.seed_value = int(args.get("seed", 0))
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	deco.use_world_room(world, args.room)
	var report := deco.decorate(painter)
	painter.dirty = true
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else report

func _trace(args: Dictionary, _report: Callable) -> Dictionary:
	var image := MDSMcpGuard.normalize(str(args.image))
	if image.is_empty() or not FileAccess.file_exists(image):
		return ctx.fail("not_found", "%s isn't a picture in the project." % args.image)
	var tracer := MDSDrawingTracer.new()
	if tracer.load_image(image) != OK:
		return ctx.fail("not_loaded", "Could not read %s as a picture." % image)
	if args.get("dry_run", false):
		return {"colors": _colors_of(tracer), "width": tracer.image.get_width(), "height": tracer.image.get_height()}
	var world := _world_of(args)
	if not world or not ctx.has_room(world, args.room):
		return ctx.error
	tracer.output = TRACE_OUTPUTS.find(str(args.get("output", "styles"))) as MDSDrawingTracer.Output
	for key in ["keep_aspect", "crop", "detail", "min_size", "smooth", "bleed", "collision", "cut_paper"]:
		if args.has(key):
			tracer.set(key, args[key])
	var styles: Dictionary = args.get("styles", {})
	for layer_name: String in styles:
		var style := _resource(styles[layer_name], "MDSFreeformStyle", layer_name)
		if not style:
			return ctx.error
		tracer.styles[TRACE_LAYERS.find(layer_name)] = style
	var problem := _apply_colors(tracer, args.get("colors", []))
	if not problem.is_empty():
		return ctx.fail("bad_value", problem)
	var painter := _edit_room(world, args.room, args)
	if not painter:
		return ctx.error
	var box := world.get_room_bounds(args.room)
	box.position -= world.get_origin(args.room)
	tracer.target = box if box.has_area() else Rect2(Vector2.ZERO, world.get_default_room_size())
	var report := tracer.apply(painter, args.get("replace", true))
	if not str(report.get("error", "")).is_empty():
		painter.free_instance()
		return ctx.fail("cant_trace", str(report.error))
	painter.dirty = true
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else report

static func _colors_of(tracer: MDSDrawingTracer) -> Array:
	var out := []
	for c: Dictionary in tracer.colors:
		out.append({"color": "#" + (c.color as Color).to_html(false), "share": snappedf(c.share, 0.001), "layer": TRACE_LAYERS[int(c.layer)]})
	return out

## Applies the arguments' {color, layer, style, fill_color, fill} to the drawing's nearest colors.
func _apply_colors(tracer: MDSDrawingTracer, given: Array) -> String:
	for g: Dictionary in given:
		if not g.has("color") or not Color.html_is_valid(str(g.color)):
			return "Each of colors needs a color: #rrggbb."
		var want := Color(str(g.color))
		var best := -1
		var least := INF
		for i in tracer.colors.size():
			var d := MDSMapImageImporter.color_distance(tracer.colors[i].color, want)
			if d < least:
				least = d
				best = i
		if best < 0:
			return "The drawing has no colors."
		var c: Dictionary = tracer.colors[best]
		if g.has("layer"):
			if not g.layer in TRACE_LAYERS:
				return "%s is not a layer. Layers: %s." % [g.layer, ", ".join(TRACE_LAYERS)]
			c.layer = TRACE_LAYERS.find(g.layer)
		if g.has("style"):
			var style := _resource(g.style, "MDSFreeformStyle", "style")
			if not style:
				return str(ctx.error._error.message)
			c.style = style
		if g.has("fill_color"):
			c.fill_color = S.color(g.fill_color)
		if g.has("fill"):
			c.fill = MDSMcpToolsRoom._fill(g.fill)
	return ""

func _tile_piece(args: Dictionary, _report: Callable) -> Dictionary:
	var tiles := {}
	for t: Array in args.tiles:
		if t.size() < 5:
			return ctx.fail("bad_arguments", "Each tile is [x, y, source, atlas_x, atlas_y].")
		tiles[Vector2i(t[0], t[1])] = [t[2], Vector2i(t[3], t[4]), t[5] if t.size() > 5 else 0]
	if tiles.is_empty():
		return ctx.fail("bad_arguments", "Give some tiles.")
	var painter := _begin_room(args)
	if not painter:
		return ctx.error
	var size := float(args.get("scale", 1.0))
	var xform := Transform2D(deg_to_rad(float(args.get("rotation", 0.0))), Vector2(size, size), 0.0, _vec2(args.pos) if args.has("pos") else Vector2.ZERO)
	var piece := painter.add_tile_piece(args.layer, tiles, xform)
	if not piece:
		painter.free_instance()
		return ctx.fail("not_placed", "The piece couldn't be placed on %s." % args.layer)
	var at := MDSMcpToolsRoom._path_of(piece, painter)
	painter.dirty = true
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else {"room": args.room, "node": at, "tiles": tiles.size()}

func _tidy(args: Dictionary, _report: Callable) -> Dictionary:
	var painter := _begin_room(args)
	if not painter:
		return ctx.error
	var out := {"room": args.room}
	if "broken" in args.ops:
		out.broken = painter.broken_cells().size()
		painter.remove_broken_cells()
	if "hidden" in args.ops:
		var cleared := []
		for n: String in painter.hidden_tiles():
			cleared.append(n)
			painter.clear_layer(n)
		out.hidden = cleared
	painter.dirty = true
	var bad := _save_room(painter)
	return bad if not bad.is_empty() else out

# --- Tilesets --------------------------------------------------------------------------------

func _open_tileset(path_arg: String) -> TileSet:
	var path := MDSMcpGuard.normalize(path_arg)
	if path.is_empty() or not FileAccess.file_exists(path):
		ctx.error = ctx.fail("not_found", "%s isn't a tileset in the project." % path_arg, "mds_tileset_create makes one.")
		return null
	var tiles := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as TileSet
	if not tiles:
		ctx.error = ctx.fail("not_loaded", "%s isn't a tileset." % path)
	return tiles

func _tileset_get(args: Dictionary, _report: Callable) -> Dictionary:
	var tiles := _open_tileset(args.tileset)
	if not tiles:
		return ctx.error
	var painter := MDSRoomPainter.for_tile_set(tiles)
	var reader := MDSMcpValues.new()
	var out := {"tileset": tiles.resource_path, "tile_size": tiles.tile_size, "sheets": reader.encode(_sheets(painter)), "terrains": reader.encode(painter.get_terrains()), "decor": reader.encode(painter.get_decor_tiles())}
	painter.free_instance()
	return out

static func _sheets(painter: MDSRoomPainter) -> Array:
	var out := []
	for s: Array in painter.get_atlas_sources():
		var atlas: TileSetAtlasSource = s[2]
		out.append({"source": s[0], "name": s[1], "texture": atlas.texture.resource_path, "tile": atlas.texture_region_size, "margin": atlas.margins, "separation": atlas.separation})
	return out

func _tileset_edit(args: Dictionary, _report: Callable) -> Dictionary:
	var tiles := _open_tileset(args.tileset)
	if not tiles:
		return ctx.error
	var path := tiles.resource_path
	if not ctx.touch(path):
		return ctx.error
	var painter := MDSRoomPainter.for_tile_set(tiles)
	var out := {"tileset": path, "op": args.op}
	var problem := ""
	var source := int(args.get("source", -1))
	if args.op != "add_sheet" and not tiles.has_source(source):
		problem = "The tileset has no source %d." % source
	else:
		match args.op:
			"add_sheet":
				var texture := MDSMcpGuard.normalize(str(args.get("texture", "")))
				if texture.is_empty() or not FileAccess.file_exists(texture) or not args.has("tile") or args.tile.size() != 2:
					problem = "add_sheet needs texture, a picture in the project, and tile: [w, h]."
				else:
					var margin: Array = args.get("margin", [0, 0])
					var gap: Array = args.get("separation", [0, 0])
					var grown := _files_near(texture)
					out.source = painter.add_sheet(texture, Vector2i(args.tile[0], args.tile[1]), Vector2i(margin[0], margin[1]), Vector2i(gap[0], gap[1]), args.get("collision", false))
					if out.source < 0:
						problem = "%s couldn't be added as a sheet." % texture
					else:
						problem = _touch_new_files(texture, grown)
			"remove_sheet":
				painter.remove_sheet(source)
			"collision":
				painter.set_collision(source, _cells(args.get("coords", [])), args.get("solid", true))
			"tag":
				painter.tag_tiles(source, _cells(args.get("coords", [])), str(args.get("kind", "")))
			"terrain":
				if not args.has("region") or not args.has("name"):
					problem = "terrain needs region and name."
				else:
					var r: Dictionary = args.region
					var made := painter.make_terrain(source, Rect2i(r.x, r.y, r.w, r.h), args.name, S.color(args.get("color", "#808080"), Color.GRAY), args.get("collision", true))
					if made.x < 0:
						problem = "region must be 3x3 or 4x4 tiles of the sheet."
					else:
						out.terrain = made
	if problem.is_empty():
		var err := painter.save_tile_set()
		if err == OK:
			err = ResourceSaver.save(tiles, path)
		if err != OK:
			problem = "Could not save %s: %s." % [path, error_string(err)]
	painter.free_instance()
	if not problem.is_empty():
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		return ctx.fail("tileset_not_changed", problem)
	ctx.host.resource_written(path)
	return out

## The files beside a sheet now: a sheet at another scale gets a scaled copy written there.
static func _files_near(texture: String) -> PackedStringArray:
	return DirAccess.get_files_at(texture.get_base_dir())

## Lets a new file written beside a sheet be taken back with the step. Returns why not, or "".
func _touch_new_files(texture: String, before: PackedStringArray) -> String:
	for f in DirAccess.get_files_at(texture.get_base_dir()):
		if not f in before and not ctx.touch(texture.get_base_dir().path_join(f)):
			return str(ctx.error._error.message)
	return ""
