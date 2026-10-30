shader_type canvas_item;
render_mode blend_add;
// Wind: thin blades of air whipping across in curved streaks. (MDSAttackFX: "wind_cut")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float w = rect_size.x / rect_size.y;
	float core = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float y0 = (fi - 2.0) * 0.32 + (fx_hash(fi) - 0.5) * 0.15;
		float bend = 0.35 + fx_hash(fi + 1.0) * 0.3;
		float x = p.x / w;
		float curve = y0 + bend * (x * x - 0.3);
		float head = mix(-1.1, 1.3, fx_ease_out(progress * 1.4 - fi * 0.06));
		float along = clamp((x - head + 0.9) / 0.9, 0.0, 1.0) * step(x, head);
		float d = abs(p.y - curve);
		core += fx_line(d, 0.02 * along + 0.002) * along;
		glow += (1.0 - smoothstep(0.0, 0.1, d)) * along * 0.5;
	}
	COLOR = fx_light(core, glow, fx_fade(0.5));
}
