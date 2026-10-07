shader_type canvas_item;
// Embers rising from a fire below, wobbling and flickering out as they cool, or with a
// negative rise_speed, ash drifting down. MDSEmbers draws a far plane behind the terrain.

render_mode blend_mix, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 hot_color : source_color = vec4(1.0, 0.80, 0.36, 1.0);
uniform vec4 cool_color : source_color = vec4(0.92, 0.22, 0.06, 1.0);
/// How fast they rise (px/s); negative: they fall, like ash.
uniform float rise_speed = 70.0;
/// Sideways drift (px/s).
uniform float drift = 15.0;
uniform float density : hint_range(0.0, 1.0) = 0.3;
uniform float size = 2.2;
/// How far they wobble from side to side.
uniform float wobble = 18.0;
/// A soft halo around each one (0 for ash).
uniform float glow : hint_range(0.0, 1.0) = 0.6;
uniform float flicker : hint_range(0.0, 1.0) = 0.7;
uniform float depth : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	px = VERTEX - rect_origin;
}

vec4 motes(vec2 p, float cell, float spd, float sz, float salt) {
	vec2 q = p + vec2(-drift, spd) * TIME;
	vec2 g = q / cell;
	vec2 id = floor(g);
	float h = env_hash(id + vec2(salt, seed));
	if (h > density) {
		return vec4(0.0);
	}
	vec2 c = (0.3 + 0.4 * env_hash2(id + vec2(seed, salt))) * cell;
	c.x += sin(TIME * (1.0 + h * 2.0) + h * 20.0) * min(wobble, cell * 0.25);
	vec2 d = fract(g) * cell - c;
	float s = sz * (0.6 + 0.8 * fract(h * 7.3));
	float core = smoothstep(s, s * 0.3, length(d));
	float halo = exp(-length(d) / max(s * 2.5, 0.1)) * glow * 0.6;
	float lit = mix(1.0, 0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * (5.0 + 7.0 * h) + h * 60.0)), flicker);
	vec3 col = mix(hot_color.rgb, cool_color.rgb, fract(h * 3.1));
	return vec4(col, max(core, halo) * lit);
}

void fragment() {
	float k = mix(1.0, 0.55, depth);
	vec4 m = motes(px, 58.0 * k, rise_speed, size * k, 1.0);
	vec4 m2 = motes(px + vec2(21.0, 9.0), 40.0 * k, rise_speed * 0.75, size * 0.75 * k, 2.0);
	m2.a *= 0.75;
	vec4 m3 = motes(px + vec2(5.0, 31.0), 27.0 * k, rise_speed * 0.55, size * 0.55 * k, 3.0);
	m3.a *= 0.5;
	vec4 best = m;
	if (m2.a > best.a) {
		best = m2;
	}
	if (m3.a > best.a) {
		best = m3;
	}
	COLOR = vec4(best.rgb, best.a * mix(1.0, 0.6, depth) * intensity * env_edge(px));
}
