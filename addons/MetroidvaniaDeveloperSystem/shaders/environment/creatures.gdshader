shader_type canvas_item;
// Creatures (MDSCreatures): a background of living things, one kind at a time: bees, wasps,
// lumaflies, moths, butterflies, dragonflies, small birds, crows, bats, firebirds, spiders,
// beetles, centipedes, snails, crabs, jellyfish, glowfish, eels, owls or worms. The node moves
// them (`cpos`, `cstate`); here each one is drawn soft, out of focus, glowing, and carries a light
// that lights its habitat behind it (`habitat`) as it moves.
//
// Laid out like the animated backgrounds: `p` has the view's middle at (0, 0) and its height 1,
// plus `drift`, the little it moves with the camera.

render_mode blend_premul_alpha;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

const int BEES = 0;
const int WASPS = 1;
const int LUMAFLIES = 2;
const int MOTHS = 3;
const int BUTTERFLIES = 4;
const int DRAGONFLIES = 5;
const int SONGBIRDS = 6;
const int CROWS = 7;
const int BATS = 8;
const int FIREBIRDS = 9;
const int SPIDERS = 10;
const int BEETLES = 11;
const int CENTIPEDES = 12;
const int SNAILS = 13;
const int CRABS = 14;
const int JELLYFISH = 15;
const int GLOWFISH = 16;
const int EELS = 17;
const int OWLS = 18;
const int WORMS = 19;

const int HIVE = 0;
const int WEB_CAVE = 1;
const int FOREST = 2;
const int SKY = 3;
const int CAVE = 4;
const int DEEP_WATER = 5;
const int EARTH = 6;
const int MARSH = 7;

uniform int creature = 0;
uniform int habitat = 0;
uniform int count = 0;
/// Per creature: x, y (plane), angle, size (negative: facing left).
uniform vec4 cpos[32];
/// Per creature: animation phase, glow, depth (0 near, 1 far), extra (a thread, a trail...).
uniform vec4 cstate[32];
uniform vec4 glow_color : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform vec4 body_color : source_color = vec4(0.1, 0.08, 0.06, 1.0);
/// The habitat's dark and its features.
uniform vec4 back_color_a : source_color = vec4(0.06, 0.04, 0.02, 1.0);
uniform vec4 back_color_b : source_color = vec4(0.35, 0.22, 0.06, 1.0);
uniform float blur : hint_range(0.0, 1.0) = 0.5;
/// How far a creature's light reaches (view heights).
uniform float light_radius = 0.14;
uniform float light_strength = 1.0;
/// Light on the habitat with no creature near.
uniform float ambient : hint_range(0.0, 1.0) = 0.3;
/// How much of the habitat is drawn behind them (0: none, only the creatures).
uniform float backdrop : hint_range(0.0, 1.0) = 1.0;
uniform vec2 drift = vec2(0.0);
uniform vec4 view_rect = vec4(0.0, 0.0, 1152.0, 648.0);

void vertex() {
	px = VERTEX - rect_origin;
}

float sat(float x) {
	return clamp(x, 0.0, 1.0);
}

float cov(float d, float s) {
	return 1.0 - smoothstep(-s, s, d);
}

float sd_el(vec2 p, vec2 r) {
	return (length(p / max(r, vec2(0.0001))) - 1.0) * min(r.x, r.y);
}

float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float sd_c(vec2 p, float r) {
	return length(p) - r;
}

int oct() {
	return max(2, 4 - int(round(blur * 2.0)));
}

// --- Habitats (what is behind them, lit by them) ----------------------------------------------------

