shader_type canvas_item;
// An animated background (MDSAnimatedBackground): soft, out-of-focus scenery in motion, as if
// far behind the room and seen through a lens. `style` picks one of the looks below; four
// colors, speed, blur, size and density shape it.
//
// It is laid out on the view, not on the room: `p` is the view's middle at (0, 0) and its
// height 1, plus `drift`, the little it moves as the camera moves (the background is far away).
// "Blur" softens every shape: lights become wide discs, clouds lose their fine detail, edges
// melt.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

const int BOKEH = 0;
const int AURORA = 1;
const int NEBULA = 2;
const int MOLTEN_BLOBS = 3;
const int DEEP_WATER = 4;
const int EMBER_GLOW = 5;
const int STORM_CLOUDS = 6;
const int FOREST_CANOPY = 7;
const int SUNSET_HAZE = 8;
const int CRYSTAL_CAVE = 9;
const int VOID_PULSE = 10;
const int BLOOD_MOON = 11;
const int ARCANE_VORTEX = 12;
const int FROZEN_NIGHT = 13;
const int SPORE_DRIFT = 14;
const int INFECTION = 15;
const int STARFIELD = 16;
const int HOLY_LIGHT = 17;
const int TOXIC_SWAMP = 18;
const int PICTURE = 19;

uniform int style = 0;
/// The deep: the bottom of the sky, the dark between the lights.
uniform vec4 color_a : source_color = vec4(0.05, 0.06, 0.12, 1.0);
/// The top of the sky.
uniform vec4 color_b : source_color = vec4(0.12, 0.10, 0.22, 1.0);
/// The lights: the main glow.
uniform vec4 color_c : source_color = vec4(1.0, 0.75, 0.45, 1.0);
/// The accent.
uniform vec4 color_d : source_color = vec4(0.55, 0.65, 1.0, 1.0);
uniform float speed = 1.0;
/// How out of focus it is (0 sharp, 1 very soft).
uniform float blur : hint_range(0.0, 1.0) = 0.6;
/// Size of its features (2: twice as big).
uniform float feature_scale = 1.0;
/// How many lights, motes, stars.
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float brightness = 1.0;
/// A throb, like a heartbeat (boss rooms), `pulse_rate` beats a second.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_rate = 1.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
/// Film grain; it also hides banding in the soft gradients.
uniform float grain : hint_range(0.0, 1.0) = 0.3;
/// How far it moved with the camera (view heights).
uniform vec2 drift = vec2(0.0);
/// The view (local px): the background is laid out on it.
uniform vec4 view_rect = vec4(0.0, 0.0, 1152.0, 648.0);
uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_picture = false;
uniform vec2 picture_size = vec2(1.0);

void vertex() {
	px = VERTEX - rect_origin;
}

float sat(float x) {
	return clamp(x, 0.0, 1.0);
}

// 1 in the middle of a disc of radius r, 0 outside; the outer `w` share of r is its soft rim.
float disc(float d, float r, float w) {
	return 1.0 - smoothstep(r * (1.0 - clamp(w, 0.02, 1.0)), r, d);
}

// How many fbm octaves at this blur: soft looks keep only the broad shapes.
int octaves(int sharp) {
	return max(2, sharp - int(round(blur * 3.0)));
}

// Out-of-focus lights in cells of size `cell` drifting along `move` (cells/s): their summed
// glow, and in `hue` the average of their random 0..1 tints (to mix two colors).
float bokeh(vec2 p, float cell, float t, vec2 move, float radius, float soft, float dens, float sd, out float hue) {
	vec2 q = p / cell + move * t;
	vec2 id = floor(q);
	vec2 f = fract(q);
	float total = 0.0;
	float tint = 0.0;
	float weight = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 cid = id + g;
			if (env_hash(cid + sd * 1.7 + seed) > dens) {
				continue;
			}
			vec2 h = env_hash2(cid + sd + seed);
			vec2 c = g + 0.5 + (h - 0.5) * 0.7 + 0.1 * vec2(sin(t * 0.7 + h.x * 6.283), cos(t * 0.5 + h.y * 6.283));
			float d = length(f - c);
			float r = radius * (0.5 + 0.5 * h.y);
			float a = disc(d, r, soft);
			// Out-of-focus discs are a little brighter towards their rim.
			a *= 0.78 + 0.22 * smoothstep(r * 0.3, r * 0.9, d);
			a *= 0.65 + 0.35 * sin(t * (0.5 + h.x) + h.y * 20.0);
			total += a;
			tint += a * fract(h.x * 7.31);
			weight += a;
		}
	}
	hue = weight > 0.0 ? tint / weight : 0.0;
	return total;
}

