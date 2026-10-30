shader_type canvas_item;
render_mode blend_add;
// The flash where a blow lands: a four-pointed star with a soft ring. (MDSAttackFX: "impact_star")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = fx_ease_out(progress * 1.8);
	float spikes = pow(abs(cos(a * 2.0 + 0.4)), 8.0) * 0.8 + pow(abs(cos(a * 2.0 + 0.4 + PI * 0.25)), 16.0) * 0.4;
	float star = 1.0 - smoothstep(0.0, (0.15 + spikes * 0.85) * t, r);
	float ring = fx_line(abs(r - t * 0.85), 0.05) * (1.0 - progress);
	float hot = exp(-r * 9.0);
	COLOR = fx_light(star * 1.2 + hot, ring + star * 0.5, fx_fade(0.35));
}
