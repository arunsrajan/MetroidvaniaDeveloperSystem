shader_type canvas_item;
render_mode blend_mix;
// A body hit hard: its picture split into red, green and blue and shaken, then settling back. (MDSAttackFX: "chromatic_hit")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 p = fx_centered();
	float k = 1.0 - fx_ease_out(progress);
	float shake = (fx_hash(floor(progress * 30.0)) - 0.5) * 0.012 * k;
	vec2 off = vec2(0.008 * k + shake, shake * 0.5);
	float r = texture(screen_tex, SCREEN_UV + off).r;
	float g = texture(screen_tex, SCREEN_UV).g;
	float b = texture(screen_tex, SCREEN_UV - off).b;
	vec3 c = mix(vec3(r, g, b), glow_color.rgb, 0.25 * k * k);
	float mask = 1.0 - smoothstep(0.7, 1.0, max(abs(p.x) / max(rect_size.x / rect_size.y, 0.001), abs(p.y)));
	COLOR = vec4(c, mask * step(progress, 0.999));
}
