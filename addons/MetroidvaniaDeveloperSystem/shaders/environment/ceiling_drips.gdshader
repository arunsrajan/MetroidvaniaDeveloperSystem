shader_type canvas_item;
// Dripping water (MDSDrips): drops gathering under the rectangle's top edge (a ceiling), swelling,
// falling and splashing on its bottom edge (the floor) in a spreading ring and a few droplets;
// the ceiling glints wet.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.72, 0.86, 0.96, 0.75);
uniform vec4 highlight : source_color = vec4(1.0, 1.0, 1.0, 0.9);
/// How many of the places a drop could form drip.
uniform float density : hint_range(0.0, 1.0) = 0.6;
/// Distance between drips (px).
uniform float spacing = 70.0;
uniform float drop_size = 3.5;
uniform float gravity = 1200.0;
/// Average seconds a drop takes to gather.
uniform float interval = 2.5;
uniform float splash : hint_range(0.0, 1.0) = 0.7;
/// Glints along the ceiling.
uniform float wet : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	float hgt = rect_size.y;
	float floor_y = hgt - 2.0;
	float col0 = floor(px.x / spacing);
	float a = 0.0;
	float hl = 0.0;
	for (int i = -1; i <= 1; i++) {
		float id = col0 + float(i);
		float h = env_hash(vec2(id, seed));
		if (h > density) {
			continue;
		}
		vec2 r = env_hash2(vec2(id, seed + 4.0));
		float x = (id + 0.2 + 0.6 * r.x) * spacing;
		float size = drop_size * (0.8 + 0.4 * r.x);
		float grow_t = interval * (0.6 + 0.8 * r.y);
		float fall_t = sqrt(2.0 * max(floor_y - size, 1.0) / max(gravity, 1.0));
		float cycle = grow_t + fall_t + 0.7;
		float cyc = (TIME + h * 17.0 * cycle) / cycle;
		float tm = fract(cyc) * cycle;
		if (tm < grow_t) {
			// Gathering under the ceiling: a bead swelling and stretching.
			float g = tm / grow_t;
			float rad = size * (0.3 + 0.7 * g);
			vec2 c = vec2(x, rad * (0.4 + 0.8 * g));
			vec2 q = (px - c) / vec2(1.0, 1.0 + 0.6 * g);
			float d = length(q);
			float bead = 1.0 - smoothstep(rad - 0.6, rad + 0.6, d);
			float neck = px.y < c.y ? 1.0 - smoothstep(rad * (0.25 + 0.5 * (1.0 - px.y / max(c.y, 1.0))) - 0.5, rad * (0.25 + 0.5 * (1.0 - px.y / max(c.y, 1.0))) + 0.5, abs(px.x - x)) : 0.0;
			a = max(a, max(bead, neck));
			hl = max(hl, bead * (1.0 - smoothstep(0.0, rad * 0.55, length(q + vec2(rad * 0.35, rad * 0.35)))));
		} else if (tm < grow_t + fall_t) {
			// Falling, stretched by its speed.
			float ft = tm - grow_t;
			float y = size + 0.5 * gravity * ft * ft;
			float stretch = 1.0 + min(gravity * ft / 450.0, 3.0);
			vec2 q = (px - vec2(x, y - size * stretch * 0.3)) / vec2(1.0, stretch);
			float d = length(q);
			float drop = 1.0 - smoothstep(size * 0.7 - 0.5, size * 0.7 + 0.5, d);
			a = max(a, drop);
			hl = max(hl, drop * 0.5);
		} else if (splash > 0.0) {
			// The splash: a ring spreading on the floor, droplets thrown up.
			float st = tm - grow_t - fall_t;
			float k = st / 0.7;
			vec2 q = (px - vec2(x, floor_y)) * vec2(1.0, 4.0);
			float ring_r = size * 1.5 + k * size * 8.0;
			a = max(a, (1.0 - smoothstep(0.8, 2.2, abs(length(q) - ring_r))) * (1.0 - k) * splash * 0.8);
			for (int j = 0; j < 4; j++) {
				vec2 rr = env_hash2(vec2(id * 3.0 + float(j), floor(cyc) + seed));
				vec2 v0 = vec2((rr.x - 0.5) * 160.0, -(70.0 + 120.0 * rr.y)) * splash;
				vec2 p = vec2(x, floor_y) + v0 * st + vec2(0.0, 0.5 * gravity * 0.6 * st * st);
				if (p.y > floor_y + 1.0) {
					continue;
				}
				float d = length(px - p);
				a = max(a, (1.0 - smoothstep(size * 0.35, size * 0.35 + 0.8, d)) * (1.0 - k));
			}
		}
	}
	float wetline = wet * (1.0 - smoothstep(0.0, 3.0, px.y)) * (0.3 + 0.7 * env_noise(vec2(px.x * 0.05, TIME * 0.5 + seed)));
	a = max(a, wetline * 0.55);
	hl = max(hl, wetline * 0.5);
	float side = clamp(min(px.x, rect_size.x - px.x) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(mix(color.rgb, highlight.rgb, clamp(hl * highlight.a, 0.0, 1.0)), a * color.a * intensity * side);
}
