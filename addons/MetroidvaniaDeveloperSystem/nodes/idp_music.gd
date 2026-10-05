@icon("res://addons/MetroidvaniaDeveloperSystem/assets/labels_idp.png")
class_name IDPMusic
extends Node
## Exploration music per area for an [IDPWorldGame]: each area's [code]music[/code] (a
## stream path in the world file) loops at its [code]music_volume_db[/code], and changing area
## crossfades to the next one. Walking between rooms of one area never restarts it, and an
## area with the same music keeps it playing.
##
## Boss fights override it: [method play_boss] starts the fight's music (the area's
## [code]boss_music[/code] by default) from silence, and is safe to call twice;
## [method end_boss] crossfades back to the area.

## The game whose areas set the music. Empty: [member IDPWorldGame.instance].
@export var game: IDPWorldGame
## Audio bus of the music.
@export var bus: StringName = &"Master"
## Seconds of crossfade between areas.
@export var crossfade_time := 1.5
## Seconds a boss's music takes to rise from silence.
@export var boss_fade_in := 1.0

## What is playing (or fading in) now.
var current_stream: AudioStream
var boss_active := false
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens: Array = [null, null]

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = bus
		p.volume_db = -80.0
		add_child(p)
		var index := i
		# Streams that don't loop by themselves start over.
		p.finished.connect(func() -> void:
			if index == _active and p.stream == current_stream and current_stream:
				p.play())
		_players.append(p)
	_connect.call_deferred()

func _connect() -> void:
	if not game:
		game = IDPWorldGame.instance
	if game:
		if not game.area_changed.is_connected(_on_area_changed):
			game.area_changed.connect(_on_area_changed)
			game.room_loaded.connect(func(_r: String) -> void: follow_area())
		follow_area()

func _on_area_changed(_from: String, _to: String) -> void:
	follow_area()

## The player playing [member current_stream].
func active_player() -> AudioStreamPlayer:
	return _players[_active] if not _players.is_empty() else null

func _area(area: String) -> Dictionary:
	return game.world.get_areas().get(area, {}) if game and game.world else {}

func _stream(path: Variant) -> AudioStream:
	var p := str(path) if path != null else ""
	return load(p) as AudioStream if not p.is_empty() and ResourceLoader.exists(p) else null

## Plays the current area's music (unless a boss's is on).
func follow_area() -> void:
	if boss_active or not game:
		return
	var a := _area(game.current_area)
	play(_stream(a.get("music")), float(a.get("music_volume_db", 0.0)), crossfade_time)

## Crossfades to [param stream] (null: silence) over [param fade] seconds. The same stream
## keeps playing; only its volume follows.
func play(stream: AudioStream, volume_db := 0.0, fade := -1.0) -> void:
	if fade < 0.0:
		fade = crossfade_time
	var cur := active_player()
	if stream == current_stream and (stream == null or cur.playing):
		_fade(_active, volume_db, fade)
		return
	var old := _active
	_active = 1 - _active
	current_stream = stream
	var nxt := active_player()
	nxt.stream = stream
	if stream:
		nxt.volume_db = -80.0
		nxt.play()
		_fade(_active, volume_db, fade)
	else:
		nxt.stop()
	_fade(old, -80.0, fade, true)

func _fade(index: int, volume_db: float, time: float, stop_after := false) -> void:
	var p := _players[index]
	if _tweens[index]:
		(_tweens[index] as Tween).kill()
	if time <= 0.0:
		p.volume_db = volume_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", volume_db, time).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[index] = tw

## Starts a boss fight's music from silence: [param stream], or the current area's
## [code]boss_music[/code]. Calling it again while it plays changes nothing.
func play_boss(stream: AudioStream = null) -> void:
	var a := _area(game.current_area) if game else {}
	if not stream:
		stream = _stream(a.get("boss_music"))
	if not stream:
		return
	if boss_active and current_stream == stream:
		return
	boss_active = true
	_fade(_active, -80.0, minf(0.5, crossfade_time), true)
	_active = 1 - _active
	current_stream = stream
	var p := active_player()
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	_fade(_active, float(a.get("music_volume_db", 0.0)), boss_fade_in)

## Ends the boss music, crossfading back to the area's.
func end_boss() -> void:
	if not boss_active:
		return
	boss_active = false
	follow_area()
