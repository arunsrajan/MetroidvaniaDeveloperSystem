shader_type canvas_item;
render_mode blend_add;
// A slam into the ground: a dome of force bursting up off it and rolling out both ways, dust flying. (MDSAttackFX: "ground_slam")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	p.y -= 0.8;
	float t = fx_ease_out(progress);
	float r = length(p * vec2(1.0, 1.6));
	float front = t * 1.6;
	float ring = fx_line(abs(r - front), 0.05 + 0.1 * (1.0 - t)) * step(p.y, 0.0);
	float fill = (1.0 - smoothstep(0.0, front, r)) * step(p.y, 0.0) * 0.35 * (1.0 - t);
	float dust = smoothstep(0.55, 0.8, fx_fbm(vec2(p.x * 4.0, p.y * 6.0 - progress * 3.0))) * (1.0 - smoothstep(0.0, 0.5, -p.y)) * step(r, front + 0.2) * step(p.y, 0.0);
	float crack = fx_line(abs(p.y), 0.03) * step(abs(p.x), front * 1.1);
	COLOR = fx_light(ring * 1.2 + crack, fill + dust * 0.6, fx_fade(0.55));
}
