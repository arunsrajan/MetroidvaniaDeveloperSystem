shader_type canvas_item;
render_mode blend_add;
// A blade's arc: a bright crescent swept from above and behind down to the front, its tail thinning out. (MDSAttackFX: "slash_arc")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float head = mix(-1.95, 1.25, fx_ease_out(progress * 1.5));
	float tail = head - 1.7;
	float along = clamp((a - tail) / (head - tail), 0.0, 1.0);
	// Soft at the blade's leading edge.
	float inside = step(tail, a) * (1.0 - smoothstep(head - 0.18, head + 0.02, a));
	float thick = 0.02 + 0.17 * along;
	float d = abs(r - 0.7 + 0.06 * (1.0 - along));
	float core = fx_line(d, thick) * inside * along * along;
	float glow = (1.0 - smoothstep(0.0, thick * 2.6, d)) * inside * along;
	COLOR = fx_light(core * 1.4, glow * 0.8, fx_fade(0.5));
}
