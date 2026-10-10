shader_type canvas_item;
// Will-o'-wisps (MDSWisps): ghostly flames drifting on slow, looping paths, a flickering tongue
// of fire trailing behind each one and licking upward, a halo lighting the air around it.

render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

/// The flame.
uniform vec4 color : source_color = vec4(0.35, 0.72, 1.0, 1.0);
/// The heart of it.
uniform vec4 core_color : source_color = vec4(0.88, 1.0, 1.0, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.6;
/// Average distance between wisps (px).
uniform float spacing = 220.0;
uniform float wisp_size = 8.0;
uniform float glow_radius = 44.0;
uniform float speed = 1.0;
/// How long the flame trails behind.
uniform float trail : hint_range(0.0, 3.0) = 1.0;
uniform float flicker : hint_range(0.0, 1.0) = 0.6;

void vertex() {
	px = VERTEX - rect_origin;
}

// Where a wisp of cell `id` is at time `t` (px, from the cell's corner).
vec2 path(vec2 r, float h, float t) {
	return (vec2(0.5) + vec2(sin(t * 0.37 * (0.6 + r.x) + h * 6.283) * 0.3 + sin(t * 0.91 + r.y * 9.0) * 0.05,
		sin(t * 0.29 * (0.6 + r.y) + r.x * 6.283) * 0.25 + sin(t * 1.3 + h * 7.0) * 0.05)) * spacing;
}

float wisp(vec2 p, vec2 id, float t, out float core) {
	core = 0.0;
	float h = env_hash(id + seed);
	if (h > density) {
		return 0.0;
	}
	vec2 r = env_hash2(id + seed * 1.7);
	float tt = t * (0.6 + 0.6 * r.x);
	vec2 head = path(r, h, tt);
	if (length(p - head) > glow_radius * 2.5 + wisp_size * 8.0) {
		return 0.0;
	}
	float fl = 1.0 + (env_noise(vec2(t * 6.0 + h * 50.0, 0.0)) - 0.5) * flicker;
	float dh = length(p - head);
	core = 1.0 - smoothstep(wisp_size * 0.3 * fl, wisp_size * 0.6 * fl, dh);
	float total = core + exp(-dh / max(glow_radius * 0.35, 0.1)) * 0.35;
	// The flame trails along the way it came, licking upward, one tongue of fire.
	float flame = 0.0;
	for (int k = 1; k <= 12; k++) {
		float fk = float(k) / 12.0;
		vec2 q = path(r, h, tt - fk * 1.4 * trail);
		q.y -= fk * 22.0 * trail;
		q.x += sin(t * 9.0 + fk * 14.0 + h * 30.0) * fk * 5.0 * flicker;
		float rad = wisp_size * (1.0 - fk * 0.85) * fl * 1.1;
		float d = length(p - q);
		flame = max(flame, (1.0 - smoothstep(rad * 0.2, rad, d)) * (1.0 - fk) * 0.85);
	}
	return total + flame;
}

void fragment() {
	float t = TIME * speed;
	vec2 id = floor(px / spacing);
	float total = 0.0;
	float core = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cid = id + vec2(float(i), float(j));
			float c;
			total += wisp(px - cid * spacing, cid, t, c);
			core = max(core, c);
		}
	}
	vec3 col = mix(color.rgb, core_color.rgb, core);
	COLOR = vec4(col, clamp(total, 0.0, 1.0) * color.a * intensity * env_edge(px));
}