// Stars (or sparks) in cells of size `cell`: soft dots of radius `size` (cell units), twinkling.
float stars(vec2 p, float cell, float size, float t, float dens, float sd) {
	vec2 q = p / cell;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 h = env_hash2(id + sd + seed);
	if (env_hash(id * 1.3 + sd + seed) > dens) {
		return 0.0;
	}
	float d = length(f - (h - 0.5) * 0.6);
	float tw = 0.55 + 0.45 * sin(t * (1.0 + h.y * 3.0) + h.x * 40.0);
	return (1.0 - smoothstep(0.0, size, d)) * tw * (0.4 + 0.6 * h.y);
}

// Cellular noise whose centres wander over time: the distances to the nearest and second-nearest
// centres, and the nearest cell's random value (0..1).
vec3 cells(vec2 p, float t) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 h = env_hash2(n + g + seed);
			vec2 o = 0.5 + 0.4 * sin(t * (0.4 + 0.4 * h.yx) + h * 6.283);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = env_hash(n + g + seed + 0.37);
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2), id);
}

// Fractal noise that drifts: `n` octaves.
float cloud(vec2 p, int n) {
	return env_fbm(p + vec2(seed * 3.1, seed * 1.7), n);
}

vec3 sky(vec2 uv) {
	return mix(color_b.rgb, color_a.rgb, smoothstep(0.0, 1.0, uv.y));
}

// --- The styles -----------------------------------------------------------------------------------

