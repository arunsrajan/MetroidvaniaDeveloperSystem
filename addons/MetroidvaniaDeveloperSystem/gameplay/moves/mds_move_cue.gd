@tool
class_name MDSMoveCue
extends MDSMove
## A beat of the fight with no hit in it: a screech that shakes the screen, a line of dialogue, a
## flag for later moves ([constant MDSMoveCondition.Kind.FLAG]), a signal for your own scene. It holds
## for [member seconds].

@export_range(0.0, 10.0, 0.05, "or_greater") var seconds := 0.0
## Camera shake (pixels).
@export var shake_pixels := 0.0
@export_range(0.0, 5.0, 0.05, "or_greater") var shake_seconds := 0.3
## Camera push-in (1: none).
@export_range(1.0, 2.0, 0.01) var punch := 1.0
## The game freezes for this long (ms).
@export var hitstop_ms := 0
## Set on the fight's flags...
@export var set_flag := &""
## ...to this.
@export var flag_value := true
## Emitted by the enemy as [signal MDSEnemy.cue], if it has one by this name.
@export var cue := &""
## Said by it.
@export var dialogue: MDSDialogueData
## Heard when it starts.
@export var sound: AudioStream

func _start(ctx: MDSMoveContext) -> void:
	var e := ctx.enemy
	if shake_pixels > 0.0:
		shake(ctx, shake_pixels, shake_seconds)
	if punch > 1.0 and e is MDSBoss:
		var d := (e as MDSBoss)._director()
		if d:
			d.punch_in(punch, maxf(0.2, seconds), e)
	if hitstop_ms > 0 and e.gameplay:
		e.gameplay.hitstop(hitstop_ms)
	if set_flag != &"":
		ctx.flags[set_flag] = flag_value
	if cue != &"" and e.has_signal(&"move_cue"):
		e.emit_signal(&"move_cue", cue)
	if dialogue and e is MDSBoss:
		(e as MDSBoss).say(dialogue)
	if sound:
		var a := AudioStreamPlayer2D.new()
		a.stream = sound
		e.add_child(a)
		a.finished.connect(a.queue_free)
		a.play()

func _update(ctx: MDSMoveContext, _delta: float) -> Status:
	return Status.DONE if elapsed(ctx) >= seconds else Status.RUNNING

## Shakes the room camera, when there is one.
static func shake(ctx: MDSMoveContext, pixels: float, time: float) -> void:
	if pixels <= 0.0:
		return
	var game := ctx.enemy.game
	if game and game.room_camera and game.room_camera.has_method(&"shake"):
		game.room_camera.call(&"shake", pixels, time)

## A cue (for code).
static func of(p_seconds: float, p_shake := 0.0, p_flag := &"") -> MDSMoveCue:
	var c := MDSMoveCue.new()
	c.seconds = p_seconds
	c.shake_pixels = p_shake
	c.set_flag = p_flag
	return c
