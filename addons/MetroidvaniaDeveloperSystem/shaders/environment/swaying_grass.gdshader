shader_type canvas_item;
// Swaying grass (MDSSwayingGrass): blades of grass along the rectangle's bottom edge, swaying in
// gusts of wind and bending away from the bodies walking through them (`bodies`, sent by the
// node), a flower on some.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.12, 0.29, 0.14, 1.0);
/// Toward the tips.
uniform vec4 tip_color : source_color = vec4(0.46, 0.7, 0.3, 1.0);
uniform vec4 flower_color : source_color = vec4(0.96, 0.86, 0.55, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.85;
/// Distance between blades (px).
uniform float blade_spacing = 5.0;
uniform float blade_height = 34.0;
/// How much their heights vary.
uniform float variation : hint_range(0.0, 1.0) = 0.5;
uniform float blade_width = 3.0;
uniform float sway = 1.0;
/// Which way the wind leans them (-1 left, 1 right).
uniform float wind : hint_range(-1.0, 1.0) = 0.15;
uniform float speed = 1.0;
/// How far around a body blades bend away (px).
uniform float part_radius = 36.0;
/// How far they bend.
uniform float bend : hint_range(0.0, 2.0) = 1.0;
uniform float flowers : hint_range(0.0, 1.0) = 0.08;
uniform vec2 bodies[4];
uniform int body_count = 0;

void vertex() {
	px = VERTEX - rect_origin;
}

// How the bodies bend the blade rooted at `x`: -1 (all the way left) to 1.
float body_bend(float x) {
	float b = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= body_count) {
			break;
		}
		vec2 q = bodies[i];
		float above = rect_size.y - q.y;
		float reach = (1.0 - smoothstep(blade_height + part_radius * 0.5, blade_height + part_radius * 1.5, above)) * smoothstep(-part_radius, 0.0, above);
		float dx = x - q.x;
		b += (dx >= 0.0 ? 1.0 : -1.0) * exp(-pow(dx / max(part_radius, 1.0), 2.0)) * reach;
	}
	return clamp(b, -1.0, 1.0);
}

void fragment() {
	float t = TIME * speed;
	float up = rect_size.y - px.y;
	float max_lean = blade_height * 0.7 * (abs(wind) + 0.5 * sway + bend);
	int reach = min(int(ceil(max_lean / max(blade_spacing, 1.0))) + 1, 10);
	float col0 = floor(px.x / blade_spacing);
	vec4 outc = vec4(0.0);
	for (int i = -10; i <= 10; i++) {
		if (abs(i) > reach) {
			continue;
		}
		float id = col0 + float(i);
		float h = env_hash(vec2(id, seed));
		if (h > density) {
			continue;
		}
		vec2 r = env_hash2(vec2(id, seed + 5.0));
		float hgt = blade_height * (1.0 - variation * r.x);
		float x0 = (id + r.y) * blade_spacing;
		float gust = (env_noise(vec2(x0 * 0.004 + t * 0.35, seed)) - 0.5) * 0.9;
		float lean = (wind + (sin(t * (1.2 + 0.4 * r.x) + x0 * 0.03) * 0.25 + gust) * sway + body_bend(x0) * bend) * hgt * 0.7;
		// A flower at the tip of some.
		if (fract(h * 7.31) < flowers) {
			vec2 tip = vec2(x0 + lean, rect_size.y - hgt);
			float fd = length(px - tip);
			float fa = 1.0 - smoothstep(1.6, 2.6, fd);
			outc = vec4(mix(outc.rgb, flower_color.rgb * (0.85 + 0.3 * r.y), fa), max(outc.a, fa));
		}
		float tt = up / hgt;
		if (tt < 0.0 || tt > 1.0) {
			continue;
		}
		float xc = x0 + lean * tt * tt;
		float w = blade_width * 0.5 * (1.0 - tt * 0.85);
		float a = 1.0 - smoothstep(w - 0.5, w + 0.5, abs(px.x - xc));
		if (a <= 0.0) {
			continue;
		}
		vec3 c = mix(color.rgb, tip_color.rgb, tt) * (0.8 + 0.35 * r.x);
		outc = vec4(mix(outc.rgb, c, a), max(outc.a, a));
	}
	float side = clamp(min(px.x, rect_size.x - px.x) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(outc.rgb, outc.a * color.a * intensity * side);
}