vec3 st_bokeh(vec2 p, vec2 uv, float t, float soft) {
	vec3 col = sky(uv);
	float h;
	float d = 0.25 + 0.6 * density;
	float far = bokeh(p, 0.09, t, vec2(0.02, -0.1), 0.3, max(soft * 0.5, 0.2), d, 13.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * far * 0.32;
	float mid = bokeh(p + vec2(3.1, 1.7), 0.2, t, vec2(-0.03, -0.06), 0.4, soft * 0.8, d * 0.85, 7.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * mid * 0.36;
	float near = bokeh(p + vec2(9.0, 4.0), 0.45, t, vec2(0.015, -0.03), 0.46, soft, d * 0.7, 1.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * near * 0.3;
	return col;
}

vec3 st_aurora(vec2 p, vec2 uv, float t, float soft) {
	vec3 col = sky(uv);
	col += vec3(stars(p, 0.035, mix(0.08, 0.2, soft), t, 0.25 + 0.4 * density, 3.0)) * 0.55 * (1.0 - uv.y);
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float x = p.x * (0.8 + 0.25 * fk) + fk * 3.7;
		// The curtain's lower edge folds and sways.
		float yc = -0.2 + 0.09 * fk + 0.3 * (cloud(vec2(x * 0.6 + t * 0.035, fk * 5.0), 3) - 0.5) + 0.04 * sin(x * 3.0 + t * 0.4 + fk);
		float w = (0.03 + 0.05 * soft) * (1.0 + 0.4 * sin(x * 2.0 + t * 0.3));
		float dy = p.y - yc;
		float band = exp(-dy * dy / (w * w));
		// The curtain rises from its bright lower edge.
		float tail = dy < 0.0 ? pow(1.0 - sat(-dy / (0.32 + 0.2 * soft)), 1.6) * 0.8 : 0.0;
		float rays = mix(0.3 + 0.7 * env_noise(vec2(x * 16.0 + t * 0.35, fk * 9.0)), 1.0, soft * 0.6);
		float wave = 0.4 + 0.6 * env_noise(vec2(x * 1.4 - t * 0.18, fk * 3.0));
		vec3 c = mix(color_c.rgb, color_d.rgb, sat(-dy * 3.0 + fk * 0.3));
		col += c * (band + tail) * rays * wave * 0.5;
	}
	return col;
}

vec3 st_nebula(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(5);
	vec2 q = env_rotate(p * 1.4, t * 0.01);
	vec2 w = vec2(cloud(q + vec2(t * 0.02, 0.0), n), cloud(q + vec2(5.2, 1.3) - t * 0.015, n));
	float v = cloud(q + 1.8 * w + vec2(1.7, 9.2), n);
	float v2 = cloud(q * 2.1 - w + 3.0, max(n - 1, 2));
	vec3 col = mix(color_a.rgb, color_b.rgb * 1.4, smoothstep(0.2, 0.7, v));
	col = mix(col, color_c.rgb, smoothstep(0.5, 0.82, v) * 0.8);
	col += color_d.rgb * pow(smoothstep(0.4, 0.82, v2), 2.0) * 0.5;
	float s = stars(p, 0.03, mix(0.07, 0.2, soft), t, 0.2 + 0.4 * density, 5.0) + stars(p, 0.07, mix(0.05, 0.16, soft), t, 0.15 + 0.3 * density, 11.0);
	return col + vec3(s) * 0.7;
}

vec3 st_blobs(vec2 p, vec2 uv, float t, float soft) {
	vec3 col = sky(uv);
	float field = 0.0;
	float tint = 0.0;
	int count = 5 + int(density * 6.0);
	for (int i = 0; i < 11; i++) {
		if (i >= count) {
			break;
		}
		float fi = float(i);
		vec2 h = env_hash2(vec2(fi * 3.7, seed + 3.0));
		vec2 c = vec2(sin(t * (0.05 + 0.05 * h.x) + fi * 2.1) * 0.85, sin(t * (0.04 + 0.06 * h.y) + fi * 1.3) * 0.55);
		float r = 0.1 + 0.11 * h.y;
		vec2 d = p - c;
		float f = r * r / (dot(d, d) + 0.0004);
		field += f;
		tint += f * h.x;
	}
	tint /= max(field, 0.001);
	float edge = mix(0.06, 0.7, soft);
	float m = smoothstep(1.0 - edge, 1.0 + edge, field);
	vec3 blob = mix(color_c.rgb, color_d.rgb, tint);
	col = mix(col, blob, m * 0.92);
	col += blob * smoothstep(0.15, 1.0, field) * 0.18;
	return col;
}

vec3 st_water(vec2 p, vec2 uv, float t, float soft) {
	vec3 col = mix(color_b.rgb, color_a.rgb, smoothstep(-0.1, 1.05, uv.y));
	// Caustics: two nets of wandering cells, bent by a slow swell, multiplied (their bright
	// lines cross where light gathers).
	float width = mix(0.05, 0.4, soft);
	vec2 swell = vec2(env_noise(p * 2.0 + t * 0.1), env_noise(p * 2.0 + 7.0 - t * 0.1)) * 0.5;
	vec3 c1 = cells(p * 3.0 + swell, t * 0.6);
	vec3 c2 = cells(p * 3.7 - swell + 5.0, t * 0.5 + 3.0);
	float net1 = 1.0 - smoothstep(0.0, width, c1.y - c1.x);
	float net2 = 1.0 - smoothstep(0.0, width * 1.2, c2.y - c2.x);
	float caustic = net1 * (0.35 + 0.65 * net2);
	col += color_c.rgb * caustic * 0.3 * (1.0 - smoothstep(0.0, 1.0, uv.y) * 0.85);
	float rays = 0.5 + 0.5 * sin((p.x + p.y * 0.32) * 7.0 + t * 0.25 + sin(p.x * 2.3 + t * 0.15) * 1.5);
	rays = pow(rays, mix(10.0, 3.0, soft)) * (1.0 - smoothstep(0.0, 0.85, uv.y));
	col += color_c.rgb * rays * 0.2;
	float h;
	float bubbles = bokeh(p + vec2(0.0, 2.0), 0.11, t, vec2(0.0, 0.28), 0.22, soft * 0.6 + 0.15, 0.15 + 0.35 * density, 4.0, h);
	col += color_d.rgb * bubbles * 0.32;
	return col;
}

vec3 st_embers(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.1, 1.1, uv.y));
	float heat = cloud(vec2(p.x * 1.5, p.y * 1.5 + t * 0.12), n);
	col += color_d.rgb * smoothstep(0.35, 1.15, uv.y) * (0.45 + 0.55 * heat) * 0.55;
	float smoke = cloud(p * 2.0 + vec2(t * 0.03, t * 0.08), n);
	col *= 0.75 + 0.35 * smoke;
	float h;
	float d = 0.2 + 0.55 * density;
	vec2 wob = vec2(sin(p.y * 6.0 + t) * 0.02, 0.0);
	float e1 = bokeh(p + wob, 0.07, t, vec2(0.03, 0.22), 0.26, max(soft * 0.5, 0.2), d, 2.0, h);
	col += mix(color_c.rgb, color_d.rgb, h * 0.6) * e1 * 0.55;
	float e2 = bokeh(p * 0.8 + wob * 2.0 + vec2(5.0, 1.0), 0.22, t, vec2(-0.02, 0.12), 0.36, soft, d * 0.6, 9.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * e2 * 0.3;
	return col;
}

vec3 st_storm(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(5);
	vec2 q = p * vec2(1.2, 1.9) + vec2(t * 0.05, 0.0);
	vec2 warp = vec2(cloud(q * 0.7 - t * 0.02, 3), cloud(q * 0.7 + 4.0, 3)) * 0.8;
	float c1 = cloud(q + warp, n);
	// Cloud tops lit from above: denser just above means a shadow.
	float lit = sat((c1 - cloud(q + warp + vec2(0.0, -0.06), n)) * 5.0 + 0.55);
	vec3 col = mix(color_b.rgb, color_a.rgb, uv.y);
	vec3 cloud_col = mix(color_a.rgb * 0.7, color_b.rgb * 1.35, lit);
	col = mix(col, cloud_col, smoothstep(0.32, 0.62, c1));
	// Lightning behind the clouds: a flash every few seconds, somewhere along the view.
	float slot = floor(t * 0.7);
	float fl = env_hash(vec2(slot, seed + 1.0));
	float age = fract(t * 0.7);
	float flash = fl > 0.45 ? exp(-age * 9.0) * (0.6 + 0.4 * step(0.08, abs(age - 0.12))) : 0.0;
	float fx = (env_hash(vec2(slot, seed + 2.0)) - 0.5) * 1.4;
	float glow = exp(-pow(length(vec2((p.x - fx) * 0.8, p.y + 0.15)), 2.0) * mix(9.0, 4.0, soft));
	col += color_c.rgb * flash * (0.18 + glow * (0.5 + 0.8 * (1.0 - c1)));
	// A veil of rain.
	float rain = env_noise(vec2(p.x * 60.0 + p.y * 12.0, p.y * 3.0 - t * 9.0));
	col += color_d.rgb * smoothstep(0.75, 1.0, rain) * (1.0 - soft * 0.7) * 0.1 * density;
	return col;
}

vec3 st_canopy(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = sky(uv);
	vec2 sway = vec2(sin(t * 0.4 + p.y * 2.0), cos(t * 0.33 + p.x * 1.5)) * 0.02;
	float leaves = cloud((p + sway) * 3.5, n);
	col *= mix(1.0, 0.45, smoothstep(0.42, 0.62 + soft * 0.1, leaves));
	float h;
	float flecks = bokeh(p + sway * 3.0, 0.1, t * 0.6, vec2(0.0, 0.0), 0.34, soft * 0.8 + 0.15, 0.25 + 0.5 * density, 6.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * flecks * 0.35 * (1.0 - smoothstep(0.42, 0.7, leaves) * 0.7);
	float rays = 0.5 + 0.5 * sin((p.x * 0.8 - p.y * 0.45) * 9.0 + sin(t * 0.2) * 0.6);
	rays = pow(rays, mix(12.0, 4.0, soft)) * (1.0 - smoothstep(0.0, 1.0, uv.y));
	col += color_c.rgb * rays * 0.16;
	return col;
}

vec3 st_sunset(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = mix(color_b.rgb, color_a.rgb, smoothstep(0.0, 0.85, uv.y));
	vec2 sun = vec2(0.32, 0.05);
	float d = length(p - sun);
	col += color_c.rgb * (disc(d, 0.11, mix(0.15, 0.7, soft)) * 0.8 + exp(-d * mix(5.0, 3.0, soft)) * 0.45);
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		vec2 q = vec2(p.x * 1.2 + t * (0.01 + 0.008 * fk) + fk * 4.0, p.y * 7.0 + fk * 2.3);
		float band = smoothstep(0.5, 0.75, cloud(q, n)) * (1.0 - smoothstep(0.15, 0.4, abs(p.y - (-0.1 + fk * 0.12))));
		vec3 c = mix(color_d.rgb, color_c.rgb, exp(-d * 2.5) * 0.8);
		col = mix(col, c, band * (0.55 - fk * 0.1));
	}
	return col;
}

// A crystal spike standing on `base`, leaning by `lean` (radians), `h` tall and `w` wide at its
// foot, pointing up (`dir` 1) or hanging down (-1): how much of the point it covers (soft), its
// distance outside (for the glow) and in `shade` its lit or shadowed facet.
float shard(vec2 p, vec2 base, float lean, float h, float w, float dir, float soft, out float outside, out float shade) {
	vec2 q = env_rotate(p - base, -lean);
	q.y *= -dir;
	float half_w = w * (1.0 - clamp(q.y / h, 0.0, 1.0));
	float d = max(abs(q.x) - half_w, max(-q.y, q.y - h));
	outside = max(d, 0.0);
	shade = mix(0.55, 1.0, smoothstep(-half_w, half_w * 0.2, -q.x)) * (0.75 + 0.25 * sat(q.y / h));
	float edge = mix(0.003, 0.03, soft);
	return 1.0 - smoothstep(-edge, edge, d);
}

// A row of crystal spikes along y = `row` (cells `cell` wide), pointing `dir`; adds them to `col`.
vec3 crystal_row(vec3 col, vec2 p, float t, float soft, float row, float dir, float cell, float size, float bright, float sd) {
	float id0 = floor(p.x / cell);
	float glow = 0.0;
	vec3 glow_col = vec3(0.0);
	for (int j = -2; j <= 2; j++) {
		float id = id0 + float(j);
		vec2 h = env_hash2(vec2(id, sd) + seed);
		vec2 h2 = env_hash2(vec2(id * 1.7 + 3.0, sd) + seed);
		if (h2.x > 0.35 + 0.6 * density) {
			continue;
		}
		vec2 base = vec2((id + 0.5 + (h.x - 0.5) * 0.6) * cell, row);
		float lean = (h.y - 0.5) * 0.7;
		float height = size * (0.45 + 0.75 * h2.y);
		float width = size * (0.14 + 0.12 * h.x);
		float outside;
		float shade;
		float cov = shard(p, base, lean, height, width, dir, soft, outside, shade);
		vec3 tint = mix(color_c.rgb, color_d.rgb, fract(h.x * 3.1 + h2.y));
		float shine = 0.6 + 0.4 * sin(t * (0.6 + h.y) + h2.x * 30.0 - p.y * 6.0);
		col = mix(col, tint * shade * shine * bright, cov * 0.9);
		float g = exp(-outside * mix(28.0, 10.0, soft)) * (1.0 - cov);
		glow += g;
		glow_col += tint * g * shine;
	}
	return col + glow_col * 0.35 * bright;
}

vec3 st_crystal(vec2 p, vec2 uv, float t, float soft) {
	vec3 col = sky(uv);
	// Far spikes, small and hazy, then near ones, large and bright, rising from the floor and
	// hanging from the ceiling.
	col = crystal_row(col, p, t, soft, 0.42, 1.0, 0.07, 0.16, 0.55, 3.0);
	col = crystal_row(col, p, t, soft, -0.46, -1.0, 0.08, 0.14, 0.5, 5.0);
	col = mix(col, color_b.rgb, 0.35);
	col = crystal_row(col, p, t, soft, 0.53, 1.0, 0.17, 0.44, 1.2, 7.0);
	col = crystal_row(col, p, t, soft, -0.55, -1.0, 0.2, 0.36, 1.1, 11.0);
	col += vec3(stars(p, 0.05, mix(0.08, 0.2, soft), t * 2.0, 0.1 + 0.3 * density, 8.0)) * mix(color_c.rgb, vec3(1.0), 0.5) * 0.8;
	return col;
}

vec3 st_void(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	float r = length(p * vec2(1.0, 1.1));
	float a = atan(p.y, p.x);
	vec3 col = mix(color_b.rgb, color_a.rgb, smoothstep(0.0, 0.9, r));
	float swirl = cloud(vec2(a * 1.5 + t * 0.1 + r * 3.0, r * 4.0 - t * 0.3), n);
	col = mix(col, color_d.rgb * 0.7, smoothstep(0.45, 0.8, swirl) * (1.0 - smoothstep(0.2, 1.0, r)) * 0.8);
	float rings = 0.5 + 0.5 * sin(r * 16.0 - t * 2.2);
	rings = pow(rings, mix(10.0, 2.5, soft)) * exp(-r * 2.2);
	col += color_c.rgb * rings * 0.45;
	float beat = exp(-fract(t * 0.5) * 6.0);
	col += color_c.rgb * exp(-r * mix(9.0, 5.0, soft)) * (0.55 + 0.5 * beat);
	return col;
}

vec3 st_blood_moon(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = mix(color_b.rgb, color_a.rgb, smoothstep(0.0, 1.0, uv.y));
	vec2 moon = vec2(0.3, -0.14);
	float d = length(p - moon);
	float r = 0.19;
	float halo = exp(-max(d - r, 0.0) * mix(7.0, 3.5, soft));
	col += color_c.rgb * halo * 0.4;
	float body = disc(d, r, mix(0.03, 0.22, soft));
	float marks = cloud((p - moon) * 8.0 + 2.0, n);
	vec3 face = mix(color_c.rgb, vec3(1.0, 0.82, 0.7), 0.3) * (0.75 + 0.4 * marks);
	face *= 1.0 - 0.45 * smoothstep(0.0, r, length(p - moon - vec2(-0.05, -0.04)));
	col = mix(col, face, body);
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		vec2 q = vec2(p.x * 1.4 + t * (0.025 + 0.015 * fk) + fk * 5.0, p.y * 5.0 + fk * 1.9);
		float mist = smoothstep(0.45, 0.8, cloud(q, n)) * smoothstep(0.55, 0.0, abs(p.y - (0.08 + fk * 0.13)));
		col = mix(col, color_d.rgb, mist * 0.6);
	}
	return col;
}

