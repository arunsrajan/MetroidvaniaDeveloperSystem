shader_type canvas_item;
render_mode blend_mix;
// A splash of ink thrown from the wound, its blots spreading and drying away. (MDSAttackFX: "ink_splash")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = fx_ease_out(progress * 1.4);
	float reach = t * (0.45 + 0.5 * fx_noise(vec2(a * 2.5, seed)));
	float body = 1.0 - smoothstep(reach - 0.05, reach, r * (0.8 + 0.4 * fx_noise(p * 5.0)));
	float blots = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float ang = fx_hash(fi + 11.0) * TAU;
		vec2 c = vec2(cos(ang), sin(ang)) * t * (0.6 + fx_hash(fi + 12.0) * 0.35) + vec2(0.0, progress * progress * 0.3);
		blots += 1.0 - smoothstep(0.04, 0.09, length(p - c) / (0.6 + fx_hash(fi + 13.0)));
	}
	float ink = clamp(body + blots, 0.0, 1.0) * fx_fade(0.4);
	vec3 c = mix(glow_color.rgb * 0.35, glow_color.rgb, smoothstep(0.0, 0.6, r));
	COLOR = vec4(c, ink * 0.95);
}