vec3 hab_hive(vec2 p) {
	vec2 q = p * 9.0;
	vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(q, q - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(q - hc.xy * s, q - (hc.zw + 0.5) * s);
	bool first = dot(h.xy, h.xy) < dot(h.zw, h.zw);
	vec2 cell = first ? h.xy : h.zw;
	vec2 id = first ? hc.xy : hc.zw + 0.5;
	vec2 ab = abs(cell);
	float edge = 0.5 - max(dot(ab, normalize(s)), ab.x);
	float wall = 1.0 - smoothstep(0.0, 0.07 + blur * 0.12, edge);
	float filled = step(0.45, env_hash(id + seed));
	vec3 inside = mix(back_color_a.rgb, back_color_b.rgb, filled * (0.55 + 0.45 * sat(edge * 2.5)));
	return mix(inside, back_color_b.rgb * 1.35, wall);
}

vec3 hab_web_cave(vec2 p) {
	float rock = env_fbm(p * 3.0 + seed, oct());
	vec3 c = mix(back_color_a.rgb, back_color_b.rgb, smoothstep(0.3, 0.8, rock) * 0.7);
	vec2 cell = floor(p / 0.7);
	vec2 c0 = (cell + 0.3 + 0.4 * env_hash2(cell + seed)) * 0.7;
	vec2 q = p - c0;
	float a = atan(q.y, q.x);
	float spoke = abs(fract(a / 6.2832 * 9.0) - 0.5) * length(q) * 6.2832 / 9.0;
	float ring = abs(fract(length(q) * 14.0) - 0.5) / 14.0;
	float web = (1.0 - smoothstep(0.0, 0.004 + blur * 0.006, min(spoke, ring))) * (1.0 - smoothstep(0.12, 0.3, length(q))) * step(env_hash(cell + seed + 4.0), 0.55);
	return c + vec3(0.55) * web * 0.35;
}

vec3 hab_forest(vec2 p) {
	vec3 c = mix(back_color_b.rgb * 0.7, back_color_a.rgb, smoothstep(-0.6, 0.6, p.y));
	float trunks = smoothstep(0.86, 0.95, sin(p.x * 7.0 + env_noise(vec2(p.y * 2.0, seed)) * 1.5));
	c = mix(c, back_color_a.rgb * 0.7, trunks * 0.8);
	float far = smoothstep(0.46, 0.62, env_fbm(p * vec2(3.0, 4.0) + seed, oct()));
	c = mix(c, back_color_b.rgb, far * 0.55);
	float near = smoothstep(0.5, 0.64, env_fbm(p * vec2(5.0, 6.0) + seed + 7.0, oct()));
	return mix(c, back_color_a.rgb * 0.55, near * 0.8);
}

vec3 hab_sky(vec2 p) {
	vec3 c = mix(back_color_b.rgb, back_color_a.rgb, smoothstep(-0.6, 0.5, p.y));
	float cloud = smoothstep(0.42, 0.75, env_fbm(vec2(p.x * 1.2, p.y * 3.0) + seed + TIME * 0.005, oct()));
	return mix(c, mix(back_color_b.rgb, vec3(1.0), 0.25), cloud * 0.35);
}

vec3 hab_cave(vec2 p) {
	float rock = env_fbm(p * 2.5 + seed, oct());
	vec3 c = mix(back_color_a.rgb, back_color_b.rgb, smoothstep(0.3, 0.8, rock) * 0.6);
	float col = floor(p.x / 0.1);
	float h = env_hash(vec2(col, seed));
	float len = 0.08 + 0.3 * h;
	float x = (col + 0.5) * 0.1;
	float top = -0.55;
	float t = sat((p.y - top) / len);
	float drip = step(abs(p.x - x), 0.035 * (1.0 - t)) * step(p.y, top + len);
	float bottom = 0.55;
	float h2 = env_hash(vec2(col, seed + 3.0));
	float len2 = 0.05 + 0.18 * h2;
	float t2 = sat((bottom - p.y) / len2);
	float mound = step(abs(p.x - x - 0.03), 0.04 * (1.0 - t2)) * step(bottom - len2, p.y);
	return mix(c, back_color_a.rgb * 0.5, max(drip, mound) * 0.85);
}

vec3 hab_deep_water(vec2 p) {
	vec3 c = mix(back_color_b.rgb, back_color_a.rgb, smoothstep(-0.6, 0.6, p.y));
	float rays = pow(0.5 + 0.5 * sin((p.x + p.y * 0.3) * 8.0 + TIME * 0.2), 6.0) * (1.0 - smoothstep(-0.5, 0.3, p.y));
	c += back_color_b.rgb * rays * 0.35;
	vec2 q = p * 30.0 + vec2(0.0, TIME * 0.6);
	vec2 id = floor(q);
	float mote = step(env_hash(id + seed), 0.06) * (1.0 - smoothstep(0.1, 0.35, length(fract(q) - 0.5)));
	return c + vec3(0.6) * mote * 0.25;
}

vec3 hab_earth(vec2 p) {
	float strata = env_fbm(vec2(p.x * 1.5, p.y * 8.0) + seed, oct());
	vec3 c = mix(back_color_a.rgb, back_color_b.rgb, smoothstep(0.3, 0.75, strata) * 0.8);
	float roots = 1.0 - smoothstep(0.0, 0.012 + blur * 0.01, abs(sin(p.x * 5.0 + sin(p.y * 6.0 + seed) * 1.4) * 0.12 - p.y * 0.02 - 0.02));
	c = mix(c, back_color_a.rgb * 0.6, roots * 0.6 * step(p.y, 0.2));
	vec2 v = env_voronoi(p * 14.0 + seed);
	return mix(c, back_color_b.rgb * 1.2, (1.0 - smoothstep(0.15, 0.25, v.x)) * 0.25);
}

vec3 hab_marsh(vec2 p) {
	vec3 c = mix(back_color_b.rgb, back_color_a.rgb, smoothstep(-0.6, 0.2, p.y));
	float water = smoothstep(0.28, 0.3, p.y);
	c = mix(c, back_color_b.rgb * 0.6 + vec3(0.03) * sin(p.x * 60.0 + TIME), water * 0.7);
	float col = floor(p.x / 0.025);
	float h = env_hash(vec2(col, seed));
	float top = 0.1 + 0.2 * h;
	float x = (col + 0.5) * 0.025 + sin(TIME * 0.6 + col) * 0.004 * (0.4 - p.y);
	float reed = step(abs(p.x - x), 0.004) * step(top, p.y) * step(p.y, 0.4) * step(h, 0.7);
	return mix(c, back_color_a.rgb * 0.5, reed);
}

vec3 hab(vec2 p) {
	switch (habitat) {
		case HIVE: return hab_hive(p);
		case WEB_CAVE: return hab_web_cave(p);
		case FOREST: return hab_forest(p);
		case SKY: return hab_sky(p);
		case CAVE: return hab_cave(p);
		case DEEP_WATER: return hab_deep_water(p);
		case EARTH: return hab_earth(p);
	}
	return hab_marsh(p);
}

// --- The creatures: body (silhouette) and emit (what glows), in their own units ------------------

vec2 c_bee(vec2 q, float ph, float s) {
	float flap = 0.25 + 0.75 * abs(sin(ph));
	float abd = sd_el(q - vec2(-0.3, 0.05), vec2(0.55, 0.38));
	float body = min(min(abd, sd_c(q - vec2(0.25, 0.0), 0.27)), sd_c(q - vec2(0.55, 0.04), 0.19));
	float wing = sd_el(env_rotate(q - vec2(-0.05, -0.42), 0.35), vec2(0.38, 0.24 * flap));
	float stripe = step(0.5, fract((q.x + 0.3) * 3.2));
	return vec2(max(cov(body, s), cov(wing, s) * 0.45), cov(abd, s) * (0.45 + 0.55 * stripe));
}

vec2 c_wasp(vec2 q, float ph, float s) {
	float flap = 0.25 + 0.75 * abs(sin(ph));
	float abd = sd_el(q - vec2(-0.45, 0.06), vec2(0.62, 0.25));
	float body = min(min(abd, sd_c(q - vec2(0.15, 0.0), 0.2)), sd_c(q - vec2(0.42, 0.02), 0.16));
	body = min(body, sd_seg(q, vec2(-0.05, 0.03), vec2(0.15, 0.0), 0.06));
	float wing = sd_el(env_rotate(q - vec2(-0.15, -0.36), 0.25), vec2(0.5, 0.15 * flap));
	float stripe = step(0.45, fract((q.x + 0.45) * 4.0));
	return vec2(max(cov(body, s), cov(wing, s) * 0.4), cov(abd, s) * (0.3 + 0.7 * stripe));
}

vec2 c_lumafly(vec2 q, float ph, float s) {
	float flap = 0.3 + 0.7 * abs(sin(ph));
	float body = sd_el(q - vec2(0.2, -0.05), vec2(0.32, 0.2));
	float lantern = sd_c(q - vec2(-0.28, 0.1), 0.38);
	float wing = sd_el(q - vec2(0.05, -0.38), vec2(0.3, 0.22 * flap));
	return vec2(max(cov(min(body, lantern), s), cov(wing, s) * 0.3), cov(lantern, s));
}

vec2 c_moth(vec2 q, float ph, float s) {
	float w = 0.35 + 0.65 * abs(cos(ph));
	vec2 m = vec2(q.x, abs(q.y));
	float wing = sd_el(env_rotate(m - vec2(-0.05, 0.45 * w), 0.45), vec2(0.45, 0.55 * w));
	float hind = sd_el(m - vec2(-0.35, 0.3 * w), vec2(0.3, 0.32 * w));
	float body = sd_seg(q, vec2(-0.5, 0.0), vec2(0.45, 0.0), 0.12);
	float ant = sd_seg(m, vec2(0.45, 0.04), vec2(0.75, 0.2), 0.02);
	float spot = sd_c(m - vec2(-0.05, 0.5 * w), 0.13);
	return vec2(max(cov(min(min(wing, hind), body), s) * 0.9, cov(ant, s)), cov(spot, s) + cov(body, s) * 0.3);
}

vec2 c_butterfly(vec2 q, float ph, float s) {
	float w = 0.2 + 0.8 * abs(cos(ph));
	vec2 m = vec2(q.x, abs(q.y));
	float front = sd_el(m - vec2(0.15, 0.5 * w), vec2(0.45, 0.48 * w));
	float hind = sd_el(m - vec2(-0.3, 0.4 * w), vec2(0.35, 0.36 * w));
	float wings = min(front, hind);
	float body = sd_seg(q, vec2(-0.45, 0.0), vec2(0.45, 0.0), 0.08);
	float edge = cov(abs(wings + 0.04) - 0.04, s) * cov(wings, s);
	float spot = cov(sd_c(m - vec2(0.2, 0.55 * w), 0.1), s);
	return vec2(cov(min(wings, body), s), max(edge, spot) + cov(wings, s) * 0.15);
}

vec2 c_dragonfly(vec2 q, float ph, float s) {
	vec2 m = vec2(q.x, abs(q.y));
	float tail = sd_seg(q, vec2(-1.0, 0.0), vec2(0.4, 0.0), 0.07);
	float body = min(min(tail, sd_c(q - vec2(0.42, 0.0), 0.13)), sd_c(q - vec2(0.62, 0.0), 0.11));
	float front = sd_el(env_rotate(m - vec2(0.3, 0.5), 0.15), vec2(0.12, 0.48));
	float hind = sd_el(env_rotate(m - vec2(0.1, 0.46), -0.15), vec2(0.11, 0.44));
	float flutter = 0.3 + 0.25 * abs(sin(ph * 3.0));
	return vec2(max(cov(body, s), cov(min(front, hind), s) * flutter), cov(tail, s) * 0.8 + cov(sd_c(q - vec2(0.62, 0.0), 0.11), s));
}

vec2 c_bird(vec2 q, float ph, float s, float span, bool fire) {
	float f = sin(ph);
	float body = sd_el(q, vec2(0.5, 0.3));
	body = min(body, sd_c(q - vec2(0.48, -0.18), 0.21));
	body = min(body, sd_seg(q, vec2(0.66, -0.19), vec2(0.88, -0.15), 0.035));
	float tail = sd_seg(q, vec2(-0.4, -0.02), vec2(-0.95, -0.1), 0.09);
	float wing = sd_seg(q, vec2(0.05, -0.12), vec2(-0.25 * span, -0.12 - 0.75 * span * f), 0.16);
	wing = min(wing, sd_el(q - vec2(-0.05, -0.12 - 0.3 * span * f), vec2(0.32, 0.14)));
	float all_d = min(min(body, tail), wing);
	if (fire) {
		float flame = sd_seg(q, vec2(-0.35, 0.0), vec2(-1.7, 0.12 * sin(ph * 0.5)), 0.13);
		float fl = cov(flame, s * 2.5) * smoothstep(-1.7, -0.3, q.x);
		return vec2(cov(all_d, s) * 0.5, cov(all_d, s) * 0.85 + fl);
	}
	float chest = cov(sd_el(q - vec2(0.18, 0.08), vec2(0.3, 0.2)), s);
	return vec2(cov(all_d, s), chest);
}

vec2 c_crow(vec2 q, float ph, float s) {
	float f = sin(ph);
	float body = sd_el(q, vec2(0.55, 0.28));
	body = min(body, sd_c(q - vec2(0.5, -0.2), 0.22));
	body = min(body, sd_seg(q, vec2(0.68, -0.2), vec2(0.98, -0.14), 0.05));
	float tail = sd_seg(q, vec2(-0.45, -0.02), vec2(-1.0, 0.0), 0.13);
	float wing = sd_seg(q, vec2(0.05, -0.12), vec2(-0.45, -0.15 - 0.95 * f), 0.18);
	wing = min(wing, sd_seg(q, vec2(-0.45, -0.15 - 0.95 * f), vec2(-0.9, -0.05 - 1.1 * f), 0.1));
	float eye = cov(sd_c(q - vec2(0.55, -0.26), 0.055), s * 0.6);
	return vec2(cov(min(min(body, tail), wing), s), eye * 1.6);
}

vec2 c_bat(vec2 q, float ph, float s) {
	float f = sin(ph);
	vec2 m = vec2(abs(q.x), q.y);
	float body = sd_el(q - vec2(0.0, 0.05), vec2(0.22, 0.32));
	body = min(body, sd_c(q - vec2(0.0, -0.3), 0.16));
	body = min(body, sd_seg(m, vec2(0.08, -0.4), vec2(0.14, -0.58), 0.04));
	float wing = sd_el(env_rotate(m - vec2(0.58, -0.05 - 0.25 * f), -0.3 * f), vec2(0.52, 0.22 + 0.08 * f));
	float notch = min(sd_c(m - vec2(0.42, 0.22 - 0.25 * f), 0.13), sd_c(m - vec2(0.75, 0.2 - 0.3 * f), 0.13));
	wing = max(wing, -notch);
	float eyes = cov(sd_c(m - vec2(0.06, -0.32), 0.035), s * 0.6);
	return vec2(cov(min(body, wing), s), eyes * 1.5);
}

vec2 c_spider(vec2 q, float ph, float s) {
	vec2 m = vec2(q.x, abs(q.y));
	float side = q.y >= 0.0 ? 0.0 : 3.1416;
	float abd = sd_el(q - vec2(-0.4, 0.0), vec2(0.45, 0.36));
	float body = min(abd, sd_c(q - vec2(0.22, 0.0), 0.24));
	float legs = 1e3;
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		vec2 hip = vec2(0.28 - fk * 0.13, 0.12);
		// Front legs reach forward, back legs back; each steps in turn.
		float a = mix(0.55, 2.55, fk / 3.0) + sin(ph + fk * 1.57 + side) * 0.22;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 knee = hip + dir * 0.42 + vec2(0.0, 0.12);
		vec2 foot = knee + dir * 0.42 + vec2(0.0, 0.08);
		legs = min(legs, min(sd_seg(m, hip, knee, 0.035), sd_seg(m, knee, foot, 0.028)));
	}
	float eyes = cov(sd_c(m - vec2(0.4, 0.06), 0.05), s * 0.6);
	float mark = cov(sd_el(q - vec2(-0.45, 0.0), vec2(0.16, 0.1)), s);
	return vec2(max(cov(body, s), cov(legs, s)), eyes * 1.4 + mark * 0.8);
}

