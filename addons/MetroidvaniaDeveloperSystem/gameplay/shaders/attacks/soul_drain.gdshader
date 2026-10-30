shader_type canvas_item;
render_mode blend_add;
// A soul drained: wisps of light spiralling in from all round to the one who hit. (MDSAttackFX: "soul_drain")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float core = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float start = fx_hash(fi) * TAU;
		float t = clamp(progress * 1.3 - fx_hash(fi + 1.0) * 0.3, 0.0, 1.0);
		float rad = mix(0.95, 0.0, t);
		float ang = start + t * 4.0;
		vec2 c = vec2(cos(ang), sin(ang)) * rad;
		vec2 c2 = vec2(cos(ang - 0.5), sin(ang - 0.5)) * min(rad + 0.12, 0.95);
		core += fx_line(fx_segment(p, c2, c), 0.025) * step(0.001, t) * step(t, 0.999);
	}
	float heart = exp(-length(p) * 7.0) * smoothstep(0.3, 1.0, progress);
	COLOR = fx_light(core + heart, core * 0.6 + heart, fx_fade(0.7));
}
