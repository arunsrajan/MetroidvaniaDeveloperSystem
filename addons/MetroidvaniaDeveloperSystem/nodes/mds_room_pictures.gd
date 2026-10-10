@tool
@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_mds.png")
class_name MDSRoomPictures
extends Node
## Pictures of rooms, made before they are needed: an [MDSLevelOverview] (a death screen that
## pulls back over the level, a map preview) shows pictures of the rooms around the live one,
## and building a dozen rooms at that moment would stall the game.
##
## The cache is static (shared by every node, kept for the session) and on disk in
## [constant CACHE_DIR], named after the room's scene path and the time it was last saved: an
## edited room is drawn again, an unchanged one never is. The editor's World map reads the same
## cache for its scene previews.
##
## As a node in an [MDSWorldGame] scene it makes the pictures of the rooms around the player in
## the background: first the ones already on disk (read off the main thread), then, one room
## every [member bake_gap] seconds, the ones never drawn (the scene loaded off the main thread
## first). A room drawn for a picture is a copy made only to be looked at
## ([method strip_for_preview]): no players, enemies, cameras, sounds or UI, nothing running.

## Emitted before a room is drawn.
signal bake_started(path: String)
## Emitted when a room's picture is ready (read from disk or drawn).
signal picture_ready(path: String, texture: Texture2D)
## Emitted when every room in scope has a picture.
signal all_ready

enum Scope { AREA, LAYER, WORLD }

const CACHE_DIR := "user://mds_room_pictures/"
## Groups whose nodes are left out of pictures (they act on the game).
const GAMEPLAY_GROUPS: PackedStringArray = ["player", "enemy", "enemies", "boss", "bosses", "mini_boss", "carry_over"]

## Rooms are drawn at this share of their size. A whole level is usually seen at a tenth or
## less, so this is still sharper than the screen.
static var bake_scale := 0.35

## The game whose rooms are pictured. Empty: [member MDSWorldGame.instance].
@export var game: MDSWorldGame
## Which rooms: the current area's, the current layer's or the whole world's.
@export var scope: Scope = Scope.AREA
## Seconds after a room loads before any work starts.
@export var start_delay := 0.5
## Seconds between two rooms drawn (each draw costs a frame or two).
@export var bake_gap := 1.0

static var _textures: Dictionary = {} ## scene path -> {key, texture}
static var _saves: Array[int] = []

var _queue: Array = [] ## of {id, path, rect}
var _running := false

# --- The cache ----------------------------------------------------------------------------------

## The key of the picture of the scene at [param path] as it is now.
static func cache_key(path: String) -> String:
	return ("%s_%d" % [path, FileAccess.get_modified_time(path)]).md5_text()

static func cache_file(path: String) -> String:
	return CACHE_DIR + cache_key(path) + ".png"

## The picture of the scene at [param path] if one is in memory and the scene hasn't changed
## since, else null. Never reads files: cheap enough for any frame.
static func picture(path: String) -> Texture2D:
	var e: Dictionary = _textures.get(path, {})
	return e.texture if not e.is_empty() and e.key == cache_key(path) else null

## The picture of the scene at [param path]: from memory, else from the disk cache (read now),
## else null.
static func load_cached(path: String) -> Texture2D:
	var tex := picture(path)
	if tex:
		return tex
	var file := cache_file(path)
	if not FileAccess.file_exists(file):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(file))
	return store(path, img, false) if img and not img.is_empty() else null

## True when the scene at [param path] has no up-to-date picture in memory or on disk.
static func is_stale(path: String) -> bool:
	return picture(path) == null and not FileAccess.file_exists(cache_file(path))

## Remembers [param image] as the picture of the scene at [param path] (and saves it to the disk
## cache, off the main thread, with [param save]).
static func store(path: String, image: Image, save := true) -> Texture2D:
	var tex := ImageTexture.create_from_image(image)
	_textures[path] = {"key": cache_key(path), "texture": tex}
	if save:
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		var file := ProjectSettings.globalize_path(cache_file(path))
		_saves.append(WorkerThreadPool.add_task(func() -> void: image.save_png(file)))
	return tex

