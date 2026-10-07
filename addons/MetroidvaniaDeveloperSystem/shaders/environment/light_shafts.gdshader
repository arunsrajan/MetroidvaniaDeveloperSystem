shader_type canvas_item;
// Shafts of light slanting down from openings above (god rays), shimmering slowly, with
// dust motes drifting in them. Added onto what is behind.

render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.94, 0.78, 0.6);
/// Slant of the shafts (degrees): positive leans toward the right as they go down.
uniform float angle_deg : hint_range(-60.0, 60.0) = 18.0;
/// Average distance between shafts (px).
uniform float spread = 150.0;
/// Soft or crisp edges.
uniform float softness : hint_range(0.0, 1.0) = 0.5;
/// How far down they reach, as a share of the rectangle's height.
uniform float reach : hint_range(0.05, 1.0) = 0.8;
/// How much they waver.
uniform float shimmer : hint_range(0.0, 1.0) = 0.5;
/// Dust motes drifting in the light.
uniform float motes : hint_range(0.0, 1.0) = 0.4;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	vec2 r = env_rotate(px - vec2(rect_size.x * 0.5, 0.0), radians(angle_deg));
	float x = r.x + seed * 500.0;
	float t = TIME * shimmer;
	float b = env_noise(vec2(x / spread, t * 0.08)) * 0.62 + env_noise(vec2(x / (spread * 0.37), 3.0 + t * 0.13)) * 0.38;
	float shafts = smoothstep(mix(0.58, 0.38, softness), mix(0.62, 0.9, softness), b);
	float v = px.y / rect_size.y;
	float fade = (1.0 - smoothstep(0.0, reach, v)) * smoothstep(0.0, 0.06, v);
	float a = shafts * fade;
	if (motes > 0.0) {
		vec2 q = px + vec2(TIME * 6.0, -TIME * 9.0);
		vec2 g = q / 22.0;
		vec2 id = floor(g);
		float h = env_hash(id + vec2(seed, 2.0));
		if (h < motes * 0.25) {
			vec2 d = (fract(g) - (0.25 + 0.5 * env_hash2(id))) * 22.0;
			float m = smoothstep(1.3, 0.2, length(d)) * (0.5 + 0.5 * sin(TIME * 2.0 + h * 40.0));
			a += m * shafts * 1.5;
		}
	}
	COLOR = vec4(color.rgb, clamp(a, 0.0, 1.0) * color.a * intensity * env_edge(px));
}