vec3 st_vortex(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec2 c = p - vec2(0.0, -0.04);
	float r = length(c);
	float a = atan(c.y, c.x);
	float twist = cloud(c * 3.0 + t * 0.05, n) * 1.2;
	float arms = sin(a * 3.0 + log(r + 0.02) * 5.5 - t * 1.1 + twist);
	float edge = mix(0.15, 0.95, soft);
	float m = smoothstep(-edge, edge, arms);
	vec3 col = mix(color_a.rgb, color_b.rgb, m * (1.0 - smoothstep(0.1, 0.95, r)));
	col += mix(color_c.rgb, color_d.rgb, smoothstep(0.0, 0.6, r)) * pow(m, 2.0) * exp(-r * 2.5) * 0.5;
	col += color_c.rgb * exp(-r * mix(14.0, 7.0, soft)) * 0.9;
	col += vec3(stars(env_rotate(c, -t * 0.05), 0.04, mix(0.1, 0.22, soft), t, 0.15 + 0.4 * density, 6.0)) * color_d.rgb * 0.7;
	return col;
}

vec3 st_frozen(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = sky(uv);
	col = mix(col, color_d.rgb, smoothstep(0.4, 0.8, cloud(vec2(p.x * 1.5 + t * 0.02, p.y * 4.0), n)) * smoothstep(0.2, 1.0, uv.y) * 0.4);
	float h;
	float d = 0.25 + 0.6 * density;
	vec2 sway = vec2(sin(p.y * 4.0 + t * 0.7) * 0.015, 0.0);
	float f1 = bokeh(p + sway, 0.06, t, vec2(0.06, -0.35), 0.24, max(soft * 0.4, 0.25), d, 3.0, h);
	float f2 = bokeh(p + sway * 2.0 + vec2(2.0, 0.0), 0.14, t, vec2(0.04, -0.22), 0.3, soft * 0.7 + 0.15, d * 0.8, 9.0, h);
	float f3 = bokeh(p + sway * 3.0 + vec2(7.0, 0.0), 0.32, t, vec2(0.02, -0.12), 0.4, soft, d * 0.5, 17.0, h);
	col += color_c.rgb * (f1 * 0.45 + f2 * 0.35 + f3 * 0.2);
	return col;
}

