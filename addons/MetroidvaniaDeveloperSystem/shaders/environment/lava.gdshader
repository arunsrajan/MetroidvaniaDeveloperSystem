shader_type canvas_item;
// A pool of molten rock (or acid, or cursed ooze): a heaving surface with a bright skin,
// molten flow underneath with dark crust plates drifting on it and glowing cracks between
// them, bubbles swelling and bursting at the surface, a heat glow over it and embers rising.
// The rectangle reaches `surface_y` px above the pool, for the glow and the embers.

render_mode blend_mix, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 crust_color : source_color = vec4(0.16, 0.04, 0.03, 1.0);
uniform vec4 hot_color : source_color = vec4(0.95, 0.30, 0.06, 1.0);
uniform vec4 bright_color : source_color = vec4(1.0, 0.82, 0.42, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.38, 0.10, 0.55);
/// Where the surface rests, in px from the top of the rectangle.
uniform float surface_y = 90.0;
uniform float wave_height = 5.0;
uniform float wave_speed = 1.0;
uniform float flow_speed = 1.0;
/// How much of the surface is crusted over.
uniform float crust : hint_range(0.0, 1.0) = 0.6;
uniform float bubbles : hint_range(0.0, 1.0) = 0.5;
uniform float embers : hint_range(0.0, 1.0) = 0.5;
uniform float glow : hint_range(0.0, 1.0) = 0.7;

void vertex() {
	px = VERTEX - rect_origin;
}

float surface_at(float sx, float t) {
	float w = sin(sx * 0.018 + t * 1.3) * 0.5 + sin(sx * 0.041 - t * 2.1) * 0.3;
	w += (env_noise(vec2(sx * 0.02, t * 0.6)) - 0.5) * 0.8;
	return surface_y + w * wave_height;
}

void fragment() {
	float t = TIME * wave_speed;
	float sx = px.x + seed * 97.0;
	float surface = surface_at(sx, t);
	float below = px.y - surface;
	vec3 col = vec3(0.0);
	float alpha = 0.0;

	// Bubbles: a dome swells over the surface and bursts.
	float bub = 0.0;
	float bub_cell = 70.0;
	float bx = floor(sx / bub_cell);
	float bh = env_hash(vec2(bx, seed + 3.0));
	float period = 2.0 + 2.5 * bh;
	float life = fract(TIME / period + bh * 5.0);
	if (bubbles > 0.0 && bh < bubbles) {
		float cx = (bx + 0.3 + 0.4 * env_hash(vec2(bx, floor(TIME / period + bh * 5.0)))) * bub_cell;
		float r = 4.0 + 16.0 * smoothstep(0.0, 0.85, life) * (0.6 + 0.6 * bh);
		vec2 d = vec2(sx - cx, px.y - surface);
		float dome = smoothstep(r, r - 2.0, length(d)) * step(life, 0.88);
		bub = dome;
		// The burst: a ring of droplets thrown out.
		if (life > 0.88) {
			float k = (life - 0.88) / 0.12;
			float ring = smoothstep(2.0, 0.0, abs(length(d * vec2(1.0, 1.6)) - r * (1.0 + k * 1.6)));
			bub = max(bub, ring * (1.0 - k) * step(d.y, 2.0));
		}
	}

	if (below >= 0.0 || bub > 0.0) {
		// Molten flow: warped noise drifting slowly.
		vec2 q = vec2(sx, px.y) / 90.0;
		float ft = TIME * flow_speed;
		vec2 warp = vec2(env_fbm(q * 0.7 + vec2(ft * 0.05, 0.0), 3), env_fbm(q * 0.7 + vec2(3.7, -ft * 0.04), 3));
		float melt = env_fbm(q + warp * 1.8 + vec2(ft * 0.08, 0.0), 4);
		// Crust plates riding on it, with glowing cracks between them.
		vec2 cell = env_voronoi(vec2(sx - ft * 12.0, px.y) / 64.0 + warp * 0.7);
		float crack = smoothstep(0.02, 0.16, cell.y - cell.x);
		float plates = smoothstep(0.5 - crust * 0.25, 0.7 - crust * 0.2, melt + crust * 0.35) * crust;
		float deep = clamp(below / max(rect_size.y - surface_y, 1.0), 0.0, 1.0);
		col = mix(hot_color.rgb, bright_color.rgb, smoothstep(0.55, 0.85, melt));
		col = mix(col, hot_color.rgb * 0.55, deep * 0.6);
		col = mix(col, crust_color.rgb, plates * crack);
		// A bright skin right at the surface, and the bubbles.
		col = mix(col, bright_color.rgb, smoothstep(5.0, 0.0, abs(below)) * 0.8);
		col = mix(col, mix(hot_color.rgb, bright_color.rgb, 0.6), bub);
		alpha = 1.0;
	} else {
		// Heat glow over the surface.
		float g = exp(below / max(surface_y * 0.3, 1.0)) * glow * glow_color.a;
		col = glow_color.rgb;
		alpha = g;
		// Embers rising and flickering out.
		if (embers > 0.0) {
			vec2 ep = vec2(sx + sin(px.y * 0.05 + TIME) * 6.0, px.y + TIME * 55.0);
			vec2 eg = ep / 34.0;
			vec2 id = floor(eg);
			float eh = env_hash(id + vec2(seed, 9.0));
			if (eh < embers * 0.5) {
				vec2 d = (fract(eg) - (0.25 + 0.5 * env_hash2(id + 4.0))) * 34.0;
				float e = smoothstep(1.8, 0.2, length(d)) * (0.5 + 0.5 * sin(TIME * 9.0 + eh * 50.0));
				e *= smoothstep(-surface_y, -surface_y * 0.4, below);
				col = mix(col, bright_color.rgb, e);
				alpha = max(alpha, e);
			}
		}
		// Soft sides for the glow (the pool itself keeps its hard edges).
		alpha *= clamp(min(px.x, rect_size.x - px.x) / max(edge_fade, 0.001), 0.0, 1.0);
	}
	COLOR = vec4(col, alpha * intensity);
}
