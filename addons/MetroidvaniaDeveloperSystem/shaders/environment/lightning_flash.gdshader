shader_type canvas_item;
// The light of a lightning strike thrown over the rectangle: brightest around the bolt and
// up in the sky, fading down and away from it. MDSLightning animates `flash`.

render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.80, 0.86, 1.0, 1.0);
/// Where the bolt struck, across the rectangle (0..1).
uniform float bolt_x : hint_range(0.0, 1.0) = 0.5;
/// How much of the light is spread evenly over the sky, away from the bolt.
uniform float spread : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	vec2 uv = px / rect_size;
	float near_bolt = exp(-abs(uv.x - bolt_x) * rect_size.x / 260.0);
	float sky = mix(1.0, 0.4, uv.y);
	// Light flickers through the clouds.
	float clouds = 0.75 + 0.5 * env_fbm(px / 300.0 + vec2(seed, TIME * 0.2), 3);
	float a = flash * intensity * mix(near_bolt, 1.0, spread) * sky * clouds * env_edge(px);
	COLOR = vec4(color.rgb, clamp(a, 0.0, 1.0) * color.a);
}
