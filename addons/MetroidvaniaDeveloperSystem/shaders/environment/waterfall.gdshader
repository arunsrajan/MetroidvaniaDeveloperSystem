shader_type canvas_item;
// A waterfall: a sheet of water pouring straight down, with straight sides and straight
// streaks racing along it, white water at the lip and where it plunges, and mist billowing out
// at its foot. What is behind it shows through, bent by the water in straight strips. `column` is the sheet (x, y, width, height) in
// px within the rectangle, which also holds the mist around its foot.

render_mode blend_mix;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 column = vec4(0.0, 0.0, 120.0, 600.0);
/// How fast the water falls (px/s).
uniform float flow_speed = 520.0;
uniform vec4 water_color : source_color = vec4(0.42, 0.70, 0.85, 0.72);
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform vec4 mist_color : source_color = vec4(0.85, 0.92, 0.97, 0.6);
/// How much the water bends what is behind it.
uniform float refraction : hint_range(0.0, 1.0) = 0.6;
uniform float mist : hint_range(0.0, 1.0) = 0.7;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	float x = px.x - column.x;
	float y = px.y - column.y;
	float w = column.z;
	float h = column.w;
	float t = TIME;
	// Straight sides: the sheet falls plumb, without a wobble or a curve.
	float inside = smoothstep(-1.0, 1.0, x) * smoothstep(-1.0, 1.0, w - x) * step(0.0, y) * step(y, h);
	// Straight streaks racing down the sheet, each lane at a pace of its own.
	float s1 = env_fall_streaks(x, y, t, flow_speed, 9.0, 120.0, seed);
	float s2 = env_fall_streaks(x + 3.0, y, t, flow_speed * 1.3, 4.0, 60.0, seed + 13.0);
	float streak = clamp(s1 * 0.75 + s2 * 0.6, 0.0, 1.0);
	float lanes = env_fall_lanes(x, 14.0, seed + 2.0);
	// A rounded sheet: darker at its sides.
	float across = clamp(1.0 - abs((x - w * 0.5) / max(w * 0.5, 1.0)), 0.0, 1.0);
	vec3 col = mix(water_color.rgb, foam_color.rgb, streak * 0.55 + lanes * 0.08);
	col *= mix(0.72, 1.08, sqrt(across)) * (0.94 + 0.12 * lanes);
	// White water at the lip and where it plunges.
	float lip = smoothstep(22.0, 0.0, y) * (0.6 + 0.4 * lanes);
	float plunge = smoothstep(h - 50.0, h, y) * (0.5 + 0.5 * max(s1, lanes));
	col = mix(col, foam_color.rgb, clamp(max(lip, plunge), 0.0, 1.0) * 0.85);
	// What is behind, bent by the water in straight strips down the sheet.
	vec2 bend = vec2((lanes - 0.5) * refraction * 10.0, 0.0) * SCREEN_PIXEL_SIZE;
	vec3 behind = texture(screen_tex, SCREEN_UV + bend * inside).rgb;
	float wa = water_color.a + (1.0 - water_color.a) * max(streak * 0.5, max(lip, plunge));
	vec3 sheet = mix(behind, col, wa);
	float alpha = inside;

	// Mist billowing out at the foot.
	if (mist > 0.0) {
		vec2 foot = vec2(px.x - (column.x + w * 0.5), px.y - (column.y + h));
		vec2 q = vec2(foot.x, foot.y + t * 30.0) / 70.0;
		float n = env_fbm(q + vec2(seed, -t * 0.15), 4);
		float reach = w * 0.9 + 60.0;
		float cloud = smoothstep(1.0, 0.25, length(foot / vec2(reach, 70.0))) * smoothstep(0.3, 0.7, n);
		float ma = cloud * mist * mist_color.a;
		sheet = mix(sheet, mist_color.rgb, ma * (1.0 - alpha * 0.5));
		alpha = max(alpha, ma);
	}
	COLOR = vec4(sheet, alpha * intensity);
}
