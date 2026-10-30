shader_type canvas_item;
render_mode blend_add;
// Fire: a burst of flame licking up and out from the hit, embers flying. (MDSAttackFX: "fire_burst")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float t = fx_ease_out(progress * 1.3);
	vec2 q = vec2(p.x, p.y + progress * 0.4);
	float r = length(q * vec2(1.0, 0.85));
	float n = fx_fbm(vec2(p.x * 3.0, p.y * 3.0 + progress * 6.0));
	float flame = 1.0 - smoothstep(t * 0.75 - 0.2, t * 0.75 + 0.15, r + n * 0.45 - max(-p.y, 0.0) * 0.35);
	float hot = 1.0 - smoothstep(0.0, t * 0.45, r + n * 0.25);
	float embers = 0.0;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 e = vec2((fx_hash(fi) - 0.5) * 1.4 * t, -progress * (0.6 + fx_hash(fi + 2.0)) + 0.1);
		embers += exp(-length(p - e) * 45.0);
	}
	float fade = 1.0 - smoothstep(0.45, 1.0, progress);
	COLOR = fx_light(hot * 1.2 + embers, flame, fade);
}