vec2 c_beetle(vec2 q, float ph, float s) {
	vec2 m = vec2(q.x, abs(q.y));
	float side = q.y >= 0.0 ? 0.0 : 3.1416;
	float shell = sd_el(q - vec2(-0.1, 0.0), vec2(0.6, 0.42));
	float body = min(shell, sd_el(q - vec2(0.58, 0.0), vec2(0.18, 0.16)));
	float legs = 1e3;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float g = sin(ph + fk * 2.1 + side) * 0.08;
		legs = min(legs, sd_seg(m, vec2(0.3 - fk * 0.25, 0.3), vec2(0.38 - fk * 0.3 + g, 0.62), 0.035));
	}
	float seam = cov(abs(q.y) - 0.015, s) * cov(shell, s);
	float spots = cov(sd_c(m - vec2(-0.2, 0.2), 0.1), s) + cov(sd_c(m - vec2(0.2, 0.15), 0.07), s);
	float rim = cov(abs(shell + 0.04) - 0.03, s);
	return vec2(max(cov(body, s), cov(legs, s)), spots + rim * 0.6 + seam * 0.3);
}

vec2 c_centipede(vec2 q, float ph, float s) {
	float body = 1e3;
	float legs = 1e3;
	float dots = 1e3;
	for (int k = 0; k < 10; k++) {
		float fk = float(k);
		vec2 c = vec2(0.6 - fk * 0.21, sin(ph - fk * 0.7) * 0.09);
		body = min(body, sd_c(q - c, 0.12 - fk * 0.004));
		float tilt = sin(ph * 2.0 + fk) * 0.08;
		legs = min(legs, sd_seg(q, c + vec2(tilt, -0.25), c + vec2(-tilt, 0.25), 0.02));
		dots = min(dots, sd_c(q - c, 0.045));
	}
	return vec2(max(cov(body, s), cov(legs, s)), cov(dots, s) + cov(sd_c(q - vec2(0.68, 0.0), 0.06), s));
}

