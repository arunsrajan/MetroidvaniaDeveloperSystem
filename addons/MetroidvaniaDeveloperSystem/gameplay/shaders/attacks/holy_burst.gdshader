shader_type canvas_item;
render_mode blend_add;
// Holy light: a radiant burst with rays fanning out and a ring of light. (MDSAttackFX: "holy_burst")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = fx_ease_out(progress * 1.4);
	float rays = pow(abs(sin(a * 6.0 + progress * 1.5)), 6.0) * (1.0 - smoothstep(0.0, t * 1.1, r));
	float ring = fx_line(abs(r - t * 0.8), 0.04);
	float halo = 1.0 - smoothstep(0.0, t * 0.55, r);
	float motes = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		vec2 m = vec2((fx_hash(fi) - 0.5) * 1.4, 0.5 - fx_hash(fi + 5.0) * 0.6 - progress * 0.6) * t;
		motes += exp(-length(p - m) * 55.0) * 1.5;
	}
	COLOR = fx_light(halo + ring + motes, rays * 0.9 + halo * 0.5, fx_fade(0.5));
}
