shader_type canvas_item;
render_mode blend_add;
// A rising slash: an arc swept up from low in front, throwing sparks upward. (MDSAttackFX: "uppercut_arc")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float head = mix(1.5, -1.7, fx_ease_out(progress * 1.5));
	float tail = head + 1.7;
	float along = clamp((tail - a) / (tail - head), 0.0, 1.0);
	float inside = smoothstep(head - 0.02, head + 0.18, a) * step(a, tail);
	float thick = 0.02 + 0.15 * along;
	float d = abs(r - 0.66);
	float core = fx_line(d, thick) * inside * along * along;
	float glow = (1.0 - smoothstep(0.0, thick * 2.5, d)) * inside * along;
	float sparks = 0.0;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 s = vec2((fx_hash(fi) - 0.3) * 1.0, 0.4 - progress * (0.9 + fx_hash(fi + 4.0)) * 1.3);
		sparks += exp(-length(p - s) * 40.0) * step(0.15, progress);
	}
	COLOR = fx_light(core * 1.4 + sparks, glow * 0.8, fx_fade(0.5));
}