vec3 st_spores(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = sky(uv);
	float fog = cloud(p * 1.8 + vec2(t * 0.02, -t * 0.01), n);
	col = mix(col, color_b.rgb * 1.4, smoothstep(0.45, 0.8, fog) * 0.5);
	float h;
	float d = 0.2 + 0.6 * density;
	vec2 wander = vec2(sin(t * 0.3 + p.y * 3.0), cos(t * 0.25 + p.x * 3.0)) * 0.02;
	float m1 = bokeh(p + wander, 0.08, t, vec2(0.02, 0.04), 0.2, 0.9, d, 5.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * m1 * 0.6;
	float m2 = bokeh(p + wander * 2.0 + 3.0, 0.2, t, vec2(-0.015, 0.025), 0.32, soft * 0.6 + 0.4, d * 0.6, 12.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * m2 * 0.3;
	return col;
}

vec3 st_infection(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = sky(uv);
	vec2 q = p * 2.6 + vec2(cloud(p * 2.0 + t * 0.03, 3), cloud(p * 2.0 + 4.0 - t * 0.03, 3)) * 0.6;
	vec3 c = cells(q, t * 0.08);
	float vein = 1.0 - smoothstep(0.0, mix(0.05, 0.35, soft), c.y - c.x);
	// The glow runs along the veins, each cell beating in its own time.
	float flow = 0.5 + 0.5 * sin(c.x * 8.0 - t * 1.6 + c.z * 6.283);
	col += color_c.rgb * vein * (0.25 + 0.55 * flow);
	col += color_c.rgb * (1.0 - smoothstep(0.0, 0.5, c.x)) * 0.05 * flow;
	float blob = smoothstep(0.55, 0.85, cloud(p * 3.0 + vec2(0.0, t * 0.05), n));
	col = mix(col, color_d.rgb, blob * 0.4);
	float h;
	float motes = bokeh(p, 0.1, t, vec2(0.01, 0.1), 0.24, soft * 0.6 + 0.2, 0.2 + 0.5 * density, 3.0, h);
	col += color_c.rgb * motes * 0.45;
	return col;
}

vec3 st_starfield(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(4);
	vec3 col = sky(uv);
	float haze = cloud(p * 1.2 + vec2(t * 0.005, 0.0), n);
	col += color_d.rgb * smoothstep(0.45, 0.85, haze) * 0.18;
	float d = 0.2 + 0.5 * density;
	float s = 0.0;
	s += stars(p + vec2(t * 0.004, 0.0), 0.022, mix(0.08, 0.18, soft), t, d, 1.0) * 0.6;
	s += stars(p + vec2(t * 0.012, 0.0), 0.045, mix(0.07, 0.17, soft), t, d * 0.8, 4.0) * 0.9;
	s += stars(p + vec2(t * 0.03, 0.0), 0.1, mix(0.06, 0.2, soft), t, d * 0.6, 9.0) * 1.2;
	return col + color_c.rgb * s;
}

vec3 st_holy(vec2 p, vec2 uv, float t, float soft) {
	vec3 col = mix(color_b.rgb, color_a.rgb, smoothstep(0.0, 1.0, uv.y));
	vec2 src = vec2(0.0, -0.75);
	vec2 c = p - src;
	float a = atan(c.x, c.y);
	float r = length(c);
	float rays = env_noise(vec2(a * 9.0 + t * 0.06, t * 0.05)) * 0.6 + env_noise(vec2(a * 21.0 - t * 0.04, 3.0)) * 0.4;
	rays = smoothstep(mix(0.45, 0.2, soft), mix(0.85, 0.95, soft), rays);
	col += color_c.rgb * rays * exp(-max(r - 0.3, 0.0) * 1.6) * 0.5;
	col += color_c.rgb * exp(-r * mix(4.0, 2.5, soft)) * 0.55;
	float h;
	float dust = bokeh(p, 0.07, t * 0.5, vec2(0.03, 0.05), 0.2, 0.8, 0.2 + 0.5 * density, 2.0, h);
	col += mix(color_c.rgb, color_d.rgb, h) * dust * 0.45 * (1.0 - smoothstep(0.3, 1.1, r) * 0.7);
	return col;
}

vec3 st_toxic(vec2 p, vec2 uv, float t, float soft) {
	int n = octaves(5);
	vec2 q = p * 1.8;
	vec2 w = vec2(cloud(q + vec2(t * 0.03, 0.0), n), cloud(q + vec2(3.3, -t * 0.025), n));
	float murk = cloud(q + w * 1.6, n);
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.25, 0.75, murk));
	col += color_d.rgb * smoothstep(0.6, 0.85, murk) * 0.35;
	// Bubbles: soft rings rising.
	vec2 bq = p / 0.12 + vec2(0.0, t * 0.25);
	vec2 id = floor(bq);
	vec2 f = fract(bq) - 0.5;
	vec2 h = env_hash2(id + seed + 21.0);
	if (h.x < 0.2 + 0.5 * density) {
		float d = length(f - (h - 0.5) * 0.5);
		float rr = 0.12 + 0.18 * h.y;
		float ring = disc(d, rr, 0.4 + soft * 0.5) * (0.35 + 0.65 * smoothstep(rr * 0.4, rr, d));
		col += color_c.rgb * ring * 0.4;
	}
	col = mix(col, color_b.rgb * 1.3, smoothstep(0.55, 1.1, uv.y) * 0.3);
	return col;
}

