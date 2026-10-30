shader_type canvas_item;
render_mode blend_add;
// A crescent of light thrown forward, flying across and fading (a sword beam). (MDSAttackFX: "crescent_wave")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float t = fx_ease_out(progress);
	vec2 c = vec2(mix(-0.9, 0.9, t) * rect_size.x / rect_size.y, 0.0);
	float outer = length((p - c) * vec2(1.6, 1.0));
	float inner = length((p - c - vec2(-0.22, 0.0)) * vec2(1.6, 1.0));
	float moon = (1.0 - smoothstep(0.62, 0.68, outer)) * smoothstep(0.58, 0.66, inner);
	float glow = (1.0 - smoothstep(0.55, 0.9, outer)) * smoothstep(0.45, 0.7, inner);
	float trail = (1.0 - smoothstep(0.0, 0.5, abs(p.y))) * smoothstep(c.x - 1.2, c.x - 0.2, p.x) * step(p.x, c.x - 0.2) * 0.35;
	COLOR = fx_light(moon * 1.3, glow * 0.7 + trail, fx_fade(0.6));
}
