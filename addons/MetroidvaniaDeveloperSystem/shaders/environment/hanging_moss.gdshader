shader_type canvas_item;
// Hanging moss (MDSHangingMoss): strands of moss and vine hanging from the rectangle's top edge,
// leafy and tapering, swaying in a draught and parting around the bodies passing through them
// (`bodies`, sent by the node). A darker, thinner layer hangs behind.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.17, 0.27, 0.13, 1.0);
/// Toward the tips.
uniform vec4 tip_color : source_color = vec4(0.45, 0.6, 0.27, 1.0);
/// The layer behind.
uniform vec4 shadow_color : source_color = vec4(0.06, 0.09, 0.06, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.7;
/// Distance between strands (px).
uniform float strand_spacing = 9.0;
uniform float strand_length = 140.0;
/// How much their lengths vary.
uniform float variation : hint_range(0.0, 1.0) = 0.6;
uniform float thickness = 5.0;
/// Leafy bumps along them.
uniform float leaves : hint_range(0.0, 1.0) = 0.6;
uniform float sway = 1.0;
uniform float speed = 1.0;
/// How far around a body strands are pushed aside (px).
uniform float part_radius = 40.0;
uniform vec2 bodies[4];
uniform int body_count = 0;

void vertex() {
	px = VERTEX - rect_origin;
}

// How far the strand hanging at `x` is pushed sideways at depth `y` by the bodies among it: the
// part beside a body moves aside, the part above bends from the root.
float push_at(float x, float y, float len) {
	float off = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= body_count) {
			break;
		}
		vec2 b = bodies[i];
		if (b.y < -part_radius || b.y > len + part_radius) {
			continue;
		}
		float dx = x - b.x;
		float near = exp(-pow(dx / max(part_radius, 1.0), 2.0));
		float bend = clamp(y / max(b.y, 1.0), 0.0, 1.0);
		off += (dx >= 0.0 ? 1.0 : -1.0) * part_radius * 0.85 * near * bend;
	}
	return off;
}

// One layer of strands: its color in rgb and coverage in a.
vec4 layer(vec2 p, float t, float gap, float len_k, float thick_k, float salt, vec3 c_root, vec3 c_tip) {
	vec4 outc = vec4(0.0);
	float col0 = floor(p.x / gap);
	int reach = int(ceil((part_radius * 0.9 + 14.0 * sway) / gap)) + 1;
	reach = min(reach, 7);
	for (int i = -7; i <= 7; i++) {
		if (abs(i) > reach) {
			continue;
		}
		float id = col0 + float(i);
		float h = env_hash(vec2(id, seed + salt));
		if (h > density) {
			continue;
		}
		vec2 r = env_hash2(vec2(id, seed + salt * 2.0 + 1.0));
		float len = strand_length * len_k * (1.0 - variation * r.x);
		if (p.y > len + thickness * 2.0) {
			continue;
		}
		float yy = clamp(p.y / len, 0.0, 1.0);
		float x0 = (id + r.y) * gap;
		float sway_x = (sin(t * (0.8 + 0.3 * r.x) + x0 * 0.013) * 6.0 * pow(yy, 1.5) + sin(t * 0.3 + x0 * 0.004) * 4.0 * yy) * sway;
		float xc = x0 + sway_x + push_at(x0, p.y, len) * len_k;
		float bumps = 1.0 + leaves * 1.2 * (env_noise(vec2(p.y * 0.12, id * 3.7 + salt)) - 0.35);
		float w = thickness * thick_k * 0.5 * (1.0 - 0.55 * yy) * bumps;
		// A rounded tip.
		float tip = p.y > len ? length(vec2(p.x - xc, (p.y - len) * 1.5)) : abs(p.x - xc);
		float a = 1.0 - smoothstep(w - 0.6, w + 0.6, tip);
		// Leaflets on alternate sides.
		float lseg = floor(p.y / 8.0);
		if (p.y < len && env_hash(vec2(lseg, id + salt)) < leaves) {
			float lside = mod(lseg + id, 2.0) * 2.0 - 1.0;
			vec2 lq = env_rotate(p - vec2(xc + lside * w * 1.5, (lseg + 0.5) * 8.0), lside * 0.6);
			float leaf = length(lq / vec2(max(w * 1.3, 1.2), 3.2));
			a = max(a, 1.0 - smoothstep(0.85, 1.15, leaf));
		}
		if (a <= 0.0) {
			continue;
		}
		float shade = 0.72 + 0.28 * clamp((p.x - xc) / max(w, 0.5) * -0.5 + 0.5, 0.0, 1.0);
		vec3 c = mix(c_root, c_tip, yy) * shade * (0.85 + 0.25 * r.x);
		outc = vec4(mix(outc.rgb, c, a), max(outc.a, a));
	}
	return outc;
}

void fragment() {
	float t = TIME * speed;
	vec4 back = layer(px + vec2(strand_spacing * 0.5, 0.0), t * 0.8, strand_spacing * 1.3, 0.75, 0.7, 11.0, shadow_color.rgb, mix(shadow_color.rgb, color.rgb, 0.5));
	vec4 front = layer(px, t, strand_spacing, 1.0, 1.0, 3.0, color.rgb, tip_color.rgb);
	vec3 c = mix(back.rgb, front.rgb, front.a);
	float a = max(front.a, back.a * 0.9);
	float side = clamp(min(px.x, rect_size.x - px.x) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(c, a * color.a * intensity * side);
}