## Waits for the pictures being saved to disk.
static func flush() -> void:
	for t in _saves:
		WorkerThreadPool.wait_for_task_completion(t)
	_saves.clear()

## Forgets the picture of [param path] in memory (all of them with ""). The disk cache stays.
static func forget(path := "") -> void:
	if path.is_empty():
		_textures.clear()
	else:
		_textures.erase(path)

## Deletes the disk cache (every picture, or those of scenes no longer in [param keep]).
static func clear_disk(keep: PackedStringArray = []) -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		return
	var keys: Dictionary = {}
	for p in keep:
		keys[cache_key(p) + ".png"] = true
	for f in DirAccess.get_files_at(CACHE_DIR):
		if not keys.has(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_DIR + f))

# --- Drawing a room -----------------------------------------------------------------------------

## The area of room [param id] in its scene's own coordinates (what a picture shows).
static func room_rect(world: MDSWorld, id: String) -> Rect2:
	var b := world.get_room_bounds(id)
	return Rect2(b.position - world.get_origin(id), b.size)

## Draws [param rect] (scene coordinates) of the scene at [param path] into a picture, remembers
## and saves it. The room is built in an off-screen viewport under [param host], drawn once and
## freed. With [param in_background] the scene is loaded off the main thread first. Returns null
## when nothing can be drawn (no scene, or no renderer: headless runs).
static func bake(host: Node, path: String, rect: Rect2, in_background := false) -> Texture2D:
	if not ResourceLoader.exists(path) or not rect.has_area() or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	var tree := host.get_tree()
	var packed: PackedScene
	if in_background and ResourceLoader.load_threaded_request(path) == OK:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
			if not is_instance_valid(host) or not host.is_inside_tree():
				return null
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
	else:
		packed = load(path) as PackedScene
	if not packed:
		return null
	var inst := packed.instantiate()
	if not inst is Node2D:
		inst.free()
		return null
	strip_for_preview(inst)
	# Nothing in it runs, and with processing off its bodies and areas stay out of physics.
	inst.process_mode = Node.PROCESS_MODE_DISABLED
	var vp := SubViewport.new()
	vp.size = Vector2i((rect.size * bake_scale).ceil()).maxi(1)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.process_mode = Node.PROCESS_MODE_DISABLED
	vp.add_child(inst)
	host.add_child(vp)
	vp.canvas_transform = Transform2D().scaled(Vector2(bake_scale, bake_scale)) * Transform2D(0.0, -rect.position)
	silence(inst) # again: some nodes make their players in _ready
	for i in 3:
		await tree.process_frame
		if not is_instance_valid(vp) or not vp.is_inside_tree():
			return null
	var img := vp.get_texture().get_image() if DisplayServer.get_name() != "headless" else null
	vp.queue_free()
	if not img or img.is_empty():
		return null
	return store(path, img)

## Takes out of a room copy made to be looked at everything that would act on the game: nodes in
## [constant GAMEPLAY_GROUPS] (players, enemies, followers), cameras, canvas layers (UI), and
## nodes with the [code]mds_preview_skip[/code] metadata; sounds are silenced. The root gets the
## [code]mds_preview[/code] metadata, so room scripts can skip gameplay setup.
static func strip_for_preview(root: Node) -> void:
	root.set_meta(&"mds_preview", true)
	silence(root)
	var doomed: Array[Node] = []
	for n in root.find_children("*", "", true, false):
		if is_gameplay_only(n):
			doomed.append(n)
	# Only the topmost of each doomed branch is freed, decided before anything is.
	for n in doomed:
		var p := n.get_parent()
		var inside := false
		while p and p != root:
			if p in doomed:
				inside = true
				break
			p = p.get_parent()
		if not inside:
			n.get_parent().remove_child(n)
			n.free()

