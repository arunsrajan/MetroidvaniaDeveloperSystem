shader_type canvas_item;
// Falling rocks: stones break off at the top of the rectangle (put it under a ceiling) and drop,
// tumbling, to crash on the ground in a puff of dust and a spray of chips. They pile up there as
// rubble, a heap of packed stones `rubble_height` px high resting on the rectangle's bottom edge
// (the ground), and pebbles trickle down between them.

render_mode blend_mix;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 rock_color : source_color = vec4(0.47, 0.42, 0.37, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.20, 0.17, 0.15, 1.0);
uniform vec4 dust_color : source_color = vec4(0.66, 0.60, 0.52, 0.75);
/// How often rocks fall (0: never).
uniform float rate : hint_range(0.0, 1.0) = 0.5;
/// The size of a big rock (px).
uniform float rock_size = 18.0;
/// How fast they fall (px/s²).
uniform float gravity = 1400.0;
/// How much rubble lies on the ground.
uniform float rubble : hint_range(0.0, 1.0) = 0.7;
/// How high the rubble heap rises (px).
uniform float rubble_height = 60.0;
uniform float dust : hint_range(0.0, 1.0) = 0.7;
uniform float pebbles : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	px = VERTEX - rect_origin;
}

// The rubble heap's height (px) at x.
float heap_at(float x) {
	float sides = smoothstep(0.0, rock_size * 2.5, x) * smoothstep(rect_size.x, rect_size.x - rock_size * 2.5, x);
	return rubble_height * rubble * (0.45 + 0.55 * env_fbm(vec2(x / 70.0, seed), 3)) * sides;
}

// A chunky stone around the origin of radius r: below 0 inside. Its outline is chipped.
float stone(vec2 p, float r, float id) {
	float a = atan(p.y, p.x);
	float chip = (env_noise(vec2(a * 1.6 + id * 7.0, id)) - 0.5) * 0.4 + (env_noise(vec2(a * 4.5 + id * 3.0, id + 2.0)) - 0.5) * 0.14;
	vec2 q = abs(p) / vec2(r, r * 0.82);
	return pow(pow(q.x, 3.0) + pow(q.y, 3.0), 1.0 / 3.0) - (1.0 + chip);
}

vec3 stone_color(vec2 q, float r, float id) {
	// Lit from above, its faces flecked.
	float lit = clamp(0.62 - q.y / max(r, 1.0) * 0.45, 0.0, 1.0);
	float fleck = env_noise(q / 3.5 + vec2(id * 5.0, id));
	return mix(rock_dark.rgb, rock_color.rgb, lit * (0.7 + 0.35 * fleck));
}

