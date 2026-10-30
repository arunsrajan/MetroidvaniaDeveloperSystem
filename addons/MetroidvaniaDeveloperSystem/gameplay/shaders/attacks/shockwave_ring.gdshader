shader_type canvas_item;
render_mode blend_mix;
// A shockwave: a ring racing outward, bending what is behind it. (MDSAttackFX: "shockwave_ring")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float t = fx_ease_out(progress);
	float front = t * 0.95;
	float d = r - front;
	float band = exp(-d * d * 300.0) * (1.0 - progress);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	vec2 bend = dir * band * 0.03 * vec2(rect_size.y / rect_size.x, 1.0);
	vec3 behind = texture(screen_tex, SCREEN_UV - bend).rgb;
	float ring = fx_line(abs(d), 0.025) * (1.0 - progress);
	vec3 c = behind + glow_color.rgb * band * 0.5 * intensity + core_color.rgb * ring * intensity;
	float a = clamp(band * 4.0 + ring, 0.0, 1.0) * step(r, 1.0);
	COLOR = vec4(c, a);
}
