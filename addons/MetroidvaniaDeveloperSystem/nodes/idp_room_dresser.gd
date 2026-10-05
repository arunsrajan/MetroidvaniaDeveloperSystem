@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_idp.png")
class_name IDPRoomDresser
extends Node
## Fits props to the floor and declutters rooms as they load ([IDPRoomDressing]), for rooms that
## are generated or dressed at runtime. Rooms dressed in the editor don't need it: use the Room
## view's Fit props to floor and Declutter, which are saved.
##
## As a child of an [IDPWorldGame] it dresses every room the game loads; anywhere else, the room
## it is in (its owner, else its parent) when it enters the tree.

## Emitted after a room was dressed, with the edits made ({node, kind, from, to}).
signal dressed(room: Node, edits: Array)

## Stand the objects that stand on the floor.
@export var fit_to_floor := true
## Separate the objects that overlap.
@export var declutter := true
## Space left between separated objects.
@export var gap := IDPRoomDressing.GAP

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var game := get_parent() as IDPWorldGame
	if game:
		game.room_loaded.connect(func(_id: String) -> void: dress(game.room_node))
	else:
		var room := owner if owner else get_parent()
		dress.call_deferred(room)

## Dresses [param room] now (it must be in the tree): returns the edits made.
func dress(room: Node) -> Array:
	if not is_instance_valid(room) or not room.is_inside_tree():
		return []
	# The room's ground is copied into a physics world of its own, apart from the live room's.
	var host := SubViewport.new()
	host.disable_3d = true
	host.size = Vector2i(4, 4)
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Outside the room: the copy mustn't count among the room's objects.
	get_tree().root.add_child(host)
	var c := IDPRoomDressing.ground_check(host, room)
	var edits: Array = []
	if fit_to_floor:
		var fit := IDPRoomDressing.fit_to_floor(room, c)
		IDPRoomDressing.apply(fit)
		edits.append_array(fit)
	if declutter:
		var sep := IDPRoomDressing.declutter(room, c, null, gap)
		IDPRoomDressing.apply(sep)
		edits.append_array(sep)
	c.free_proxy()
	host.free()
	dressed.emit(room, edits)
	return edits