vec3 st_picture(vec2 p, vec2 uv, float t, float soft) {
	if (!has_picture) {
		return sky(uv);
	}
	// Cover the view (cropping the picture's long side), drift and breathe slowly.
	float view_aspect = view_rect.z / max(view_rect.w, 1.0);
	float pic_aspect = picture_size.x / max(picture_size.y, 1.0);
	vec2 k = view_aspect > pic_aspect ? vec2(1.0, pic_aspect / view_aspect) : vec2(view_aspect / pic_aspect, 1.0);
	float zoom = (1.08 + 0.04 * sin(t * 0.07)) * max(feature_scale, 0.05);
	vec2 pan = vec2(sin(t * 0.031), cos(t * 0.023)) * 0.025 + drift * 0.15;
	vec2 base = (uv - 0.5) * k / zoom + 0.5 + pan;
	base.x += sin(base.y * 6.0 + t * 0.4) * 0.002 * density;
	// A soft disc blur: golden-angle taps, wider with more blur, on a blurrier mip.
	float radius = blur * 0.035;
	float lod = blur * 4.0;
	vec3 sum = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 16; i++) {
		float fi = float(i);
		float rr = sqrt((fi + 0.5) / 16.0) * radius;
		float ang = fi * 2.39996;
		vec2 o = vec2(cos(ang), sin(ang)) * rr * vec2(1.0, view_aspect);
		sum += textureLod(picture, clamp(base + o, vec2(0.001), vec2(0.999)), lod).rgb;
		total += 1.0;
	}
	vec3 col = sum / total * color_c.rgb;
	return mix(col, color_d.rgb, color_d.a * 0.5);
}

