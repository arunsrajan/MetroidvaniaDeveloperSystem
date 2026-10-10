shader_type canvas_item;
// Void tendrils (MDSVoidTendrils): tendrils of black void rising from the rectangle's bottom
// edge out of a pool of darkness, writhing, a dark violet glow at their rims, motes of void
// drifting up. They lean toward the bodies that come near (`bodies`, sent by the node).

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.02, 0.01, 0.04, 1.0);
/// Their rims and the motes.
uniform vec4 glow_color : source_color = vec4(0.5, 0.25, 1.0, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.75;
/// Distance between tendrils (px).
uniform float spacing = 46.0;
uniform float height = 160.0;
uniform float variation : hint_range(0.0, 1.0) = 0.5;
uniform float thickness = 14.0;
uniform float writhe = 1.0;
uniform float speed = 1.0;
/// How close (px) a body must come for them to reach for it.
uniform float reach = 160.0;
/// The pool of darkness at their roots.
uniform float pool : hint_range(0.0, 1.0) = 0.7;
uniform float motes : hint_range(0.0, 1.0) = 0.4;
uniform vec2 bodies[4];
uniform int body_count = 0;

void vertex() {
	px = VERTEX - rect_origin;
}

// How a tendril rooted at `x`, `hgt` tall, leans toward the bodies near it: -1 to 1.
float lean_to(float x, float hgt) {
	float lean = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= body_count) {
			break;
		}
		vec2 b = bodies[i];
		float dx = b.x - x;
		float above = rect_size.y - b.y;
		float k = (1.0 - smoothstep(reach * 0.35, reach, abs(dx))) * (1.0 - smoothstep(hgt + reach * 0.3, hgt + reach, above));
		lean += clamp(dx / max(reach * 0.5, 1.0), -1.0, 1.0) * k;
	}
	return clamp(lean, -1.0, 1.0);
}

void fragment() {
	float t = TIME * speed;
	float up = rect_size.y - px.y;
	float col0 = floor(px.x / spacing);
	float cover = 0.0;
	float rim = 0.0;
	for (int i = -3; i <= 3; i++) {
		float id = col0 + float(i);
		float h = env_hash(vec2(id, seed));
		if (h > density) {
			continue;
		}
		vec2 r = env_hash2(vec2(id, seed + 2.0));
		float hgt = height * (1.0 - variation * r.x);
		float tt = up / hgt;
		if (tt < -0.05 || tt > 1.1) {
			continue;
		}
		float x0 = (id + 0.5 + (r.y - 0.5) * 0.6) * spacing;
		float s = clamp(tt, 0.0, 1.0);
		float wr = (sin(t * (0.9 + 0.5 * r.x) + s * 4.0 + h * 20.0) * 0.5 + sin(t * 1.7 + s * 9.0 + r.y * 12.0) * 0.25) * writhe * 18.0 * s;
		float lean = lean_to(x0, hgt) * hgt * 0.6;
		float xc = x0 + wr + lean * s * s;
		float w = thickness * 0.5 * sqrt(max(1.0 - s, 0.0)) * (0.85 + 0.3 * r.y) + 0.6;
		float d = (tt > 1.0) ? length(vec2(px.x - xc, up - hgt)) - 0.6 : abs(px.x - xc) - w;
		cover = max(cover, 1.0 - smoothstep(-0.7, 0.7, d));
		float pulse = 0.55 + 0.45 * sin(t * 2.0 + h * 10.0 - s * 5.0);
		rim = max(rim, exp(-max(d, 0.0) / 5.0) * pulse * (1.0 - smoothstep(-2.5, 0.5, -d)));
	}
	// The pool at their roots, and motes of void rising from it.
	float pool_a = pool * (1.0 - smoothstep(0.0, height * 0.35, up)) * (0.7 + 0.3 * env_noise(vec2(px.x * 0.02 + t * 0.2, seed)));
	vec2 mq = vec2(px.x, px.y + t * 28.0) / 26.0;
	vec2 mid = floor(mq);
	vec2 mr = env_hash2(mid + seed * 3.0);
	float mote = 0.0;
	if (env_hash(mid + seed) < motes * 0.5) {
		mote = (1.0 - smoothstep(0.5, 2.2, length((fract(mq) - 0.5 - (mr - 0.5) * 0.6) * 26.0))) * (1.0 - smoothstep(height * 0.2, height * 1.3, up));
	}
	vec4 c = vec4(color.rgb, pool_a);
	c = vec4(mix(c.rgb, glow_color.rgb, rim * 0.8), max(c.a, rim * 0.75));
	c = vec4(mix(c.rgb, color.rgb + glow_color.rgb * 0.06, cover), max(c.a, cover));
	c = vec4(mix(c.rgb, glow_color.rgb, mote), max(c.a, mote * 0.8));
	float side = clamp(min(px.x, rect_size.x - px.x) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(c.rgb, c.a * color.a * intensity * side);
}
