shader_type canvas_item;
render_mode blend_mix;
// Poison: a sickly cloud welling up from the hit, bubbles rising through it. (MDSAttackFX: "poison_cloud")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float t = fx_ease_out(progress * 1.3);
	float n = fx_fbm(p * 2.5 + vec2(progress * 0.6, -progress * 1.2));
	float r = length(p * vec2(0.9, 1.1));
	float cloud = 1.0 - smoothstep(t * 0.6, t * 0.6 + 0.35, r - n * 0.4);
	float bubbles = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		vec2 c = vec2((fx_hash(fi) - 0.5) * 1.0, 0.4 - fract(progress * (0.8 + fx_hash(fi + 1.0)) + fx_hash(fi + 2.0)) * 1.2);
		float d = length(p - c);
		bubbles += fx_line(abs(d - 0.05), 0.02);
	}
	float fade = fx_fade(0.45);
	vec3 c = mix(glow_color.rgb * 0.5, glow_color.rgb, n) + core_color.rgb * bubbles;
	COLOR = vec4(c * intensity, clamp(cloud * 0.75 + bubbles * cloud, 0.0, 1.0) * fade);
}
