@tool
class_name MDSGeometryChecker
extends Node
## Runs [MDSRoomCheck] on room scenes in the background, one room per frame, for the Issues
## tab's Geometry category. Each room is checked in an off-screen [SubViewport] with a
## physics space of its own. Results are cached until the scene file, the room's shape, its
## passages or the player settings change.

## Emitted when a batch is done, with the scene paths it checked.
signal finished(paths: Array)
signal progress(current: int, total: int, path: String)

## path -> {sig, issues}
var results: Dictionary = {}
var _host: SubViewport
var _queue: Array = [] ## jobs
var _running := false

func _ready() -> void:
	_host = SubViewport.new()
	_host.disable_3d = true
	_host.size = Vector2i(4, 4)
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_host)

## A job: {path, name (for messages), rects, passages, player (settings dict),
## cell_size (MetSys mode: issues get the map cell they are in)}.
static func signature(job: Dictionary) -> String:
	return JSON.stringify([FileAccess.get_modified_time(job.path), job.rects.map(func(r: Rect2) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y]),
		job.passages.map(func(p: Dictionary) -> Array: return [p.name, p.pos.x, p.pos.y, p.side]), job.get("player", {})])

## Whether [param job]'s cached result is out of date.
func is_stale(job: Dictionary) -> bool:
	return results.get(job.path, {}).get("sig", "") != signature(job)

## Cached issues of a scene, or [].
func issues_of(path: String) -> Array:
	return results.get(path, {}).get("issues", [])

## Queues the jobs that need checking (all of them with [param force]) and runs them.
func check(jobs: Array, force := false) -> void:
	for j in jobs:
		if not ResourceLoader.exists(j.path):
			continue
		if force or is_stale(j):
			_queue = _queue.filter(func(q: Dictionary) -> bool: return q.path != j.path)
			_queue.append(j)
	if not _running and not _queue.is_empty():
		_run()

func _run() -> void:
	_running = true
	var done: Array = []
	var total := _queue.size()
	while not _queue.is_empty():
		if not is_inside_tree():
			break
		await get_tree().process_frame
		if _queue.is_empty():
			break
		var job: Dictionary = _queue.pop_front()
		progress.emit(done.size() + 1, total, job.path)
		results[job.path] = {"sig": signature(job), "issues": check_now(job, _host)}
		done.append(job.path)
	_running = false
	if not done.is_empty():
		finished.emit(done)

## Checks one room scene right away (under [param host], in the tree).
static func check_now(job: Dictionary, host: Node) -> Array:
	var packed := load(job.path) as PackedScene
	if not packed:
		return []
	var scene := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	scene.set_meta(&"fake_map", true)
	var c := MDSRoomCheck.new(job.get("player", {}))
	c.room_rects.assign(job.rects)
	c.passages = job.passages
	c.build_from_scene(scene, host)
	var issues := c.run(job.get("name", ""))
	c.free_proxy()
	scene.free()
	var cell_size: Vector2 = job.get("cell_size", Vector2.ZERO)
	for i in issues:
		if cell_size != Vector2.ZERO:
			i.cell = Vector2i((Vector2(i.pos) / cell_size).floor())
	return issues
