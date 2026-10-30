shader_type canvas_item;
render_mode blend_add;
// A dash's wake: speed lines streaming out behind the attacker. (MDSAttackFX: "dash_streak")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float w = rect_size.x / rect_size.y;
	float lines = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float y = (fx_hash(fi) - 0.5) * 1.5;
		float len = 0.4 + fx_hash(fi + 3.0) * 1.0;
		float x1 = w * 0.6 - progress * (0.6 + fx_hash(fi + 5.0)) * w * 1.6;
		float on = step(x1 - len, p.x) * step(p.x, x1);
		float along = clamp((p.x - x1 + len) / len, 0.0, 1.0);
		lines += fx_line(abs(p.y - y), 0.02 + 0.03 * along) * on * along;
	}
	float body = (1.0 - smoothstep(0.0, 0.5, abs(p.y))) * smoothstep(-w, w * 0.6, p.x) * 0.25;
	COLOR = fx_light(lines, lines * 0.6 + body, fx_fade(0.3));
}
