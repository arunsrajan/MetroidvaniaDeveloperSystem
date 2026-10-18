@tool
class_name MDSMovementInspectorPlugin
extends EditorInspectorPlugin
## Inspector plugin for [MDSMovementConfig]: previews the jump arc (height and distance
## computed from tunables) next to the default 1152x648 room size for scale.

func _can_handle(object: Object) -> bool:
	return object is MDSMovementConfig

func _parse_begin(object: Object) -> void:
	var config := object as MDSMovementConfig
	if not config:
		return
	var preview := MDSJumpArcPreview.new(config)
	add_custom_control(preview)

class MDSJumpArcPreview extends Control:
	var config: MDSMovementConfig

	func _init(p_config: MDSMovementConfig) -> void:
		config = p_config
		custom_minimum_size = Vector2(0, 190)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if config and not config.changed.is_connected(queue_redraw):
			config.changed.connect(queue_redraw)

	func _draw() -> void:
		if not config:
			return
		var w := size.x
		var h := size.y
		var bg_rect := Rect2(0, 0, w, h)
		draw_rect(bg_rect, Color(0.11, 0.12, 0.14), true)
		draw_rect(bg_rect, Color(0.22, 0.24, 0.28), false, 1.0)

		# Scale the 1152 x 648 room box to fit inside the view.
		const ROOM_W := 1152.0
		const ROOM_H := 648.0
		var pad := 14.0
		var avail_w := maxf(w - pad * 2.0, 100.0)
		var avail_h := maxf(h - pad * 2.0 - 24.0, 60.0)
		var scale_factor := minf(avail_w / ROOM_W, avail_h / ROOM_H)

		var room_size := Vector2(ROOM_W, ROOM_H) * scale_factor
		var room_pos := Vector2(pad, h - pad - 20.0 - room_size.y)
		var room_rect := Rect2(room_pos, room_size)

		# Draw room outline
		draw_rect(room_rect, Color(0.18, 0.20, 0.24), true)
		draw_rect(room_rect, Color(0.35, 0.38, 0.44), false, 1.0)

		# Floor line
		var floor_y := room_rect.end.y
		draw_line(Vector2(room_rect.position.x, floor_y), Vector2(room_rect.end.x, floor_y), Color(0.5, 0.55, 0.6), 1.5)

		var font := get_theme_default_font()
		var font_size := 10

		# Draw room label
		draw_string(font, room_rect.position + Vector2(6, 14), "Room Scale: 1152 x 648", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.65, 0.72))

		# Generate and draw jump arc
		var arc := config.jump_arc(1.0 / 60.0)
		if arc.size() >= 2:
			var pts := PackedVector2Array()
			var origin := Vector2(room_rect.position.x + 20.0 * scale_factor, floor_y)
			for pt in arc:
				var screen_pt := origin + pt * scale_factor
				pts.append(screen_pt)

			draw_polyline(pts, Color(0.25, 0.85, 1.0), 2.0, true)

			# Apex point
			var h_px := config.jump_height()
			var rise := config.rise_time()
			var dist_px := config.jump_distance()
			var apex_screen := origin + Vector2(config.max_run_speed * rise, -h_px) * scale_factor

			draw_circle(apex_screen, 3.0, Color(1.0, 0.8, 0.2))

			# Height dimension line
			draw_line(Vector2(apex_screen.x, floor_y), apex_screen, Color(1.0, 0.8, 0.2, 0.5), 1.0)

		# Stats text banner at bottom
		var stats_text := "Height: %d px | Dist: %d px | Air time: %.2f s" % [
			roundi(config.jump_height()),
			roundi(config.jump_distance()),
			config.rise_time() + config.fall_time()
		]
		draw_string(font, Vector2(pad, h - 6.0), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.92, 0.96))
