shader_type canvas_item;
render_mode blend_add;
// Sparks thrown out from the hit, arcing down as they fly. (MDSAttackFX: "spark_burst")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float core = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		float ang = fx_hash(fi) * TAU;
		float speed = 0.6 + fx_hash(fi + 1.0) * 0.6;
		float t = fx_ease_out(progress) * speed;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 head = dir * t + vec2(0.0, progress * progress * 0.5);
		vec2 back = dir * max(t - 0.18, 0.0) + vec2(0.0, max(progress - 0.1, 0.0) * max(progress - 0.1, 0.0) * 0.5);
		core += fx_line(fx_segment(p, back, head), 0.03) * (1.0 - progress * 0.6);
	}
	float flash = exp(-length(p) * 7.0) * (1.0 - smoothstep(0.0, 0.3, progress));
	COLOR = fx_light(core + flash, core * 0.6 + flash, fx_fade(0.6));
}
