shader_type canvas_item;
// Gnat swarm (MDSGnatSwarm): clouds of tiny gnats buzzing around swarm centres that drift about,
// wings catching the light; a swarm drawn to the bodies that come near (`bodies`, sent by the node)
// gathers around them.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.08, 0.08, 0.05, 0.9);
/// Their wings catching the light (its alpha: how much).
uniform vec4 glint_color : source_color = vec4(0.78, 0.82, 0.62, 0.6);
/// How many of the places a swarm could be have one.
uniform float swarm_density : hint_range(0.0, 1.0) = 0.5;
/// Average distance between swarms (px).
uniform float swarm_spacing = 320.0;
/// How far a swarm spreads (px).
uniform float swarm_size = 55.0;
/// Gnats in a swarm.
uniform int gnats = 22;
uniform float gnat_size = 1.4;
/// How fast they buzz about.
uniform float buzz = 1.0;
/// How fast the swarms drift.
uniform float drift = 1.0;
/// How much a swarm is drawn to a body near it.
uniform float lure : hint_range(0.0, 1.0) = 0.6;
uniform float lure_radius = 260.0;
uniform vec2 bodies[4];
uniform int body_count = 0;

void vertex() {
	px = VERTEX - rect_origin;
}

vec2 swarm_centre(vec2 id, float t, out float alive) {
	float h = env_hash(id + seed);
	alive = step(h, swarm_density);
	vec2 r = env_hash2(id + seed * 2.1);
	vec2 c = (id + 0.5 + (r - 0.5) * 0.4) * swarm_spacing + vec2(sin(t * 0.13 * drift + r.x * 6.283), sin(t * 0.11 * drift + r.y * 6.283)) * swarm_spacing * 0.22;
	float best = 1e9;
	vec2 target = c;
	for (int i = 0; i < 4; i++) {
		if (i >= body_count) {
			break;
		}
		float d = length(bodies[i] - c);
		if (d < best) {
			best = d;
			target = bodies[i] + vec2(sin(t * 0.7 + r.x * 6.0) * 20.0, -30.0);
		}
	}
	return mix(c, target, lure * (1.0 - smoothstep(lure_radius * 0.4, lure_radius, best)));
}

void fragment() {
	float t = TIME;
	vec2 id0 = floor(px / swarm_spacing);
	float a = 0.0;
	float gl = 0.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 id = id0 + vec2(float(i), float(j));
			float alive;
			vec2 c = swarm_centre(id, t, alive);
			if (alive < 0.5 || length(px - c) > swarm_size * 1.7 + 4.0) {
				continue;
			}
			for (int k = 0; k < 48; k++) {
				if (k >= gnats) {
					break;
				}
				float fk = float(k);
				vec2 r = env_hash2(id * 13.1 + vec2(fk, seed));
				float bt = t * buzz * (2.0 + 3.0 * r.x);
				vec2 off = vec2(sin(bt + r.y * 6.283) + 0.5 * sin(bt * 2.7 + fk), cos(bt * 1.3 + r.x * 6.283) + 0.5 * sin(bt * 3.1 + fk * 1.7)) * swarm_size * (0.25 + 0.4 * r.y);
				float d = length(px - c - off);
				float dot_a = 1.0 - smoothstep(gnat_size * 0.5, gnat_size + 0.6, d);
				a = max(a, dot_a);
				gl = max(gl, dot_a * step(0.5, fract(bt * 4.0 + r.x)));
			}
		}
	}
	vec3 c = mix(color.rgb, glint_color.rgb, gl * glint_color.a);
	COLOR = vec4(c, a * color.a * intensity * env_edge(px));
}
