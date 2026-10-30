shader_type canvas_item;
render_mode blend_add;
// A whirlwind: the blade swept round twice in a full circle. (MDSAttackFX: "spin_slash")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x) + PI;
	float head = fx_ease_out(progress * 1.2) * TAU * 2.0;
	float behind = mod(head - a, TAU);
	float trail = 1.0 - smoothstep(0.0, 2.6, behind);
	float d = abs(r - 0.72);
	float core = fx_line(d, 0.03 + 0.1 * trail) * trail * trail;
	float glow = (1.0 - smoothstep(0.0, 0.3, d)) * trail * 0.8 + (1.0 - smoothstep(0.0, 0.75, r)) * 0.12 * trail;
	COLOR = fx_light(core * 1.4, glow, fx_fade(0.6));
}
