shader_type canvas_item;
// Cobwebs (MDSCobwebs): spider webs strung across the rectangle's corners (and a whole one in its
// middle if you like): spokes from the corner, sagging rings between them, some torn, dew glinting
// along the threads. They tremble while something moves through them (`tremble`, set by the node).

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.92, 0.92, 0.96, 0.55);
uniform vec4 dew_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
/// Which webs: 1 top-left, 2 top-right, 4 bottom-left, 8 bottom-right, 16 a whole one in the middle.
uniform int corners = 3;
uniform float web_radius = 150.0;
uniform int spokes = 9;
uniform int rings = 9;
/// How much the rings sag between spokes.
uniform float sag : hint_range(0.0, 1.0) = 0.35;
uniform float thickness = 1.0;
/// Dew drops along the threads.
uniform float dew : hint_range(0.0, 1.0) = 0.5;
/// Torn pieces of ring.
uniform float torn : hint_range(0.0, 1.0) = 0.15;
/// How hard it trembles now (0..1).
uniform float tremble = 0.0;

void vertex() {
	px = VERTEX - rect_origin;
}

// A web centred on `c`, its spokes from angle `a0` over `span` (radians; 2pi: a whole web).
// Returns its threads' coverage; `dw` its dew.
float web(vec2 p, vec2 c, float a0, float span, float rad, float salt, out float dw) {
	dw = 0.0;
	vec2 q = p - c;
	float r = length(q);
	if (r > rad + 3.0 || r < 0.5) {
		return 0.0;
	}
	bool whole = span > 6.0;
	float u = mod(atan(q.y, q.x) - a0 + 12.566, 6.2832);
	if (!whole && u > span) {
		return 0.0;
	}
	float n = float(max(spokes, 3));
	float seg = whole ? span / n : span / (n - 1.0);
	float su = u / seg;
	float si = round(su);
	float shake = tremble * sin(TIME * 38.0 + r * 0.15 + salt) * 2.5 * (r / rad);
	float w = 0.5 * thickness;
	// The spokes, wobbling a little when it trembles.
	float spoke_d = abs((su - si) * seg * r + shake * 0.5);
	float spoke = (1.0 - smoothstep(w, w + 0.9, spoke_d)) * (1.0 - smoothstep(rad - 4.0, rad, r));
	// The rings: polygon sides between two spokes, sagging toward the middle.
	float fr = fract(su);
	float lowsp = floor(su);
	float droop = 1.0 - sag * 0.18 * sin(fr * 3.1416);
	float s = (r - shake) / droop;
	float nr = float(max(rings, 1));
	float kf = pow(clamp(s / rad, 0.0, 1.0), 1.0 / 1.25) * nr;
	float k = max(round(kf), 1.0);
	float rk = rad * pow(k / nr, 1.25);
	float ring_d = abs(s - rk) * droop;
	float keep = step(torn, env_hash(vec2(lowsp + salt * 13.0, k + seed)));
	if (!whole && lowsp >= n - 1.0) {
		keep = 0.0;
	}
	float ring = (1.0 - smoothstep(w, w + 0.9, ring_d)) * keep;
	// Dew: drops at a few places along the rings.
	float slot = floor(fr * 4.0);
	if (env_hash(vec2(lowsp * 4.0 + slot + salt, k + seed * 3.0)) < dew * keep) {
		float fc = (slot + 0.5) / 4.0;
		float along = (fr - fc) * seg * r;
		float dd = length(vec2(along, s - rk));
		float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + lowsp * 3.0 + k);
		dw = (1.0 - smoothstep(0.8 * thickness, 1.8 * thickness, dd)) * twinkle;
	}
	return max(spoke, ring);
}

void fragment() {
	float total = 0.0;
	float dew_a = 0.0;
	float d;
	vec2 sz = rect_size;
	if ((corners & 1) != 0) {
		total = max(total, web(px, vec2(0.0), 0.0, 1.5708, web_radius, 1.0, d));
		dew_a = max(dew_a, d);
	}
	if ((corners & 2) != 0) {
		total = max(total, web(px, vec2(sz.x, 0.0), 1.5708, 1.5708, web_radius, 2.0, d));
		dew_a = max(dew_a, d);
	}
	if ((corners & 4) != 0) {
		total = max(total, web(px, vec2(0.0, sz.y), 4.7124, 1.5708, web_radius, 3.0, d));
		dew_a = max(dew_a, d);
	}
	if ((corners & 8) != 0) {
		total = max(total, web(px, sz, 3.1416, 1.5708, web_radius, 4.0, d));
		dew_a = max(dew_a, d);
	}
	if ((corners & 16) != 0) {
		total = max(total, web(px, sz * 0.5, 0.0, 6.2832, min(min(sz.x, sz.y) * 0.48, web_radius * 1.4), 5.0, d));
		dew_a = max(dew_a, d);
	}
	vec3 c = mix(color.rgb, dew_color.rgb, dew_a);
	float a = max(total * color.a, dew_a * dew_color.a);
	COLOR = vec4(c, a * intensity);
}
