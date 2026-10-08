shader_type canvas_item;
// One layer of a parallax background (MDSParallaxBackground): a sky, a silhouette (mountains,
// hills, forest, city, ruins, cave rock, dunes), clouds, a fog band, stars, or a picture
// repeated sideways. The layer is drawn in its own "content" coordinates, the node's local
// pixels minus `offset`: MDSParallaxBackground moves `offset` with the camera, slower for far
// layers, which is the parallax.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

const int SKY = 0;
const int MOUNTAINS = 1;
const int HILLS = 2;
const int FOREST = 3;
const int CITY = 4;
const int RUINS = 5;
const int CAVE = 6;
const int DUNES = 7;
const int CLOUDS = 8;
const int FOG = 9;
const int STARS = 10;
const int TEXTURE_LAYER = 11;

uniform int kind = 1;
uniform vec4 color : source_color = vec4(0.16, 0.14, 0.25, 1.0);
/// Peaks' snow, windows, rims, the sky's top.
uniform vec4 color_top : source_color = vec4(0.9, 0.9, 1.0, 1.0);
/// The haze at the base, the sky's bottom.
uniform vec4 color_bottom : source_color = vec4(0.5, 0.4, 0.5, 1.0);
/// Content offset (px): the camera's movement times how much this layer stays behind.
uniform vec2 offset = vec2(0.0);
/// Where features stand (content y, px).
uniform float base_y = 400.0;
/// How tall they rise (px).
uniform float height = 200.0;
/// How wide they are (px).
uniform float feature_size = 400.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
/// The silhouette runs on down to the bottom of the view.
uniform bool fill_below = true;
uniform float haze : hint_range(0.0, 1.0) = 0.3;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
/// Drift (px/s), for clouds.
uniform float autoscroll = 0.0;
/// The view (local px): the sky's gradient spans it.
uniform vec4 view_rect = vec4(0.0, 0.0, 1152.0, 648.0);
uniform sampler2D picture : source_color, filter_linear, repeat_enable;
uniform vec2 picture_size = vec2(1.0);
uniform float picture_scale = 1.0;
uniform bool repeat_x = true;

void vertex() {
	px = VERTEX - rect_origin;
}

float ridge(float x) {
	float n = 0.0;
	float amp = 0.55;
	float f = 1.0;
	for (int i = 0; i < 5; i++) {
		float v = 1.0 - abs(env_noise(vec2(x * f, seed + float(i) * 7.1)) * 2.0 - 1.0);
		n += v * v * amp;
		f *= 2.1;
		amp *= mix(0.35, 0.6, roughness);
	}
	return n;
}

float smooth_hills(float x) {
	return env_fbm(vec2(x, seed * 3.0), 3) * 1.3 + (env_noise(vec2(x * 4.0, seed)) - 0.5) * 0.15 * roughness;
}

// 1 inside the silhouette whose top is at `top` (content y), with a soft edge.
float below_line(float y, float top) {
	return smoothstep(top - 1.0, top + 1.0, y);
}