vec2 c_snail(vec2 q, float ph, float s, float trail) {
	float body = sd_el(q - vec2(0.1, 0.2), vec2(0.7, 0.14));
	vec2 sc = q - vec2(-0.15, -0.05);
	float shell = sd_c(sc, 0.42);
	body = min(body, min(sd_seg(q, vec2(0.65, 0.12), vec2(0.85, -0.15), 0.025), sd_seg(q, vec2(0.58, 0.12), vec2(0.7, -0.12), 0.022)));
	float r = length(sc);
	float a = atan(sc.y, sc.x);
	float spiral = abs(fract(r * 5.0 - a / 6.2832) - 0.5) / 5.0;
	float glow_spiral = cov(spiral - 0.02, s) * cov(shell, s);
	float t = q.x < -0.5 && q.x > -0.5 - trail ? cov(abs(q.y - 0.28) - 0.05, s) * smoothstep(-0.5 - trail, -0.5, q.x) : 0.0;
	float tips = cov(sd_c(q - vec2(0.85, -0.15), 0.05), s) + cov(sd_c(q - vec2(0.7, -0.12), 0.045), s);
	return vec2(cov(min(body, shell), s), glow_spiral + t * 0.8 + tips);
}

vec2 c_crab(vec2 q, float ph, float s) {
	vec2 m = vec2(abs(q.x), q.y);
	float f = sin(ph);
	float body = sd_el(q, vec2(0.55, 0.32));
	float arm = sd_seg(m, vec2(0.45, -0.05), vec2(0.72, -0.35 - 0.1 * f), 0.06);
	float claw = sd_c(m - vec2(0.8, -0.45 - 0.1 * f), 0.17);
	float legs = 1e3;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		legs = min(legs, sd_seg(m, vec2(0.3 - fk * 0.12, 0.15), vec2(0.6 - fk * 0.1, 0.45 + 0.05 * sin(ph * 2.0 + fk)), 0.035));
	}
	float stalks = sd_seg(m, vec2(0.12, -0.28), vec2(0.16, -0.45), 0.03);
	float eyes = cov(sd_c(m - vec2(0.16, -0.47), 0.05), s);
	float spots = cov(sd_c(m - vec2(0.22, -0.05), 0.08), s);
	return vec2(cov(min(min(body, arm), min(claw, min(legs, stalks))), s), cov(claw, s) * 0.8 + eyes * 1.3 + spots * 0.6);
}

