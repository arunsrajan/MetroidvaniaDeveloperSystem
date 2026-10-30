shader_type canvas_item;
render_mode blend_mix;
// Electrocuted: arcs crawling over the body, its picture flickering bright and dark. (MDSAttackFX: "electrocute")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 p = fx_centered();
	vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
	float tick = floor(progress * 20.0);
	float flicker = fx_hash(tick + 1.0);
	float arcs = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 a = vec2(fx_hash(tick + fi * 3.0) - 0.5, fx_hash(tick + fi * 5.0) - 0.5) * 1.6;
		vec2 m = a + vec2(fx_hash(tick + fi * 7.0) - 0.5, fx_hash(tick + fi * 11.0) - 0.5) * 0.7;
		vec2 b = m + vec2(fx_hash(tick + fi * 13.0) - 0.5, fx_hash(tick + fi * 17.0) - 0.5) * 0.7;
		arcs += fx_line(fx_segment(p, a, m), 0.02) + fx_line(fx_segment(p, m, b), 0.02);
	}
	float on = 1.0 - smoothstep(0.85, 1.0, progress);
	vec3 c = behind * mix(0.5, 1.7, flicker) + glow_color.rgb * arcs * intensity + core_color.rgb * arcs * 0.5;
	float mask = 1.0 - smoothstep(0.8, 1.0, max(abs(p.x) / max(rect_size.x / rect_size.y, 0.001), abs(p.y)));
	COLOR = vec4(c, mask * on);
}
