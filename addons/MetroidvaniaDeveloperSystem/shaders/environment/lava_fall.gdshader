shader_type canvas_item;
// Lava falls: molten rock pouring straight down over a ledge, slow and thick, with straight
// sides. A white-hot core with straight orange streaks racing down it, dark crust plates riding
// down in straight lanes with glowing cracks between them, a bright lip where it pours over and
// a splash where it lands throwing molten drops, a heat glow around it, embers rising and the air wavering in
// the heat. `column` is the fall (x, y, width, height) in px within the rectangle, which also
// holds the glow, the splash and the embers around it.

render_mode blend_mix, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 column = vec4(0.0, 0.0, 110.0, 600.0);
/// How fast the molten rock falls in its middle (px/s); its sides drag slower.
uniform float flow_speed = 170.0;
uniform vec4 crust_color : source_color = vec4(0.16, 0.04, 0.03, 1.0);
uniform vec4 hot_color : source_color = vec4(0.95, 0.30, 0.06, 1.0);
uniform vec4 bright_color : source_color = vec4(1.0, 0.82, 0.42, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.10, 0.55);
/// How much crust forms on it as it falls.
uniform float crust : hint_range(0.0, 1.0) = 0.45;
uniform float glow : hint_range(0.0, 1.0) = 0.8;
/// How far the glow reaches out to each side (px).
uniform float glow_spread = 90.0;
/// Molten drops thrown out where it lands.
uniform float splash : hint_range(0.0, 1.0) = 0.7;
uniform float embers : hint_range(0.0, 1.0) = 0.6;
/// The air wavering in the heat around it.
uniform float heat_haze : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	px = VERTEX - rect_origin;
}

// A molten drop flung from the landing point on an arc, cooling as it flies (0..1).
float drop(vec2 p, float i, float land_x, float land_y, float w, out float cool) {
	float period = 0.8 + 0.7 * env_hash(vec2(i, seed + 1.0));
	float phase = TIME / period + env_hash(vec2(i, seed + 2.0));
	float n = floor(phase);
	float k = fract(phase);
	float side = env_hash(vec2(i, n + seed)) * 2.0 - 1.0;
	// From the edges of its foot, flung outward.
	float start = land_x + sign(side) * w * (0.3 + 0.2 * abs(side));
	float reach = sign(side) * (30.0 + 110.0 * env_hash(vec2(i + 5.0, n + seed)));
	// An arc 40 to 150 px high, landing a little lower than it left.
	float height = 40.0 + 110.0 * env_hash(vec2(i + 9.0, n + seed));
	vec2 at = vec2(start + reach * k, land_y - 8.0 - 4.0 * height * k * (1.0 - k) + 30.0 * k);
	float r = mix(5.5, 2.0, k);
	cool = k;
	return smoothstep(r, r * 0.3, length(p - at)) * step(env_hash(vec2(i + 13.0, n)), splash);
}