void fragment() {
	vec2 local = px + rect_origin;
	vec2 uv = (local - view_rect.xy) / max(view_rect.zw, vec2(1.0));
	float aspect = view_rect.z / max(view_rect.w, 1.0);
	vec2 p = ((uv - 0.5) * vec2(aspect, 1.0) + drift) / max(feature_scale, 0.05);
	float t = TIME * speed + seed * 13.0;
	float soft = mix(0.12, 1.0, blur);
	vec3 col;
	switch (style) {
		case BOKEH: col = st_bokeh(p, uv, t, soft); break;
		case AURORA: col = st_aurora(p, uv, t, soft); break;
		case NEBULA: col = st_nebula(p, uv, t, soft); break;
		case MOLTEN_BLOBS: col = st_blobs(p, uv, t, soft); break;
		case DEEP_WATER: col = st_water(p, uv, t, soft); break;
		case EMBER_GLOW: col = st_embers(p, uv, t, soft); break;
		case STORM_CLOUDS: col = st_storm(p, uv, t, soft); break;
		case FOREST_CANOPY: col = st_canopy(p, uv, t, soft); break;
		case SUNSET_HAZE: col = st_sunset(p, uv, t, soft); break;
		case CRYSTAL_CAVE: col = st_crystal(p, uv, t, soft); break;
		case VOID_PULSE: col = st_void(p, uv, t, soft); break;
		case BLOOD_MOON: col = st_blood_moon(p, uv, t, soft); break;
		case ARCANE_VORTEX: col = st_vortex(p, uv, t, soft); break;
		case FROZEN_NIGHT: col = st_frozen(p, uv, t, soft); break;
		case SPORE_DRIFT: col = st_spores(p, uv, t, soft); break;
		case INFECTION: col = st_infection(p, uv, t, soft); break;
		case STARFIELD: col = st_starfield(p, uv, t, soft); break;
		case HOLY_LIGHT: col = st_holy(p, uv, t, soft); break;
		case TOXIC_SWAMP: col = st_toxic(p, uv, t, soft); break;
		default: col = st_picture(p, uv, t, soft); break;
	}
	// A throb (boss rooms): a double beat, like a heart.
	float ph = fract(TIME * pulse_rate);
	float beat = exp(-ph * 9.0) + 0.6 * exp(-max(ph - 0.24, 0.0) * 9.0) * step(0.24, ph);
	col *= brightness * (1.0 + pulse * beat * 0.45);
	col += color_c.rgb * pulse * beat * 0.06;
	float vig = smoothstep(0.35, 1.0, length((uv - 0.5) * vec2(1.0, 0.9)) * 1.45);
	col *= 1.0 - vignette * vig;
	col += (env_hash(FRAGCOORD.xy + floor(TIME * 24.0) * vec2(17.0, 31.0)) - 0.5) * (0.004 + grain * 0.045);
	COLOR = vec4(max(col, vec3(0.0)), intensity * env_edge(px));
}