static func is_gameplay_only(n: Node) -> bool:
	if MDSLegacy.has_meta_key(n, &"mds_preview_skip"):
		return true
	for g in GAMEPLAY_GROUPS:
		if n.is_in_group(g):
			return true
	if n is Camera2D or n is CanvasLayer:
		return true
	var s: Script = n.get_script()
	return s != null and s.get_global_name() in [&"PhantomCamera2D", &"PhantomCameraHost"]

## Keeps every sound player (scripts reach for them) but stopped and empty.
static func silence(root: Node) -> void:
	for n in root.find_children("*", "", true, false):
		if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
			n.autoplay = false
			n.stop()
			n.stream = null

# --- Rooms in scope -----------------------------------------------------------------------------

## Rooms with a scene around [param current] in [param world]: its area's, its layer's or all.
static func rooms_in_scope(world: MDSWorld, current: String, p_scope: Scope) -> Array[String]:
	var out: Array[String] = []
	var area := world.get_room_area(current) if world.has_room(current) else ""
	var layer := world.get_room_layer(current) if world.has_room(current) else 0
	for id in world.get_room_ids():
		if world.get_scene_path(id).is_empty() or world.get_room_layer(id) != layer:
			continue
		if p_scope == Scope.AREA and world.get_room_area(id) != area:
			continue
		out.append(id)
	return out

# --- The node -----------------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.is_editor_hint():
		return
	_connect.call_deferred()

func _connect() -> void:
	if not game:
		game = MDSWorldGame.instance
	if not game:
		return
	if not game.room_loaded.is_connected(_on_room_loaded):
		game.room_loaded.connect(_on_room_loaded)
	if not game.current_room.is_empty():
		_on_room_loaded(game.current_room)

## Rooms in scope without an up-to-date picture.
func stale_rooms() -> Array[String]:
	var out: Array[String] = []
	if not game:
		game = MDSWorldGame.instance
	if not game or not game.world:
		return out
	for id in rooms_in_scope(game.world, game.current_room, scope):
		if picture(game.world.get_scene_path(id)) == null:
			out.append(id)
	return out

## Rooms waiting for a picture.
func pending() -> int:
	return _queue.size()

func _on_room_loaded(_id: String) -> void:
	var queued: Dictionary = {}
	for q in _queue:
		queued[q.path] = true
	for id in stale_rooms():
		var path := game.world.get_scene_path(id)
		if not queued.has(path):
			_queue.append({"id": id, "path": path, "rect": room_rect(game.world, id)})
			queued[path] = true
	if not _running and not _queue.is_empty():
		_work()

func _work() -> void:
	_running = true
	var tree := get_tree()
	await tree.create_timer(start_delay, true, false, true).timeout
	# What is on disk: read off the main thread, made into textures one per frame.
	for q in _queue.duplicate():
		if not is_inside_tree():
			_running = false
			return
		if picture(q.path) or not FileAccess.file_exists(cache_file(q.path)):
			continue
		var file := ProjectSettings.globalize_path(cache_file(q.path))
		var result: Array = []
		var task := WorkerThreadPool.add_task(func() -> void: result.append(Image.load_from_file(file)))
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var img: Image = result[0] if not result.is_empty() else null
		if img and not img.is_empty():
			picture_ready.emit(q.path, store(q.path, img, false))
			_queue.erase(q)
		await tree.process_frame
	# What isn't: drawn a room at a time, spaced out, never while an overview is on screen.
	while not _queue.is_empty():
		await tree.create_timer(bake_gap, true, false, true).timeout
		if not is_inside_tree():
			break
		if MDSLevelOverview.is_open():
			continue
		var q: Dictionary = _queue.pop_front()
		if picture(q.path):
			continue
		bake_started.emit(q.path)
		var tex: Texture2D = await bake(self, q.path, q.rect, true)
		if tex:
			picture_ready.emit(q.path, tex)
	_running = false
	if is_inside_tree() and stale_rooms().is_empty():
		all_ready.emit()
