@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_idp.png")
class_name IDPLevelOverview
extends Node2D
## A pull-back over the level: pictures of the rooms around the live one ([IDPRoomPictures]),
## each in its real place on the world map, while the camera pulls back until all of them are on
## screen. For a death screen (Lost in the Sky's fall), a level intro or a map preview.
##
## Put it in an [IDPWorldGame] scene (a child of the game). [method open] shows it and
## [method close] takes it away and gives the camera back. The camera moves through the room
## camera's [IDPCameraDirector] ([method IDPCameraDirector.frame_world]), or the game's Camera2D
## when there is no room camera.
##
## Pictures already made (an [IDPRoomPictures] node makes them while the game is played) are
## shown at once; a room never pictured is drawn after the pull-back has started.
## [codeblock]
## func _on_player_died() -> void:
##     await $LevelOverview.show_for(5.0)   # skippable after a second
##     get_tree().reload_current_scene()
## [/codeblock]

signal opened
signal closed

## The game whose rooms are shown. Empty: [member IDPWorldGame.instance].
@export var game: IDPWorldGame
## Which rooms: the current area's, the current layer's or the whole world's.
@export var scope: IDPRoomPictures.Scope = IDPRoomPictures.Scope.AREA
## Seconds the pull-back takes (eased in and out).
@export var pull_time := 2.4
## Share of the screen the level fills at the end of the pull-back.
@export_range(0.5, 1.0) var fit := 0.94
## Space around the level, as a share of its size.
@export var margin := 0.03
## [method show_for] can be skipped with any key or button after this many seconds.
@export var skip_after := 1.0

static var _open := 0

## The pictures shown, by room id.
var pictures: Dictionary = {}
## The area the pull-back frames (world).
var level_rect := Rect2()
var _shown := false
var _skip := false
var _cam_state: Dictionary = {}
var _tween: Tween

## True while an overview is on screen ([IDPRoomPictures] draws nothing meanwhile).
static func is_open() -> bool:
	return _open > 0

func _ready() -> void:
	# Pictures are placed in world coordinates.
	top_level = true
	global_position = Vector2.ZERO

func _game() -> IDPWorldGame:
	if not game:
		game = IDPWorldGame.instance
	return game

## Shows the rooms around the live one and pulls the camera back over them.
func open() -> void:
	var g := _game()
	if _shown or not g or not g.world or g.current_room.is_empty():
		return
	_shown = true
	_open += 1
	var world := g.world
	level_rect = world.get_room_bounds(g.current_room)
	var missing: Array[String] = []
	for id in IDPRoomPictures.rooms_in_scope(world, g.current_room, scope):
		level_rect = level_rect.merge(world.get_room_bounds(id))
		if id == g.current_room:
			continue
		var tex := IDPRoomPictures.picture(world.get_scene_path(id))
		_add_picture(id, tex)
		if not tex:
			missing.append(id)
	level_rect = level_rect.grow(maxf(level_rect.size.x, level_rect.size.y) * margin)
	_pull_back()
	opened.emit()
	# Rooms never pictured: from the disk cache, else drawn now, one a frame.
	for id in missing:
		if not _shown:
			return
		var path := world.get_scene_path(id)
		var tex := IDPRoomPictures.load_cached(path)
		if not tex:
			tex = await IDPRoomPictures.bake(self, path, IDPRoomPictures.room_rect(world, id))
		if tex and _shown and pictures.has(id):
			_set_texture(pictures[id], tex, world.get_room_bounds(id).size)
		await get_tree().process_frame

## Takes the pictures away and gives the camera back (gliding, or at once with
## [param instant]).
func close(instant := false) -> void:
	if not _shown:
		return
	_shown = false
	_open = maxi(0, _open - 1)
	for id in pictures:
		if is_instance_valid(pictures[id]):
			pictures[id].queue_free()
	pictures.clear()
	var g := _game()
	var director := g.room_camera.get_director() if g and g.room_camera else null
	if director:
		if instant:
			director.cancel()
		else:
			director.release()
	elif not _cam_state.is_empty() and g and g.camera:
		if _tween:
			_tween.kill()
		for k in _cam_state:
			g.camera.set(k, _cam_state[k])
		_cam_state.clear()
	closed.emit()

## Opens, holds for [param seconds] (or until a key or button after [member skip_after]), and
## leaves it open: the caller decides what comes next (a reload, [method close]...).
func show_for(seconds: float) -> void:
	open()
	_skip = false
	var start := Time.get_ticks_msec()
	var until := start + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and _shown:
		if _skip and Time.get_ticks_msec() - start > int(skip_after * 1000.0):
			break
		await get_tree().process_frame

func _unhandled_input(event: InputEvent) -> void:
	if _shown and event.is_pressed() and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton):
		_skip = true

func _add_picture(id: String, tex: Texture2D) -> void:
	var b := game.world.get_room_bounds(id)
	var s := Sprite2D.new()
	s.name = "Room_" + id.validate_node_name()
	s.centered = false
	# A dark live room's light doesn't reach the pictures.
	s.light_mask = 0
	s.position = b.position
	add_child(s)
	_set_texture(s, tex, b.size)
	pictures[id] = s

func _set_texture(s: Sprite2D, tex: Texture2D, size: Vector2) -> void:
	s.texture = tex
	if tex:
		s.scale = size / Vector2(tex.get_size())

func _pull_back() -> void:
	var g := game
	if g.room_camera:
		g.room_camera.get_director().frame_world(level_rect, INF, pull_time, fit)
		return
	var cam := g.camera if g.camera else get_viewport().get_camera_2d()
	if not cam:
		return
	_cam_state = {"zoom": cam.zoom, "offset": cam.offset, "limit_left": cam.limit_left, "limit_top": cam.limit_top,
		"limit_right": cam.limit_right, "limit_bottom": cam.limit_bottom, "position_smoothing_enabled": cam.position_smoothing_enabled}
	var vp := cam.get_viewport_rect().size
	var z := minf(vp.x / level_rect.size.x, vp.y / level_rect.size.y) * fit
	var centre := cam.get_screen_center_position()
	cam.position_smoothing_enabled = false
	cam.limit_left = -10000000
	cam.limit_top = -10000000
	cam.limit_right = 10000000
	cam.limit_bottom = 10000000
	cam.offset = centre - cam.global_position
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_parallel()
	_tween.tween_property(cam, "zoom", Vector2(z, z), pull_time)
	_tween.tween_property(cam, "offset", level_rect.get_center() - cam.global_position, pull_time)

func _exit_tree() -> void:
	if _shown:
		_shown = false
		_open = maxi(0, _open - 1)
