shader_type canvas_item;
render_mode blend_add;
// A blocked hit: hexagons of a shield lighting up as a ripple runs out from the blow. (MDSAttackFX: "shield_ripple")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	vec2 q = p * 6.0;
	vec2 g = vec2(1.0, 1.7320508);
	vec2 a1 = mod(q, g) - g * 0.5;
	vec2 b1 = mod(q - g * 0.5, g) - g * 0.5;
	vec2 hx = dot(a1, a1) < dot(b1, b1) ? a1 : b1;
	vec2 ah = abs(hx);
	float edge = max(dot(ah, normalize(vec2(1.0, 1.7320508))), ah.x);
	float lines = smoothstep(0.42, 0.5, edge);
	float wave = exp(-pow((r - fx_ease_out(progress) * 0.95) * 7.0, 2.0));
	float dome = (1.0 - smoothstep(0.85, 0.95, r));
	float hit = exp(-r * 6.0) * (1.0 - progress);
	COLOR = fx_light(lines * wave * dome + hit, (wave * 0.4 + 0.08) * dome + lines * 0.2 * dome, fx_fade(0.55));
}
