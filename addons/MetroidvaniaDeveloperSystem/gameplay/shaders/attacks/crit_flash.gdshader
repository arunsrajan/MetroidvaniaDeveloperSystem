shader_type canvas_item;
render_mode blend_add;
// A critical hit: a blinding cross flare and a burst of light. (MDSAttackFX: "crit_flash")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float t = fx_ease_out(progress * 2.0);
	float h = fx_line(abs(p.y), 0.04 * (1.0 - progress)) * (1.0 - smoothstep(0.0, 1.6 * t, abs(p.x)));
	float v = fx_line(abs(p.x), 0.04 * (1.0 - progress)) * (1.0 - smoothstep(0.0, 1.0 * t, abs(p.y)));
	float d1 = fx_line(abs(p.x - p.y) * 0.7071, 0.02) * (1.0 - smoothstep(0.0, 0.6 * t, r));
	float d2 = fx_line(abs(p.x + p.y) * 0.7071, 0.02) * (1.0 - smoothstep(0.0, 0.6 * t, r));
	float burst = 1.0 - smoothstep(0.0, 0.5 * t, r);
	float ring = fx_line(abs(r - t * 0.9), 0.04);
	COLOR = fx_light(h + v + burst * 1.3 + (d1 + d2) * 0.6, ring + burst * 0.4, fx_fade(0.3));
}
