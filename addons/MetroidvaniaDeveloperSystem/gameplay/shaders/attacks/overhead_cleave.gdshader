shader_type canvas_item;
render_mode blend_add;
// A heavy cleave: a wide smear of the blade brought down from overhead. (MDSAttackFX: "overhead_cleave")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float head = mix(-2.7, 0.9, fx_ease_out(progress * 1.4));
	float tail = head - 2.0;
	float along = clamp((a - tail) / (head - tail), 0.0, 1.0);
	float inside = smoothstep(tail, tail + 0.4, a) * (1.0 - smoothstep(head - 0.2, head + 0.02, a));
	float inner = mix(0.62, 0.25, along);
	float band = smoothstep(inner - 0.05, inner + 0.05, r) * (1.0 - smoothstep(0.78, 0.86, r));
	float streaks = 0.6 + 0.4 * fx_noise(vec2(r * 18.0, a * 2.0));
	float edge = fx_line(abs(r - 0.82), 0.06);
	float core = edge * inside * along * 1.3;
	float glow = band * inside * along * along * streaks;
	COLOR = fx_light(core, glow, fx_fade(0.45));
}
