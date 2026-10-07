shader_type canvas_item;
// Snowfall: four depths of soft flakes drifting down, swaying, carried by the wind. With
// blizzard, gusts of driven snow streak across. MDSSnowfall draws a far plane behind the
// terrain (depth 1) and a near one in front of it.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

/// How fast the flakes fall (px/s).
uniform float fall_speed = 70.0;
/// Sideways drift (px/s): positive toward the right.
uniform float wind = 25.0;
/// How far the flakes sway as they fall.
uniform float sway : hint_range(0.0, 1.0) = 0.5;
uniform float flake_size = 3.0;
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform vec4 color : source_color = vec4(0.96, 0.97, 1.0, 0.9);
/// Driven snow: faster, slanted flakes and streaks of snow racing along.
uniform float blizzard : hint_range(0.0, 1.0) = 0.0;
/// 0 the near plane, 1 far away.
uniform float depth : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	px = VERTEX - rect_origin;
}

float flakes(vec2 p, float cell, float spd, float size, float amount, float salt) {
	float w = wind * (1.0 + blizzard * 6.0);
	vec2 q = p - vec2(w, spd * (1.0 + blizzard * 1.5)) * TIME * (cell / 60.0);
	vec2 g = q / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = env_hash(id + vec2(salt, seed));
	if (h > amount) {
		return 0.0;
	}
	vec2 c = 0.3 + 0.4 * env_hash2(id + vec2(seed, salt * 1.7));
	c.x += sin(TIME * (0.6 + h) + h * 30.0) * 0.18 * sway;
	vec2 d = (f - c) * cell;
	// Slanted and smeared in a blizzard.
	d.x += d.y * w / max(spd * 2.0, 1.0) * blizzard;
	d.y /= 1.0 + blizzard * 1.5;
	float s = size * (0.6 + 0.8 * fract(h * 13.7));
	return smoothstep(s, s * 0.25, length(d));
}

void fragment() {
	float k = mix(1.0, 0.5, depth);
	float s = flakes(px, 60.0 * k, fall_speed, flake_size * k, density, 1.0);
	s = max(s, 0.8 * flakes(px + vec2(17.0, 5.0), 44.0 * k, fall_speed * 0.8, flake_size * 0.8 * k, density, 2.0));
	s = max(s, 0.6 * flakes(px + vec2(3.0, 29.0), 30.0 * k, fall_speed * 0.6, flake_size * 0.6 * k, density, 3.0));
	s = max(s, 0.4 * flakes(px + vec2(11.0, 13.0), 20.0 * k, fall_speed * 0.45, flake_size * 0.45 * k, density, 4.0));
	float alpha = s * mix(1.0, 0.6, depth);
	if (blizzard > 0.0) {
		float drift = env_fbm(vec2((px.x - wind * 18.0 * TIME) / 300.0, px.y / 60.0) + seed, 4);
		float streak = env_noise(vec2((px.x - wind * 30.0 * TIME) / 180.0, px.y / 6.0 + seed));
		float b = smoothstep(0.45, 0.85, drift) * 0.35 + smoothstep(0.75, 0.95, streak) * 0.3;
		alpha = max(alpha, b * blizzard);
	}
	COLOR = vec4(color.rgb, alpha * color.a * intensity * env_edge(px));
}
