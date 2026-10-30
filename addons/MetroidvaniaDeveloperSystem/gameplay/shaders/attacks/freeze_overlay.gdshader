shader_type canvas_item;
render_mode blend_mix;
// Frozen: the body tinted icy, frost creeping in from its edges, thawing away at the end. (MDSAttackFX: "freeze_overlay")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 p = fx_centered();
	vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
	float hold = smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.75, 1.0, progress));
	float lum = dot(behind, vec3(0.3, 0.59, 0.11));
	vec3 ice = mix(vec3(lum), glow_color.rgb, 0.45) + vec3(0.05, 0.1, 0.15);
	float edge = max(abs(p.x) / max(rect_size.x / rect_size.y, 0.001), abs(p.y));
	float frost = smoothstep(0.55, 0.95, edge + fx_fbm(p * 6.0) * 0.4) * hold;
	float crystals = pow(fx_noise(p * 18.0), 6.0) * 2.5 * frost;
	vec3 c = mix(behind, ice, hold * 0.8) + core_color.rgb * (frost * 0.5 + crystals);
	float mask = 1.0 - smoothstep(0.85, 1.0, edge);
	COLOR = vec4(c, mask * step(0.001, hold));
}