vec2 c_jellyfish(vec2 q, float ph, float s) {
	float pulse = 0.5 + 0.5 * sin(ph);
	float bell = max(sd_el(q, vec2(0.55 + 0.1 * pulse, 0.42 - 0.08 * pulse)), q.y - 0.12);
	float tent = 1e3;
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		float x = -0.32 + fk * 0.16 + sin(q.y * 6.0 - ph * 1.5 + fk) * 0.07;
		float len = 1.4 - mod(fk, 2.0) * 0.35;
		float w = 0.025 * (1.0 - sat((q.y - 0.1) / len));
		float d = (q.y > 0.1 && q.y < 0.1 + len) ? abs(q.x - x) - w : 1e3;
		tent = min(tent, d);
	}
	float inner = cov(bell, s) * (0.55 + 0.45 * (1.0 - sat(length(q) / 0.6)));
	return vec2(max(cov(bell, s) * 0.7, cov(tent, s) * 0.6), inner + cov(tent, s) * 0.5);
}

vec2 c_fish(vec2 q, float ph, float s) {
	float w = sin(ph);
	float body = sd_el(q - vec2(0.05, 0.0), vec2(0.6, 0.27));
	float tail = min(sd_seg(q, vec2(-0.5, 0.0), vec2(-0.92, -0.25 + w * 0.12), 0.07), sd_seg(q, vec2(-0.5, 0.0), vec2(-0.92, 0.25 + w * 0.12), 0.07));
	float fin = sd_seg(q, vec2(0.0, -0.25), vec2(-0.2, -0.4), 0.05);
	float line = cov(abs(q.y - 0.02 - 0.03 * sin(q.x * 6.0)) - 0.035, s) * cov(body, s);
	float eye = cov(sd_c(q - vec2(0.42, -0.06), 0.05), s);
	return vec2(cov(min(min(body, tail), fin), s), line + eye + cov(body, s) * 0.15);
}

