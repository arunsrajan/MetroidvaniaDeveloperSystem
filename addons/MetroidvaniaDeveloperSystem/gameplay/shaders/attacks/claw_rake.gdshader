shader_type canvas_item;
render_mode blend_add;
// Three claw marks torn across one after another, ragged at their ends. (MDSAttackFX: "claw_rake")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float core = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float t = clamp(progress * 2.2 - fi * 0.22, 0.0, 1.0);
		vec2 off = vec2(fi * 0.32 - 0.32, fi * 0.1 - 0.1);
		vec2 a = vec2(-0.6, -0.75) + off;
		vec2 b = mix(a, vec2(0.55, 0.7) + off, fx_ease_out(t));
		float d = fx_segment(p, a, b);
		float along = clamp(dot(p - a, b - a) / max(dot(b - a, b - a), 0.0001), 0.0, 1.0);
		float taper = sin(along * PI);
		float rag = 0.8 + 0.4 * fx_noise(p * 14.0 + fi);
		core += fx_line(d, 0.05 * taper * rag) * step(0.001, t);
		glow += (1.0 - smoothstep(0.0, 0.16 * taper, d)) * step(0.001, t) * 0.7;
	}
	COLOR = fx_light(core * 1.3, glow, fx_fade(0.5));
}
