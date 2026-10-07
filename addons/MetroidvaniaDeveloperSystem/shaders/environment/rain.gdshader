shader_type canvas_item;
// Rain: three depths of streaks falling at an angle, splashes along the bottom of the
// rectangle and a mist hanging low. MDSRain draws a far plane behind the terrain (depth 1)
// and a near one in front of it.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

/// Lean of the rain (degrees): positive falls toward the right.
uniform float angle_deg : hint_range(-60.0, 60.0) = 12.0;
/// How fast the drops fall (px/s).
uniform float speed = 1100.0;
uniform float density : hint_range(0.0, 1.0) = 0.55;
uniform float drop_length = 34.0;
uniform float drop_width = 1.4;
uniform vec4 color : source_color = vec4(0.72, 0.80, 0.90, 0.55);
/// 0 the near plane, 1 far away.
uniform float depth : hint_range(0.0, 1.0) = 0.0;
/// Splashes along the rectangle's bottom edge (the ground).
uniform float splashes : hint_range(0.0, 1.0) = 0.6;
/// A mist hanging low over the ground.
uniform float mist : hint_range(0.0, 1.0) = 0.15;
uniform vec4 mist_color : source_color = vec4(0.45, 0.52, 0.60, 1.0);

void vertex() {
	px = VERTEX - rect_origin;
}

// Drops in columns `cell_w` wide, about one per `cell_h` of fall in the columns that have one.
float drops(vec2 p, float cell_w, float cell_h, float spd, float len, float wid, float amount, float salt) {
	float col_id = floor(p.x / cell_w);
	float col_rand = env_hash(vec2(col_id, salt + seed));
	float y = p.y - TIME * spd * (0.85 + 0.3 * col_rand) + col_rand * 1000.0;
	vec2 id = vec2(col_id, floor(y / cell_h));
	float h = env_hash(id + vec2(salt * 3.1, seed));
	if (h > amount) {
		return 0.0;
	}
	float x_in = (fract(p.x / cell_w) - (0.2 + 0.6 * env_hash(id + 7.7))) * cell_w;
	float y_in = fract(y / cell_h) * cell_h - env_hash(id + 3.3) * max(cell_h - len, 0.0);
	float inside = step(0.0, y_in) * step(y_in, len);
	// Brighter at the head (the bottom end).
	float along = clamp(y_in / max(len, 0.001), 0.0, 1.0);
	return inside * smoothstep(wid, 0.0, abs(x_in)) * (0.3 + 0.7 * along);
}

float splash(vec2 p, float ground_y) {
	float cell = 34.0;
	float cx = floor(p.x / cell);
	float h = env_hash(vec2(cx, seed + 5.0));
	float period = 0.45 + 0.4 * h;
	float life = fract(TIME / period + h * 7.0);
	float x0 = (cx + 0.2 + 0.6 * env_hash(vec2(cx, floor(TIME / period + h * 7.0)))) * cell;
	vec2 d = vec2(p.x - x0, (p.y - ground_y) * 3.0);
	float r = life * 9.0;
	float ring = smoothstep(1.6, 0.0, abs(length(d) - r)) * step(p.y, ground_y + 1.0);
	// Two droplets thrown up.
	float hop = life * (1.0 - life) * 4.0;
	float drop1 = smoothstep(1.4, 0.0, length(vec2(p.x - x0 - life * 7.0, p.y - (ground_y - hop * 9.0))));
	float drop2 = smoothstep(1.4, 0.0, length(vec2(p.x - x0 + life * 6.0, p.y - (ground_y - hop * 7.0))));
	return max(ring, max(drop1, drop2)) * (1.0 - life) * step(h, 0.8);
}

void fragment() {
	float a = radians(angle_deg);
	vec2 r = env_rotate(px, a);
	float k = mix(1.0, 0.55, depth);
	float rain = drops(r, 26.0 * k, 260.0 * k, speed * mix(1.0, 0.7, depth), drop_length * k, drop_width * k, density, 1.0);
	rain = max(rain, 0.6 * drops(r + vec2(7.0, 0.0), 15.0 * k, 170.0 * k, speed * 0.8 * k, drop_length * 0.7 * k, drop_width * 0.75 * k, density, 2.0));
	rain = max(rain, 0.35 * drops(r + vec2(3.0, 0.0), 9.0 * k, 120.0 * k, speed * 0.62 * k, drop_length * 0.5 * k, drop_width * 0.6 * k, density, 3.0));
	rain *= mix(1.0, 0.55, depth);
	vec3 col = color.rgb;
	float alpha = rain * color.a;
	if (splashes > 0.0 && depth < 0.5) {
		float s = splash(px, rect_size.y - 3.0) * splashes;
		alpha = max(alpha, s * color.a * 1.4);
	}
	if (mist > 0.0) {
		float low = smoothstep(rect_size.y * 0.55, rect_size.y, px.y);
		float m = env_fbm(vec2(px.x - TIME * 40.0, px.y * 2.0) / 260.0 + seed, 4);
		float ma = low * smoothstep(0.3, 0.8, m) * mist * 0.6;
		col = mix(col, mist_color.rgb, ma / max(alpha + ma, 0.001));
		alpha = max(alpha, ma);
	}
	// No fade along the bottom: that is the ground the splashes land on.
	float edge = clamp(min(min(px.x, rect_size.x - px.x), px.y) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(col, alpha * intensity * edge);
}