void fragment() {
	vec2 p = px;
	float ground = rect_size.y;
	float t = TIME;
	vec3 col = vec3(0.0);
	float alpha = 0.0;

	// The rubble heap: stones packed together, dark gaps between them.
	float heap = heap_at(p.x);
	float top = ground - heap;
	if (heap > 0.5 && p.y > top - 1.5) {
		float cell = rock_size * 0.62;
		vec2 v = env_voronoi(p / cell + vec2(seed * 3.1, 0.0));
		float gap = smoothstep(0.02, 0.16, v.y - v.x);
		float tone = env_noise(floor(p / cell + vec2(seed * 3.1, 0.0)) * 1.7 + seed);
		// Each stone rounded: lighter at its middle.
		float round_lit = clamp(1.15 - v.x * 1.1, 0.0, 1.0);
		vec3 c = mix(rock_dark.rgb, rock_color.rgb, (0.3 + 0.65 * tone) * round_lit);
		c = mix(rock_dark.rgb * 0.5, c, gap);
		c *= mix(0.7, 1.05, smoothstep(ground, top, p.y));
		col = c;
		alpha = smoothstep(top - 1.5, top + 1.5, p.y);
	}

	// Rocks: in lanes across the rectangle, each dropping now and then.
	float lane_w = rock_size * 3.2;
	float lane = floor(p.x / lane_w);
	// Two lanes each side: the chips and dust of a rock reach that far.
	for (int k = -2; k <= 2; k++) {
		float li = lane + float(k);
		for (int slot = 0; slot < 2; slot++) {
			float id = li * 2.0 + float(slot);
			if (env_hash(vec2(id, seed)) > rate) {
				continue;
			}
			float size = rock_size * (0.55 + 0.8 * env_hash(vec2(id, seed + 1.0)));
			float x0 = (li + 0.2 + 0.6 * env_hash(vec2(id, seed + 2.0))) * lane_w;
			float land = ground - heap_at(x0) - size * 0.5;
			float drop = land + size * 0.5;
			float fall = sqrt(2.0 * max(drop, 1.0) / gravity);
			float period = fall + 0.7 + 3.0 * env_hash(vec2(id, seed + 3.0)) * (1.6 - rate);
			float tt = t + period * env_hash(vec2(id, seed + 4.0));
			float n = floor(tt / period);
			float life = tt - n * period;
			float sx = x0 + (env_hash(vec2(id, n)) - 0.5) * lane_w * 0.4;
			float spin = (env_hash(vec2(id + 9.0, n)) - 0.5) * 9.0;
			if (life < fall) {
				// Falling, tumbling.
				float y = -size * 0.5 + 0.5 * gravity * life * life;
				vec2 q = env_rotate(p - vec2(sx, y), spin * life);
				float d = stone(q, size, id + n);
				if (d < 0.08) {
					float a = smoothstep(0.08, -0.08, d);
					col = mix(col, stone_color(q, size, id + n), a);
					alpha = max(alpha, a);
				}
			} else {
				float since = life - fall;
				vec2 hit = vec2(sx, land);
				// Chips flung up and out, falling back.
				if (since < 0.7) {
					for (int j = 0; j < 4; j++) {
						float fj = float(j);
						float ang = mix(-2.7, -0.45, env_hash(vec2(id + fj * 13.0, n)));
						float speed = 90.0 + 170.0 * env_hash(vec2(id + fj * 7.0, n + 1.0));
						vec2 cp = hit + vec2(cos(ang), sin(ang)) * speed * since + vec2(0.0, 0.5 * gravity * since * since);
						if (cp.y < ground - heap_at(cp.x)) {
							vec2 cq = env_rotate(p - cp, since * 12.0 + fj);
							float cr = size * (0.22 + 0.14 * env_hash(vec2(fj, id)));
							float cd = stone(cq, cr, id + fj + n);
							if (cd < 0.1) {
								float a = smoothstep(0.1, -0.1, cd);
								col = mix(col, stone_color(cq, cr, id + fj), a);
								alpha = max(alpha, a);
							}
						}
					}
				}
				// A puff of dust where it hit.
				if (dust > 0.0 && since < 1.4) {
					float grow = min(size * (1.2 + since * 5.0), lane_w * 1.15);
					vec2 dq = (p - hit - vec2(0.0, -since * 22.0)) / vec2(1.7, 1.0);
					float puff = smoothstep(grow, grow * 0.25, length(dq));
					puff *= smoothstep(0.15, 0.55, env_fbm(p / 18.0 + vec2(id, -since * 1.5), 3));
					puff *= (1.0 - smoothstep(0.2, 1.4, since)) * dust * dust_color.a;
					col = mix(col, dust_color.rgb, puff * (1.0 - alpha * 0.4));
					alpha = max(alpha, puff);
				}
			}
		}
	}

	// Pebbles trickling down in thin streams.
	if (pebbles > 0.0) {
		float stream_w = rock_size * 5.0;
		float si = floor(p.x / stream_w);
		if (env_hash(vec2(si, seed + 17.0)) < pebbles * 0.6) {
			float sx = (si + 0.3 + 0.4 * env_hash(vec2(si, seed + 18.0))) * stream_w;
			vec2 g = vec2((p.x - sx) / 6.0, (p.y - t * 420.0) / 26.0);
			vec2 id2 = floor(g);
			float h = env_hash(id2 + vec2(si, seed));
			if (abs(p.x - sx) < 8.0 && h < 0.35 && p.y < ground - heap_at(p.x)) {
				vec2 d = (fract(g) - vec2(0.5, 0.5)) * vec2(6.0, 26.0);
				float a = smoothstep(2.2, 1.0, length(d));
				col = mix(col, mix(rock_dark.rgb, rock_color.rgb, h * 2.0), a);
				alpha = max(alpha, a);
			}
		}
	}
	COLOR = vec4(col, alpha * intensity);
}
