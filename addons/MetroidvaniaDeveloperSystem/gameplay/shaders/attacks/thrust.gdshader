shader_type canvas_item;
render_mode blend_add;
// A stab: a straight streak shooting forward, its tip blazing, speed lines beside it. (MDSAttackFX: "thrust")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float w = rect_size.x / rect_size.y;
	float t = fx_ease_out(progress * 1.6);
	float tip = mix(-w * 0.9, w * 0.95, t);
	float start = -w * 0.9 + (w * 1.6) * smoothstep(0.45, 1.0, progress);
	float on = step(start, p.x) * step(p.x, tip);
	float along = clamp((p.x - start) / max(tip - start, 0.001), 0.0, 1.0);
	float thick = 0.02 + 0.12 * along;
	float core = fx_line(abs(p.y), thick) * on;
	float glow = (1.0 - smoothstep(0.0, thick * 3.0, abs(p.y))) * on * along;
	float point_ = exp(-length(p - vec2(tip, 0.0)) * 9.0);
	float lines = 0.0;
	for (int i = 0; i < 4; i++) {
		float y = (fx_hash(float(i) + 3.0) - 0.5) * 1.2;
		float x0 = tip - 0.4 - fx_hash(float(i) + 7.0) * 0.8;
		lines += fx_line(abs(p.y - y), 0.025) * step(x0 - 0.5, p.x) * step(p.x, x0) * 0.5;
	}
	COLOR = fx_light(core + point_ * 1.5, glow + lines, fx_fade(0.55));
}