vec2 c_eel(vec2 q, float ph, float s) {
	float y = sin(q.x * 3.2 - ph) * 0.12 * (0.3 + (0.45 - q.x) * 0.35);
	float th = 0.13 * smoothstep(-1.75, -1.1, q.x) * (1.0 - smoothstep(0.3, 0.5, q.x));
	float body = (q.x > -1.8 && q.x < 0.5) ? abs(q.y - y) - th : 1e3;
	float hy = sin(0.38 * 3.2 - ph) * 0.12 * 0.32;
	body = min(body, sd_el(q - vec2(0.38, hy), vec2(0.17, 0.12)));
	vec2 dq = vec2(fract(q.x * 4.0) - 0.5, (q.y - y) * 4.0);
	float spots = (q.x > -1.5 && q.x < 0.3) ? cov(length(dq) - 0.22, s * 4.0) : 0.0;
	return vec2(cov(body, s), spots * 0.9 + cov(sd_c(q - vec2(0.45, hy - 0.03), 0.035), s));
}

vec2 c_owl(vec2 q, float look, float s, float blink) {
	vec2 m = vec2(abs(q.x), q.y);
	float body = sd_el(q - vec2(0.0, 0.15), vec2(0.48, 0.6));
	body = min(body, sd_c(q - vec2(look * 0.05, -0.55), 0.38));
	body = min(body, sd_seg(vec2(abs(q.x - look * 0.05), q.y), vec2(0.22, -0.82), vec2(0.32, -1.0), 0.06));
	float perch = sd_seg(q, vec2(-1.3, 0.75), vec2(1.3, 0.8), 0.07);
	vec2 em = vec2(abs(q.x - look * 0.08), q.y);
	float eyes = sd_el(em - vec2(0.15, -0.58), vec2(0.11, 0.11 * (1.0 - blink) + 0.004));
	float chest = cov(sd_el(q - vec2(0.0, 0.2), vec2(0.25, 0.32)), s) * 0.2;
	return vec2(cov(min(body, perch), s), cov(eyes, s * 0.7) * 1.4 + chest);
}

