shader_type canvas_item;
render_mode blend_mix;
// A shadow's bite: dark jaws snapping shut on the hit, their edges glowing. (MDSAttackFX: "shadow_bite")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	// Open, then snapping shut by half way.
	float t = clamp(progress / 0.45, 0.0, 1.0);
	float close_ = t * t * t;
	float gap = mix(0.75, 0.0, close_);
	float teeth = abs(fract(p.x * 4.0) - 0.5) * 0.25;
	float upper = smoothstep(-gap - 0.02, -gap + 0.02, -p.y - teeth) * step(abs(p.x), 0.9 - abs(p.y) * 0.3);
	float lower = smoothstep(-gap - 0.02, -gap + 0.02, p.y - teeth) * step(abs(p.x), 0.9 - abs(p.y) * 0.3);
	float jaw = clamp(upper + lower, 0.0, 1.0) * (1.0 - smoothstep(0.75, 0.95, length(p)));
	float edge = (fx_line(abs(-p.y - teeth + gap), 0.05) + fx_line(abs(p.y - teeth + gap), 0.05)) * step(length(p), 0.9);
	float snap = exp(-length(p) * 6.0) * smoothstep(0.4, 0.5, progress) * (1.0 - smoothstep(0.5, 0.8, progress));
	float fade = fx_fade(0.55);
	vec3 c = mix(vec3(0.03, 0.0, 0.05), glow_color.rgb * intensity, clamp(edge + snap, 0.0, 1.0));
	COLOR = vec4(c, clamp(jaw * 0.9 + edge + snap, 0.0, 1.0) * fade);
}
