shader_type canvas_item;
render_mode blend_add;
// A parry: a diamond of light snapping out from the clash of blades, sparks flying off it. (MDSAttackFX: "parry_flash")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float t = fx_ease_out(progress * 1.6);
	float dia = abs(p.x) + abs(p.y);
	float outline = fx_line(abs(dia - t * 0.9), 0.05);
	float inner = 1.0 - smoothstep(0.0, t * 0.5, dia);
	float sparks = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		vec2 dir = vec2(cos(fi * PI * 0.5 + 0.785), sin(fi * PI * 0.5 + 0.785));
		sparks += fx_line(fx_segment(p, dir * t * 0.4, dir * t * 1.1), 0.03);
	}
	COLOR = fx_light(outline * 1.3 + inner + sparks, outline * 0.8 + inner * 0.4, fx_fade(0.4));
}