void fragment() {
	vec2 local = px + rect_origin;
	vec2 c = local - offset;
	c.x += TIME * autoscroll;
	vec3 col = color.rgb;
	float a = 0.0;
	float depth_in = 0.0; // 0 at the top edge of the silhouette, 1 at its base

	if (kind == SKY) {
		float t = clamp((local.y - view_rect.y) / max(view_rect.w, 1.0), 0.0, 1.0);
		col = mix(color_top.rgb, color_bottom.rgb, t);
		a = 1.0;
	} else if (kind == MOUNTAINS || kind == HILLS || kind == DUNES) {
		float x = c.x / max(feature_size, 1.0);
		float h;
		if (kind == MOUNTAINS) {
			h = ridge(x * 0.5);
		} else if (kind == HILLS) {
			h = smooth_hills(x * 0.6);
		} else {
			// Dunes: long gentle windward slopes, steep lee faces; the profile is 0 at both
			// ends of each dune, so neighbours join without a step.
			float w = fract(x * 0.7 + env_noise(vec2(x * 0.3, seed)) * 0.6);
			float windward = pow(clamp(w / 0.82, 0.0, 1.0), 1.5);
			float lee = smoothstep(1.0, 0.82, w);
			h = mix(windward, lee, step(0.82, w)) * 0.8 + env_noise(vec2(x * 0.2, seed + 2.0)) * 0.4;
		}
		float top = base_y - h * height;
		a = below_line(c.y, top);
		if (!fill_below) {
			a *= 1.0 - smoothstep(base_y, base_y + 2.0, c.y);
		}
		depth_in = clamp((c.y - top) / max(height, 1.0), 0.0, 1.0);
		if (kind == MOUNTAINS) {
			// Snow on the peaks: near the top of tall ones.
			float snow = smoothstep(0.62, 0.8, h) * smoothstep(top + height * 0.12, top, c.y);
			col = mix(col, color_top.rgb, snow * color_top.a);
		} else {
			// A lit rim along the crest.
			col = mix(col, color_top.rgb, smoothstep(top + 3.0, top, c.y) * color_top.a * 0.6);
		}
	} else if (kind == FOREST) {
		float x = c.x / max(feature_size, 1.0);
		float ground = base_y - smooth_hills(x * 0.3) * height * 0.25;
		float cell = feature_size * 0.09;
		float cx = floor(c.x / cell);
		float best = 0.0;
		for (int k = -2; k <= 2; k++) {
			float id = cx + float(k);
			float hsh = env_hash(vec2(id, seed));
			float tree_h = height * (0.45 + 0.55 * hsh);
			float centre = (id + 0.5 + (env_hash(vec2(id, seed + 4.0)) - 0.5) * 0.6) * cell;
			float half_w = cell * (0.9 + roughness * 0.8) * (0.55 + 0.45 * hsh);
			float tip = ground - tree_h;
			// A conifer: wider toward its base, in tiers.
			float along = clamp((c.y - tip) / max(tree_h, 1.0), 0.0, 1.0);
			float tiers = 0.82 + 0.18 * fract(along * 4.0);
			float w = half_w * along * tiers;
			float inside = step(tip, c.y) * step(abs(c.x - centre), w);
			best = max(best, inside);
		}
		a = max(best, below_line(c.y, ground));
		depth_in = clamp((c.y - (ground - height)) / max(height, 1.0), 0.0, 1.0);
	} else if (kind == CITY || kind == RUINS) {
		float cell = feature_size * 0.12;
		float cx = floor(c.x / cell);
		float hsh = env_hash(vec2(cx, seed));
		float top = base_y - height * (0.25 + 0.75 * hsh * hsh);
		float left = cx * cell + cell * 0.08 * env_hash(vec2(cx, seed + 1.0));
		float right = (cx + 1.0) * cell - cell * 0.08 * env_hash(vec2(cx, seed + 2.0));
		if (kind == RUINS) {
			// Broken tops in steps (fallen stonework) and gaps between the buildings.
			top += (floor(env_noise(vec2(floor(c.x / (cell * 0.14)) * 0.37, seed)) * 5.0) / 5.0 - 0.3) * cell * 1.2;
			if (hsh < 0.25) {
				top = base_y - height * 0.08;
			}
		}
		float inside = step(top, c.y) * step(left, c.x) * step(c.x, right);
		a = max(inside, below_line(c.y, base_y - height * 0.05));
		depth_in = clamp((c.y - top) / max(height, 1.0), 0.0, 1.0);
		if (kind == CITY && inside > 0.5 && c.y < base_y - 4.0) {
			// Lit windows.
			vec2 wc = floor(vec2(c.x / 9.0, c.y / 12.0));
			vec2 wf = fract(vec2(c.x / 9.0, c.y / 12.0));
			float lit = step(1.0 - roughness * 0.5, env_hash(wc + seed)) * step(0.25, wf.x) * step(wf.x, 0.75) * step(0.3, wf.y) * step(wf.y, 0.75);
			col = mix(col, color_top.rgb, lit * color_top.a);
		}
	} else if (kind == CAVE) {
		// Stalactites hanging from a ceiling and stalagmites rising to meet them.
		float x = c.x / max(feature_size, 1.0);
		float rock = (env_noise(vec2(c.x / max(feature_size * 0.06, 1.0), seed + 13.0)) - 0.5) * height * 0.08 * (0.5 + roughness);
		float ceiling = base_y - height * 2.2 + smooth_hills(x * 0.4 + 9.0) * height * 0.5 + rock;
		float floor_y = base_y - smooth_hills(x * 0.4) * height * 0.35 - rock;
		float sx = c.x / max(feature_size * 0.13, 1.0);
		float sid = floor(sx);
		float sf = fract(sx);
		// Some cells hang a spike, some raise one, a few both; each tapers from a wide base to
		// a point, and its width varies.
		float wide = 0.45 + 0.5 * env_hash(vec2(sid, seed + 11.0));
		float shape = pow(clamp(1.0 - abs(sf - 0.5) * 2.0 / wide, 0.0, 1.0), 1.5);
		float spike = env_hash(vec2(sid, seed + 3.0));
		float len = height * 1.3 * pow(max(spike - 0.3, 0.0) / 0.7, 2.0);
		float rise_spike = env_hash(vec2(sid + 31.0, seed + 5.0));
		float rise_len = height * 0.9 * pow(max(rise_spike - 0.45, 0.0) / 0.55, 2.0);
		float hang = 1.0 - below_line(c.y, ceiling + len * shape);
		float rise = below_line(c.y, floor_y - rise_len * shape);
		a = max(hang, rise);
		float upper = step(c.y, (ceiling + floor_y) * 0.5);
		float from_ceiling = clamp((ceiling + len - c.y) / max(len + height * 0.3, 1.0), 0.0, 1.0);
		float from_floor = clamp((c.y - floor_y + rise_len) / max(rise_len + height * 0.3, 1.0), 0.0, 1.0);
		depth_in = 1.0 - mix(from_floor, from_ceiling, upper);
	} else if (kind == CLOUDS) {
		float n = env_fbm(vec2(c.x / max(feature_size, 1.0), c.y / max(height, 1.0) * 0.8 + seed), 5);
		float band = 1.0 - smoothstep(0.0, height, abs(c.y - base_y));
		a = smoothstep(0.45 - roughness * 0.15, 0.75, n) * band;
		col = mix(color.rgb, color_top.rgb, smoothstep(0.5, 0.85, n));
	} else if (kind == FOG) {
		float n = env_fbm(vec2(c.x / max(feature_size, 1.0), c.y / max(height, 1.0) + seed), 4);
		float band = 1.0 - smoothstep(height * 0.2, height, abs(c.y - base_y));
		a = band * (0.55 + 0.45 * n);
	} else if (kind == STARS) {
		vec2 g = c / 26.0;
		vec2 id = floor(g);
		float h = env_hash(id + seed);
		if (h < 0.08 + roughness * 0.2) {
			vec2 d = (fract(g) - (0.2 + 0.6 * env_hash2(id))) * 26.0;
			float r = 0.6 + 1.2 * fract(h * 17.0);
			float tw = 0.6 + 0.4 * sin(TIME * (1.0 + 3.0 * h) + h * 40.0);
			a = smoothstep(r, 0.0, length(d)) * tw;
		}
		a *= 1.0 - smoothstep(base_y - height, base_y, c.y);
	} else if (kind == TEXTURE_LAYER) {
		vec2 size = picture_size * picture_scale;
		vec2 uv = vec2(c.x / max(size.x, 1.0), (c.y - (base_y - size.y)) / max(size.y, 1.0));
		if ((repeat_x || (uv.x >= 0.0 && uv.x <= 1.0)) && uv.y >= 0.0 && uv.y <= 1.0) {
			vec4 t = texture(picture, vec2(fract(uv.x), uv.y));
			col = t.rgb * color.rgb;
			a = t.a;
		} else if (fill_below && uv.y > 1.0) {
			a = 1.0;
		}
		depth_in = clamp(uv.y, 0.0, 1.0);
	}

	if (kind != SKY && kind != STARS && kind != CLOUDS) {
		// Haze: the air between the layer and the viewer, thicker toward its base.
		col = mix(col, color_bottom.rgb, haze * smoothstep(0.0, 1.0, depth_in));
	}
	if (kind == STARS) {
		col = color.rgb;
	}
	COLOR = vec4(col, a * alpha * mix(color.a, 1.0, float(kind == SKY)) * intensity);
}