vec2 c_worm(vec2 q, float ph, float s, float progress) {
	if (progress < 0.0) {
		return vec2(cov(min(sd_el(q - vec2(-0.8, 0.0), vec2(0.3, 0.1)), sd_el(q - vec2(0.8, 0.0), vec2(0.3, 0.1))), s) * 0.8, 0.0);
	}
	float big_r = 0.8;
	float th = 0.16;
	float head = 3.1416 - progress * 3.1416 * 1.5;
	float tail_a = head + 1.7;
	float a = atan(-q.y, q.x);
	float lo = max(head, 0.0);
	float hi = min(tail_a, 3.1416);
	float on = (a >= lo && a <= hi) ? 1.0 : 0.0;
	float d = abs(length(q) - big_r) - th;
	float worm_d = on > 0.5 ? d : 1e3;
	if (head > 0.0) {
		worm_d = min(worm_d, sd_c(q - vec2(cos(head), -sin(head)) * big_r, th * 1.05));
	}
	float above = step(q.y, 0.0);
	float dirt = min(sd_el(q - vec2(-big_r, 0.0), vec2(0.3, 0.1)), sd_el(q - vec2(big_r, 0.0), vec2(0.3, 0.1)));
	float rings = step(0.5, fract(a * 8.0 + ph * 0.3)) * cov(worm_d, s);
	float tip = head > 0.0 ? cov(sd_c(q - vec2(cos(head), -sin(head)) * big_r, th * 0.7), s) : 0.0;
	return vec2(max(cov(worm_d, s) * above, cov(dirt, s) * 0.8), (rings * 0.6 + tip) * above);
}

vec2 shape(vec2 q, vec4 cs, float s) {
	switch (creature) {
		case BEES: return c_bee(q, cs.x, s);
		case WASPS: return c_wasp(q, cs.x, s);
		case LUMAFLIES: return c_lumafly(q, cs.x, s);
		case MOTHS: return c_moth(q, cs.x, s);
		case BUTTERFLIES: return c_butterfly(q, cs.x, s);
		case DRAGONFLIES: return c_dragonfly(q, cs.x, s);
		case SONGBIRDS: return c_bird(q, cs.x, s, 1.0, false);
		case CROWS: return c_crow(q, cs.x, s);
		case BATS: return c_bat(q, cs.x, s);
		case FIREBIRDS: return c_bird(q, cs.x, s, 1.2, true);
		case SPIDERS: return c_spider(q, cs.x, s);
		case BEETLES: return c_beetle(q, cs.x, s);
		case CENTIPEDES: return c_centipede(q, cs.x, s);
		case SNAILS: return c_snail(q, cs.x, s, cs.w);
		case CRABS: return c_crab(q, cs.x, s);
		case JELLYFISH: return c_jellyfish(q, cs.x, s);
		case GLOWFISH: return c_fish(q, cs.x, s);
		case EELS: return c_eel(q, cs.x, s);
		case OWLS: return c_owl(q, cs.x, s, cs.w);
	}
	return c_worm(q, cs.x, s, cs.w);
}

