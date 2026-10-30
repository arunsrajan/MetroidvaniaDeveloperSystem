shader_type canvas_item;
render_mode blend_add;
// Ice: a burst of crystal shards flung out, frost glittering where it struck. (MDSAttackFX: "ice_shatter")

#include "res://addons/MetroidvaniaDeveloperSystem/gameplay/shaders/attacks/attack_fx.gdshaderinc"

void fragment() {
	vec2 p = fx_centered();
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = fx_ease_out(progress * 1.2);
	float shards = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float ang = fi / 10.0 * TAU + fx_hash(fi) * 0.5;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 c = dir * t * (0.5 + fx_hash(fi + 1.0) * 0.4);
		vec2 lp = p - c;
		vec2 side = vec2(-dir.y, dir.x);
		float along = dot(lp, dir);
		float across = abs(dot(lp, side));
		float len = 0.14 + fx_hash(fi + 2.0) * 0.1;
		float shard = step(abs(along), len) * step(across, (len - abs(along)) * 0.35);
		shards += shard;
	}
	float frost = (1.0 - smoothstep(0.0, 0.45, r)) * (0.6 + 0.4 * fx_noise(p * 5.0)) * (1.0 - progress) * 0.7;
	float glint = 0.0;
	for (int i = 0; i < 8; i++) {
		float fi = float(i);
		vec2 g = (vec2(fx_hash(fi + 20.0), fx_hash(fi + 30.0)) - 0.5) * 1.1 * t;
		float tw = 0.5 + 0.5 * sin(progress * 30.0 + fi * 2.0);
		glint += exp(-length(p - g) * 60.0) * tw * 2.0;
	}
	COLOR = fx_light(clamp(shards, 0.0, 1.0) + glint, frost + shards * 0.4, fx_fade(0.6));
}
