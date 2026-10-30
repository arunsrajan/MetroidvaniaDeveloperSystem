shader_type canvas_item;
render_mode blend_add;
// Lightning: a jagged bolt cracking down onto the hit, forking, flickering, then a flash. (MDSAttackFX: "lightning_strike")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float flick = step(0.35, fx_hash(floor(progress * 24.0)));
	float bolt = 0.0;
	float glow = 0.0;
	vec2 a = vec2(0.0, -1.0);
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 b = vec2((fx_hash(fi + floor(progress * 8.0) * 3.0) - 0.5) * 0.5, -1.0 + (fi + 1.0) * 0.125);
		if (i == 7) {
			b = vec2(0.0);
		}
		float d = fx_segment(p, a, b);
		bolt += fx_line(d, 0.025);
		glow += 1.0 - smoothstep(0.0, 0.18, d);
		if (i == 3) {
			vec2 f = b + vec2(0.35, 0.3);
			float df = fx_segment(p, b, f);
			bolt += fx_line(df, 0.015) * 0.8;
			glow += (1.0 - smoothstep(0.0, 0.1, df)) * 0.6;
		}
		a = b;
	}
	float flash = exp(-length(p) * 5.0) * (1.0 - smoothstep(0.0, 0.5, progress));
	COLOR = fx_light(clamp(bolt, 0.0, 1.0) * mix(0.4, 1.0, flick) + flash, clamp(glow, 0.0, 1.0) * 0.6 * mix(0.3, 1.0, flick), fx_fade(0.5));
}