void fragment() {
	float x = px.x - column.x;
	float y = px.y - column.y;
	float w = column.z;
	float h = column.w;
	float t = TIME;
	float across_raw = 1.0 - abs(x - w * 0.5) / max(w * 0.5, 1.0);
	float across = clamp(across_raw, 0.0, 1.0);
	// Straight sides: the molten rock falls plumb, without bulges or a curve.
	float inside = smoothstep(-1.5, 1.5, x) * smoothstep(-1.5, 1.5, w - x) * step(0.0, y) * step(y, h);
	// Lanes of molten rock sliding down side by side, faster in the middle and dragging at the
	// sides. Each lane keeps one pace, so whatever rides on it stays a straight line.
	float id = floor(x / 8.0);
	float mid = clamp(1.0 - abs((id + 0.5) * 8.0 - w * 0.5) / max(w * 0.5, 1.0), 0.0, 1.0);
	float fy = y - t * flow_speed * (0.45 + 0.55 * sqrt(mid));
	float melt = env_noise(vec2(id * 3.7 + seed, fy / 110.0)) * 0.65 + env_noise(vec2(id * 1.9 + seed + 5.0, fy / 45.0)) * 0.35;
	float streak = max(env_fall_streaks(x, y, t, flow_speed * 0.8, 5.0, 70.0, seed * 1.7), smoothstep(0.55, 0.9, melt) * 0.6);
	// Crust riding down in long straight strands, a lane wide, glowing where they meet.
	float cl = x / 12.0;
	float cid = floor(cl);
	float cmid = clamp(1.0 - abs((cid + 0.5) * 12.0 - w * 0.5) / max(w * 0.5, 1.0), 0.0, 1.0);
	float cfy = y - t * flow_speed * (0.45 + 0.55 * sqrt(cmid));
	float plate_n = env_noise(vec2(cid * 5.3 + seed + 11.0, cfy / (150.0 + 90.0 * env_hash(vec2(cid, seed + 4.0)))));
	float plates = smoothstep(0.58, 0.78, plate_n + (1.0 - across) * 0.4 + crust * 0.3 - 0.15);
	plates *= crust * smoothstep(0.0, 140.0, y) * 0.9;
	float fx = fract(cl);
	float crack = smoothstep(0.0, 0.18, min(fx, 1.0 - fx));
	vec3 col = mix(hot_color.rgb, bright_color.rgb, streak * (0.4 + 0.6 * across));
	// A white-hot core.
	col = mix(col, mix(bright_color.rgb, vec3(1.0, 0.97, 0.88), 0.35), smoothstep(0.55, 1.0, across) * (0.3 + 0.3 * melt));
	col = mix(col, crust_color.rgb, plates * crack);
	// Darker at its very sides, where it cools first.
	col *= mix(0.7, 1.0, smoothstep(0.0, 0.35, across_raw));
	// A bright lip where it pours over, and where it lands.
	float lip = smoothstep(16.0, 0.0, y);
	float land = smoothstep(h - 36.0, h, y) * (0.6 + 0.4 * streak);
	col = mix(col, bright_color.rgb, clamp(max(lip, land), 0.0, 1.0) * 0.75);
	vec3 out_col = col;
	float alpha = inside;

	// Around it: the air wavering, the glow, molten drops and embers.
	float cx = px.x - (column.x + w * 0.5);
	float dx = max(abs(cx) - w * 0.5, 0.0);
	float span = smoothstep(-40.0, 0.0, y) * smoothstep(h + 60.0, h, y);
	float haze = exp(-dx / max(glow_spread * 0.6, 1.0)) * span * heat_haze;
	vec2 bend = vec2(sin(px.y * 0.06 - t * 7.0 + px.x * 0.01) + (env_noise(vec2(px.x * 0.03, px.y * 0.03 - t * 2.0)) - 0.5) * 2.0, 0.0) * haze * 3.0;
	vec3 behind = texture(screen_tex, SCREEN_UV + bend * SCREEN_PIXEL_SIZE).rgb;
	float flicker = 0.85 + 0.15 * sin(t * 3.1 + seed) * sin(t * 4.7);
	float g = exp(-dx / max(glow_spread * 0.6, 1.0)) * span * 0.8;
	vec2 pool = vec2(cx, (px.y - (column.y + h)) * 1.5);
	g = max(g, exp(-length(pool) / (w * 0.6 + glow_spread * 0.6)));
	g *= glow * glow_color.a * flicker;
	vec3 around = mix(behind, glow_color.rgb, clamp(g, 0.0, 1.0));
	float around_a = max(haze * 0.9, g);
	// Embers rising beside it and over where it lands.
	if (embers > 0.0) {
		vec2 ep = vec2(px.x + sin(px.y * 0.05 + t) * 6.0, px.y + t * 70.0);
		vec2 eg = ep / 30.0;
		vec2 id = floor(eg);
		float eh = env_hash(id + vec2(seed, 9.0));
		if (eh < embers * 0.45) {
			vec2 d = (fract(eg) - (0.25 + 0.5 * env_hash2(id + 4.0))) * 30.0;
			float e = smoothstep(1.8, 0.2, length(d)) * (0.5 + 0.5 * sin(t * 9.0 + eh * 50.0));
			e *= exp(-dx / max(glow_spread * 0.7, 1.0)) * smoothstep(-20.0, 60.0, y);
			around = mix(around, bright_color.rgb, e);
			around_a = max(around_a, e);
		}
	}
	around_a *= env_edge(px);
	out_col = mix(around, out_col, alpha);
	alpha = max(alpha, around_a);
	// Molten drops thrown out where it lands, cooling as they fly (over the fall too).
	if (splash > 0.0) {
		for (int i = 0; i < 12; i++) {
			float cool;
			float d = drop(px, float(i), column.x + w * 0.5, column.y + h, w, cool);
			if (d > 0.0) {
				out_col = mix(out_col, mix(bright_color.rgb, hot_color.rgb * 0.6, cool), d);
				alpha = max(alpha, d);
			}
		}
	}
	COLOR = vec4(out_col, alpha * intensity);
}
