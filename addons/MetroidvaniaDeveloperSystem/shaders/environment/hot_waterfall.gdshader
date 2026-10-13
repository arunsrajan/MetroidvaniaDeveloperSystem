shader_type canvas_item;
// Hot water falls: a sheet of scalding mineral water pouring straight down, milky and pale where
// it runs thick, straight sides and straight streaks racing along it, a warm glow deep in it, white water at its lip and where
// it plunges, steam pouring off its whole length and billowing up from its foot, and the air
// around it wavering in the heat. `column` is the sheet (x, y, width, height) in px within the
// rectangle, which also holds the steam above, beside and below it.

render_mode blend_mix, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 column = vec4(0.0, 0.0, 120.0, 600.0);
/// How fast the water falls (px/s).
uniform float flow_speed = 420.0;
uniform vec4 water_color : source_color = vec4(0.45, 0.80, 0.80, 0.78);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 0.96, 1.0);
/// The warm light deep in the water and in the pool it plunges into.
uniform vec4 glow_color : source_color = vec4(1.0, 0.72, 0.45, 0.45);
uniform vec4 steam_color : source_color = vec4(0.94, 0.95, 0.96, 0.7);
/// How much the water bends what is behind it.
uniform float refraction : hint_range(0.0, 1.0) = 0.5;
uniform float steam : hint_range(0.0, 1.0) = 0.8;
/// How fast the steam climbs (px/s).
uniform float steam_rise = 60.0;
/// How far the steam drifts out to each side (px).
uniform float steam_spread = 110.0;
/// The air wavering in the heat beside the sheet.
uniform float shimmer : hint_range(0.0, 1.0) = 0.6;

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
	float across = clamp(1.0 - abs((x - w * 0.5) / max(w * 0.5, 1.0)), 0.0, 1.0);
	// Milky mineral water: paler where it runs thick, a warm glow deep in its middle.
	vec3 col = mix(water_color.rgb, foam_color.rgb, 0.12 + streak * 0.55 + lanes * 0.06);
	col *= mix(0.78, 1.06, sqrt(across)) * (0.95 + 0.1 * lanes);
	col = mix(col, glow_color.rgb, glow_color.a * 0.4 * across * (0.6 + 0.4 * lanes));
	// White water at the lip and where it plunges.
	float lip = smoothstep(22.0, 0.0, y) * (0.6 + 0.4 * lanes);
	float plunge = smoothstep(h - 60.0, h, y) * (0.5 + 0.5 * max(s1, lanes));
	col = mix(col, foam_color.rgb, clamp(max(lip, plunge), 0.0, 1.0) * 0.85);

	// The air wavers in the heat beside the sheet (not through it: the falling water stays
	// straight), and the water bends what is behind it in straight strips.
	float side = abs(x - w * 0.5) - w * 0.5;
	float near = smoothstep(steam_spread, 0.0, side) * smoothstep(-steam_spread, 0.0, y) * smoothstep(h + steam_spread, h, y);
	float waver = (sin(px.y * 0.07 - t * 6.0 + px.x * 0.02) + (env_noise(vec2(px.x * 0.03, px.y * 0.03 - t * 1.5)) - 0.5) * 2.0) * shimmer * near * (1.0 - inside);
	vec2 bend = vec2((lanes - 0.5) * refraction * 10.0 * inside + waver * 2.5, waver * 0.8) * SCREEN_PIXEL_SIZE;
	vec3 behind = texture(screen_tex, SCREEN_UV + bend).rgb;
	float wa = water_color.a + (1.0 - water_color.a) * max(streak * 0.5, max(lip, plunge));
	vec3 out_col = mix(behind, col, wa * inside);
	float alpha = max(inside, near * shimmer * 0.9);

	// Steam pouring off its whole length, climbing and drifting out.
	if (steam > 0.0) {
		vec2 sp = vec2((px.x - column.x - w * 0.5) / 46.0, (px.y + t * steam_rise) / 55.0);
		float drift = env_fbm(sp * 0.5 + vec2(seed, t * 0.05), 2) - 0.5;
		float plume = env_fbm(sp + vec2(drift * 1.5 + seed, 0.0), 4);
		float spread = steam_spread * (0.5 + 0.5 * smoothstep(h, -steam_spread, y));
		float band = 1.0 - smoothstep(0.0, spread, side);
		float wisp = smoothstep(0.38, 0.72, plume) * band * smoothstep(h + 40.0, h - 40.0, y);
		// Billowing up from the plunge pool, a little above the foot so it shows over the ground.
		vec2 foot = vec2(px.x - (column.x + w * 0.5), px.y - (column.y + h - 40.0));
		float pool = smoothstep(1.0, 0.2, length(foot / vec2(w * 0.9 + steam_spread * 0.8, 130.0)));
		float billow = pool * smoothstep(0.3, 0.66, env_fbm(vec2(foot.x, foot.y + t * steam_rise * 0.8) / 60.0 + vec2(seed, 0.0), 4));
		float sa = clamp(max(wisp, billow), 0.0, 1.0) * steam * steam_color.a;
		// Thin over the sheet itself, so its straight fall still shows.
		sa *= 1.0 - inside * 0.8;
		out_col = mix(out_col, steam_color.rgb, sa);
		alpha = max(alpha, sa);
		// A warm glow where it plunges.
		float warm = smoothstep(1.0, 0.0, length(foot / vec2(w * 0.8 + 30.0, 50.0))) * glow_color.a * 0.6;
		out_col = mix(out_col, glow_color.rgb, warm * (1.0 - inside * 0.5));
		alpha = max(alpha, warm);
	}
	// Soft at the rectangle's edges (the sheet keeps its own).
	alpha = max(inside, alpha * env_edge(px));
	COLOR = vec4(out_col, alpha * intensity);
}
