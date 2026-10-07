shader_type canvas_item;
// A waterfall: a sheet of water pouring down with streaks racing along it, ragged sides,
// white water at the lip and where it plunges, and mist billowing out at its foot. What is
// behind it shows through, bent by the water. `column` is the sheet (x, y, width, height) in
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
	// Ragged sides that breathe along the fall.
	float wob_l = (env_noise(vec2((y - t * flow_speed * 0.3) * 0.012, seed)) - 0.5) * w * 0.14;
	float wob_r = (env_noise(vec2((y - t * flow_speed * 0.3) * 0.012, seed + 7.0)) - 0.5) * w * 0.14;
	float inside = smoothstep(-1.5, 1.5, x - wob_l) * smoothstep(-1.5, 1.5, w + wob_r - x) * step(0.0, y) * step(y, h);
	// Streaks racing down the sheet.
	float s1 = env_noise(vec2(x / 9.0, (y - t * flow_speed) / 120.0) + seed);
	float s2 = env_noise(vec2(x / 4.0 + 13.0, (y - t * flow_speed * 1.3) / 60.0));
	float streak = smoothstep(0.45, 0.9, s1 * 0.6 + s2 * 0.5);
	// A rounded sheet: darker at its sides.
	float across = clamp(1.0 - abs((x - w * 0.5) / max(w * 0.5, 1.0)), 0.0, 1.0);
	vec3 col = mix(water_color.rgb, foam_color.rgb, streak * 0.55);
	col *= mix(0.72, 1.08, sqrt(across));
	// White water at the lip and where it plunges.
	float lip = smoothstep(22.0, 0.0, y) * (0.6 + 0.4 * s2);
	float plunge = smoothstep(h - 50.0, h, y) * (0.5 + 0.5 * s1);
	col = mix(col, foam_color.rgb, clamp(max(lip, plunge), 0.0, 1.0) * 0.85);
	// What is behind, bent by the water.
	vec2 bend = vec2((s1 - 0.5) * refraction * 10.0, 0.0) * SCREEN_PIXEL_SIZE;
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
