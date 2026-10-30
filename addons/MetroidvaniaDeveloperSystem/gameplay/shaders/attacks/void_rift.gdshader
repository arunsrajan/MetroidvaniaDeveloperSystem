shader_type canvas_item;
render_mode blend_mix;
// Void: a rift torn open where it struck, swirling into darkness, its rim burning. (MDSAttackFX: "void_rift")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float open_ = sin(min(progress * 1.4, 1.0) * PI);
	float swirl = fx_fbm(vec2(a * 2.0 + r * 4.0 - progress * 6.0, r * 3.0));
	float size = 0.55 * open_;
	float hole = 1.0 - smoothstep(size - 0.1, size + 0.05, r + (swirl - 0.5) * 0.25);
	float rim = fx_line(abs(r + (swirl - 0.5) * 0.25 - size), 0.07) * open_;
	float wisps = smoothstep(0.55, 0.75, swirl) * (1.0 - smoothstep(size, size + 0.4, r)) * open_;
	vec3 dark = mix(vec3(0.02, 0.0, 0.04), glow_color.rgb * 0.25, swirl * 0.5);
	vec3 c = mix(glow_color.rgb * intensity, dark, hole) + core_color.rgb * rim * intensity;
	COLOR = vec4(c, clamp(hole + rim + wisps * 0.6, 0.0, 1.0));
}
