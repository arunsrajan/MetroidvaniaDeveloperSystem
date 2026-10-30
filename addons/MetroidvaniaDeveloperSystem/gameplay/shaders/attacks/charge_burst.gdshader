shader_type canvas_item;
render_mode blend_add;
// A charged blow: motes gathering into the point, then a burst of light let loose. (MDSAttackFX: "charge_burst")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float gather = 1.0 - smoothstep(0.0, 0.5, progress);
	float motes = 0.0;
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		float ang = fi / 12.0 * TAU + fx_hash(fi) * 0.4;
		float dist = mix(0.95, 0.05, clamp(progress * 2.0 + fx_hash(fi + 2.0) * 0.2, 0.0, 1.0));
		motes += exp(-length(p - vec2(cos(ang), sin(ang)) * dist) * 30.0);
	}
	float t = clamp((progress - 0.45) * 2.0, 0.0, 1.0);
	float burst = (1.0 - smoothstep(0.0, 0.2 + t * 0.9, r)) * step(0.45, progress) * (1.0 - t);
	float ring = fx_line(abs(r - t * 0.95), 0.06) * step(0.45, progress);
	float rays = pow(abs(cos(a * 4.0)), 12.0) * (1.0 - smoothstep(0.0, 1.0, r)) * step(0.45, progress) * (1.0 - t);
	float hold = exp(-r * 6.0) * gather;
	COLOR = fx_light(motes * gather + burst * 1.5 + hold, ring + rays, fx_fade(0.75));
}
