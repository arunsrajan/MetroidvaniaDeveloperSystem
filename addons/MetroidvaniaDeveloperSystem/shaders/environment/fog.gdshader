shader_type canvas_item;
// Drifting fog or mist: warped banks rolling slowly sideways, even over the whole rectangle
// or hugging its bottom (ground fog).

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.74, 0.79, 0.84, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.5;
/// Drift (px/s): positive toward the right.
uniform float speed = 18.0;
/// Size of the banks (px).
uniform float scale = 380.0;
/// 0 even, 1 lies along the bottom of the rectangle.
uniform float ground : hint_range(0.0, 1.0) = 0.0;
/// How high ground fog reaches, as a share of the rectangle's height.
uniform float ground_height : hint_range(0.05, 1.0) = 0.35;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	vec2 p = px + vec2(seed * 173.0, seed * 59.0);
	float t = TIME;
	vec2 q = vec2(p.x - t * speed, p.y) / scale;
	vec2 warp = vec2(env_fbm(q * 0.6 + vec2(t * 0.02, 0.0), 4), env_fbm(q * 0.6 + vec2(4.1, -t * 0.015), 4));
	float f = env_fbm(q + warp * 1.2, 5);
	float f2 = env_fbm(vec2(p.x - t * speed * 1.7, p.y) / (scale * 0.45) + warp, 4);
	float fog = smoothstep(0.25, 0.85, f * 0.7 + f2 * 0.45);
	float v = px.y / rect_size.y;
	float low = smoothstep(1.0 - ground_height, 1.0 - ground_height * 0.15, v);
	float k = mix(1.0, low, ground);
	float a = fog * density * k * (0.55 + 0.45 * density);
	COLOR = vec4(color.rgb * mix(0.85, 1.05, f2), a * color.a * intensity * env_edge(px));
}