// How far (in its own units) a creature's drawing reaches from its middle.
float reach() {
	switch (creature) {
		case FIREBIRDS: return 2.0;
		case EELS: return 2.0;
		case DRAGONFLIES: return 1.3;
		case CENTIPEDES: return 1.6;
		case JELLYFISH: return 1.7;
		case CROWS: return 1.8;
		case OWLS: return 1.5;
	}
	return 1.25;
}

void fragment() {
	vec2 local = px + rect_origin;
	vec2 uv = (local - view_rect.xy) / max(view_rect.zw, vec2(1.0));
	float aspect = view_rect.z / max(view_rect.w, 1.0);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0) + drift;
	float px_size = 1.0 / max(view_rect.w, 1.0);
	vec3 gcol = glow_color.rgb;
	float rch = reach();
	// One pass over them: their light on the habitat, and their bodies and halos in a layer of
	// their own (premultiplied), far ones first, laid over the lit habitat at the end.
	vec3 light = vec3(ambient);
	float thread = 0.0;
	vec3 lay = vec3(0.0);
	float lay_a = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= count) {
			break;
		}
		vec4 cp = cpos[i];
		vec4 cs = cstate[i];
		vec2 d = p - cp.xy;
		// A hanging spider's thread runs up from it, beyond its light.
		if (creature == SPIDERS && cs.w > 0.0 && p.y > cp.y - cs.w && p.y < cp.y) {
			thread = max(thread, (1.0 - smoothstep(0.0, px_size * (1.0 + blur * 2.0), abs(d.x))) * (0.35 + 0.65 * sat(cs.y)));
		}
		float lr = light_radius * mix(1.0, 0.6, cs.z);
		float sz = max(abs(cp.w), 0.0005);
		float body_reach = sz * (creature == SNAILS ? rch + cs.w : rch);
		float far = max(lr * 3.0, max(body_reach, sz * 6.0));
		if (abs(d.x) > far || abs(d.y) > far) {
			continue;
		}
		float dd = dot(d, d);
		if (dd < lr * lr * 9.0) {
			light += gcol * cs.y * light_strength / (1.0 + dd / (lr * lr) * 3.0) * (1.0 - smoothstep(lr * 2.0, lr * 3.0, sqrt(dd)));
		}
		float dist = sqrt(dd);
		if (dist > max(body_reach, sz * 6.0)) {
			continue;
		}
		// A soft halo of its light around it.
		vec3 add = gcol * exp(-dist / (sz * 1.1)) * cs.y * 0.45 * (1.0 - cs.z * 0.4);
		if (dist <= body_reach) {
			vec2 q = env_rotate(d, -cp.z) / sz;
			if (cp.w < 0.0) {
				q.x = -q.x;
			}
			float soft = (px_size * 1.2 + blur * sz * 0.22 * (1.0 + cs.z * 2.0)) / sz;
			vec2 be = shape(q, cs, soft);
			float b = be.x * body_color.a * (1.0 - cs.z * 0.35);
			// Lit by its own light and the air around it; the far ones hazier.
			vec3 lit = body_color.rgb * (ambient * 1.2 + 0.15 + cs.y * light_strength) + gcol * 0.12 * cs.y;
			lit = mix(lit, back_color_a.rgb * (ambient + 0.3), cs.z * 0.4);
			lay = lit * b + lay * (1.0 - b);
			lay_a = b + lay_a * (1.0 - b);
			add += gcol * be.y * cs.y * 1.25 * (1.0 - cs.z * 0.45);
		}
		lay += add;
	}
	vec3 pm = hab(p) * light * backdrop;
	float a = backdrop;
	pm = pm * (1.0 - thread * 0.6) + vec3(0.75) * light * thread * 0.6;
	a = max(a, thread * 0.6);
	pm = lay + pm * (1.0 - lay_a);
	a = lay_a + a * (1.0 - lay_a);
	float k = intensity * env_edge(px);
	COLOR = vec4(pm * k, clamp(a, 0.0, 1.0) * k);
}
