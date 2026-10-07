shader_type canvas_item;
// Fireflies, spores or glitter: glowing motes wandering on slow loops, pulsing on and off.

render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.85, 1.0, 0.45, 1.0);
uniform vec4 color_b : source_color = vec4(0.55, 1.0, 0.75, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.35;
uniform float size = 2.0;
/// Radius of each one's glow (px).
uniform float glow_radius = 9.0;
/// How fast they wander.
uniform float speed = 1.0;
/// 0 always lit, 1 they blink on and off.
uniform float blink : hint_range(0.0, 1.0) = 0.7;
/// Average distance between them (px).
uniform float spacing = 90.0;
uniform float depth : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	px = VERTEX - rect_origin;
}

float mote(vec2 p, float cell, float salt, out float pick) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	float h = env_hash(id + vec2(salt, seed));
	pick = fract(h * 11.0);
	if (h > density) {
		return 0.0;
	}
	vec2 r = env_hash2(id + vec2(seed, salt * 3.0));
	float t = TIME * speed * (0.4 + 0.6 * r.x);
	vec2 c = vec2(0.5) + vec2(sin(t + r.y * 6.3) * 0.28, sin(t * 1.37 + r.x * 6.3) * 0.28);
	float dist = length((fract(g) - c) * cell);
	float pulse = mix(1.0, smoothstep(0.2, 0.9, sin(TIME * (0.8 + 1.4 * r.y) + h * 40.0) * 0.5 + 0.5), blink);
	float core = smoothstep(size, size * 0.3, dist);
	float halo = exp(-dist / max(glow_radius * 0.45, 0.1)) * 0.55;
	return max(core, halo) * pulse;
}

void fragment() {
	float k = mix(1.0, 0.6, depth);
	float pick1;
	float pick2;
	float a1 = mote(px, spacing * k, 1.0, pick1);
	float a2 = mote(px + vec2(spacing * 0.5), spacing * 0.7 * k, 2.0, pick2) * 0.7;
	vec3 c1 = mix(color.rgb, color_b.rgb, step(0.5, pick1));
	vec3 c2 = mix(color.rgb, color_b.rgb, step(0.5, pick2));
	vec3 col = mix(c2, c1, step(a2, a1));
	float a = max(a1, a2) * mix(1.0, 0.55, depth);
	COLOR = vec4(col, a * color.a * intensity * env_edge(px));
}
