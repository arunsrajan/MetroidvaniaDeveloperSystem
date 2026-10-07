shader_type canvas_item;
// Leaves (or petals) drifting down: each one tumbles as it falls, showing its paler back,
// swaying on the breeze. MDSFallingLeaves draws a far plane behind the terrain.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color_a : source_color = vec4(0.85, 0.45, 0.14, 1.0);
uniform vec4 color_b : source_color = vec4(0.72, 0.20, 0.10, 1.0);
uniform vec4 color_c : source_color = vec4(0.90, 0.70, 0.22, 1.0);
uniform float fall_speed = 55.0;
/// Sideways drift (px/s).
uniform float wind = 30.0;
uniform float density : hint_range(0.0, 1.0) = 0.35;
/// Leaf length (px).
uniform float leaf_size = 9.0;
/// How fast they spin and tumble.
uniform float spin = 1.0;
uniform float sway : hint_range(0.0, 1.0) = 0.6;
uniform float depth : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	px = VERTEX - rect_origin;
}

vec4 leaf(vec2 p, float cell, float spd, float sz, float salt) {
	vec2 q = p - vec2(wind, spd) * TIME;
	vec2 g = q / cell;
	vec2 id = floor(g);
	float h = env_hash(id + vec2(salt, seed));
	if (h > density) {
		return vec4(0.0);
	}
	vec2 r = env_hash2(id + vec2(seed, salt * 2.0));
	vec2 c = vec2(0.5 + sin(TIME * (0.7 + r.x) + r.y * 6.3) * 0.22 * sway, 0.5);
	vec2 d = (fract(g) - c) * cell;
	float ang = TIME * spin * (0.8 + 1.5 * r.y) + h * 30.0;
	d = env_rotate(d, ang);
	// Tumbling: the leaf turns edge-on and over.
	float tumble = cos(TIME * spin * (1.2 + r.x) + r.y * 20.0);
	d.x /= max(abs(tumble), 0.18);
	float half_len = sz * (0.7 + 0.6 * fract(h * 5.3));
	float half_w = half_len * 0.42;
	float along = d.y / half_len;
	float shape = step(abs(along), 1.0) * smoothstep(half_w * (1.0 - along * along) + 0.6, half_w * (1.0 - along * along) - 0.6, abs(d.x));
	vec3 col = mix(color_a.rgb, color_b.rgb, step(0.4, fract(h * 17.0)));
	col = mix(col, color_c.rgb, step(0.75, fract(h * 23.0)));
	// The midrib, and the paler back when it turns over.
	col *= mix(1.0, 0.7, smoothstep(0.8, 0.0, abs(d.x)) * step(abs(along), 0.9));
	col = mix(col, col * 1.25 + 0.05, step(tumble, 0.0) * 0.5);
	return vec4(col, shape);
}

void fragment() {
	float k = mix(1.0, 0.55, depth);
	vec4 l1 = leaf(px, 120.0 * k, fall_speed, leaf_size * k, 1.0);
	vec4 l2 = leaf(px + vec2(37.0, 61.0), 85.0 * k, fall_speed * 0.75, leaf_size * 0.75 * k, 2.0);
	vec4 best = l1;
	if (l2.a > best.a) {
		best = l2;
	}
	COLOR = vec4(best.rgb * mix(1.0, 0.75, depth), best.a * mix(1.0, 0.65, depth) * intensity * env_edge(px));
}
