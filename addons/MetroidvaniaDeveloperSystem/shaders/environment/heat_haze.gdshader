shader_type canvas_item;
// Heat haze: what is behind the rectangle shimmers, rippling upward, strongest low down
// (over lava, a forge, a desert floor).

render_mode blend_mix, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
/// How far things are bent (px).
uniform float strength = 4.0;
/// How fast the ripples rise (px/s).
uniform float speed = 40.0;
/// Size of the ripples (px).
uniform float scale = 60.0;
/// 0 even, 1 strongest along the bottom, fading out toward the top.
uniform float rise : hint_range(0.0, 1.0) = 0.6;
/// A warm cast over the haze (alpha: how much).
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.40, 0.0);

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	vec2 q = vec2(px.x, px.y + TIME * speed) / scale;
	vec2 n = vec2(env_noise(q + seed) - 0.5, env_noise(q * 1.3 + vec2(7.1, seed)) - 0.5);
	n += 0.5 * vec2(env_noise(q * 2.7 + 3.0) - 0.5, 0.0);
	float v = px.y / rect_size.y;
	float k = mix(1.0, v, rise) * env_edge(px) * intensity;
	vec2 offs = n * strength * k * SCREEN_PIXEL_SIZE * 2.0;
	vec3 c = texture(screen_tex, SCREEN_UV + offs).rgb;
	c = mix(c, tint.rgb, tint.a * k);
	COLOR = vec4(c, 1.0);
}
