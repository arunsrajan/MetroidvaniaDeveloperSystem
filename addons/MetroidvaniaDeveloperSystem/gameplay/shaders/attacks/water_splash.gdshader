shader_type canvas_item;
render_mode blend_add;
// Water: a crown of spray bursting up from the hit and drops falling back. (MDSAttackFX: "water_splash")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float core = 0.0;
	for (int i = 0; i < 16; i++) {
		float fi = float(i);
		float ang = -PI * 0.5 + (fx_hash(fi) - 0.5) * 2.2;
		float speed = 1.0 + fx_hash(fi + 1.0) * 0.8;
		float t = progress;
		vec2 drop = vec2(cos(ang), sin(ang)) * speed * t + vec2(0.0, 2.2 * t * t);
		float size = 0.035 + fx_hash(fi + 2.0) * 0.03;
		core += 1.0 - smoothstep(size * 0.5, size, length((p - drop) * vec2(1.0, 0.7)));
	}
	float crown = fx_line(abs(length(p * vec2(1.0, 2.5)) - fx_ease_out(progress) * 0.6), 0.05) * step(0.0, p.y + 0.1);
	COLOR = fx_light(clamp(core, 0.0, 1.0) * 0.9, crown + core * 0.5, fx_fade(0.6));
}
