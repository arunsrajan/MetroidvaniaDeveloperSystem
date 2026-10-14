// Shared by the machinery backgrounds (MDSMachineryBackground): machinery_gothic.gdshader and
// machinery_scifi.gdshader. Each defines `vec4 machine(vec2 q, float t, float v, inout float g2)`
// for its twenty machines, `vec4 machine_bounds(float v)` (the box, x0, x1, y0, y1 in the
// machine's space, outside which it draws nothing, its glow included) and `bool machine_rope()`
// (it hangs from a rope or chain running straight up from its box), then includes
// machinery_draw.gdshaderinc.
//
// A machine is drawn in its own space `q`: its middle at (0, 0), about 1 across its radius (a
// hanging one hangs from (0, -1), a standing one stands on y = 1). `t` is its own time (it turns,
// swings and pumps by time alone), `v` varies it (0..1). It returns:
//   x: the signed distance to its solid parts (negative inside), in its own units;
//   y: how much its lights glow there (in light_color); g2 is the glow in accent_color;
//   z: shading of its solid parts (1: plain);
//   w: 0 for metal or stone (metal_color), 1 for the parts in accent_color (bronze, cloth...).
//
// Machines are fixed in the world: laid out on the rectangle (in the node's own coordinates,
// divided by `unit`, a screen-sized cell's height in px), so the camera pans over them as over
// the room and nothing but time moves them. inst_a holds each one's place (x, y), size (its
// radius) and depth (0 near, 1 far); inst_b its phase, pace (negative: turning the other way),
// variety and mirror (1 or -1). The far ones are drawn first, fading into the haze; all are out
// of focus, the nearest and farthest the most.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

render_mode blend_premul_alpha, unshaded;

const int MAX_MACHINES = 12;

uniform int kind = 0;
uniform int count = 0;
uniform vec4 inst_a[MAX_MACHINES];
uniform vec4 inst_b[MAX_MACHINES];
/// The backdrop: its top and its bottom (the haze the far machines fade into).
uniform vec4 back_top : source_color = vec4(0.05, 0.05, 0.09, 1.0);
uniform vec4 back_bottom : source_color = vec4(0.12, 0.10, 0.16, 1.0);
/// The machines' iron, stone or steel.
uniform vec4 metal_color : source_color = vec4(0.16, 0.14, 0.18, 1.0);
/// Their lights: flames, lit windows, energy.
uniform vec4 light_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
/// Their other material (bronze, cloth, glass) and second light.
uniform vec4 accent_color : source_color = vec4(0.55, 0.38, 0.22, 1.0);
uniform float speed = 1.0;
/// How out of focus they are (0 sharp, 1 very soft).
uniform float blur : hint_range(0.0, 1.0) = 0.55;
uniform float brightness = 1.0;
/// How much the far machines fade into the backdrop.
uniform float haze : hint_range(0.0, 1.0) = 0.6;
uniform float vignette : hint_range(0.0, 1.0) = 0.4;
uniform float grain : hint_range(0.0, 1.0) = 0.25;
/// A light catching the machines' edges, so dark iron still reads against the dark.
uniform float rim_light : hint_range(0.0, 1.0) = 0.5;
/// Draw a backdrop of its own (off: only the machines, over what is behind).
uniform bool backdrop = true;
/// The layout's unit (px): the height of a cell of it.
uniform float unit = 648.0;
/// What the machines are laid out on (local px): the room, its backdrop's gradient running down it.
uniform vec4 layout_rect = vec4(0.0, 0.0, 1152.0, 648.0);

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_rbox(vec2 p, vec2 b, float r) {
	return sd_box(p, b - vec2(r)) - r;
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_ring(vec2 p, float r, float w) {
	return abs(length(p) - r) - w;
}

// An isosceles triangle: its apex at (0, 0), its base `q.y` below, `q.x` either side.
float sd_tri(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}

// An ellipse's outline as a ring: radii `ab`, `w` thick (close to a distance near the line).
float sd_ellipse_ring(vec2 p, vec2 ab, float w) {
	vec2 r = max(ab, vec2(0.01));
	float k = length(p / r);
	return abs((k - 1.0) * min(r.x, r.y)) - w;
}

// `p` turned into the first of `n` sectors around the middle (the sector along +x).
vec2 polar_rep(vec2 p, float n) {
	float s = TAU / n;
	float a = mod(atan(p.y, p.x) + s * 0.5, s) - s * 0.5;
	return vec2(cos(a), sin(a)) * length(p);
}

// Which of `n` sectors around the middle `p` is in (0..n-1).
float sector(vec2 p, float n) {
	return floor(mod(atan(p.y, p.x) / TAU * n + n + 0.5, n));
}

// A cogwheel: a disc `r` round with `teeth` teeth `h` high.
float sd_gear(vec2 p, float r, float teeth, float h) {
	vec2 q = polar_rep(p, teeth);
	float body = length(p) - r;
	float tooth = sd_rbox(q - vec2(r + h * 0.45, 0.0), vec2(h * 0.55, r * PI / teeth * 0.42), h * 0.2);
	return min(body, tooth);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// A soft light around distance `d` (0 at the light), `r` wide.
float glow_at(float d, float r) {
	return exp(-max(d, 0.0) / max(r, 1e-4));
}

// A wide soft light `r` round, falling to nothing (unlike glow_at's long tail): for halos that
// must fade out inside the machine's box.
float halo(float d, float r) {
	float k = max(d, 0.0) / max(r, 1e-4);
	return exp(-k * k);
}

// A flame's flicker (0.6..1.2) at time `t`, varied by `v`.
float flicker(float t, float v) {
	return 0.75 + 0.25 * env_noise(vec2(t * 6.0, v * 31.0)) + 0.12 * sin(t * 17.0 + v * 9.0);
}

// The backdrop: the haze, slow mist, a light low down, motes drifting up.
vec3 machinery_backdrop(vec2 p, vec2 uv, float t, vec3 haze_col) {
	vec3 c = haze_col;
	float n = env_fbm(vec2(p.x * 1.1 + t * 0.015, p.y * 2.2) + vec2(seed, 3.0), 3);
	c = mix(c, c * 1.3 + light_color.rgb * 0.035, smoothstep(0.42, 0.85, n) * (0.35 + 0.35 * blur));
	c += light_color.rgb * 0.05 * smoothstep(0.45, 0.0, 1.0 - uv.y);
	vec2 g = (p + vec2(sin(p.y * 3.0 + t * 0.2) * 0.02, t * 0.02)) * 16.0;
	vec2 id = floor(g);
	float h = env_hash(id + vec2(seed, 7.0));
	if (h > 0.93) {
		vec2 d = fract(g) - 0.5 + (env_hash2(id + 3.0) - 0.5) * 0.5;
		c += light_color.rgb * smoothstep(0.16, 0.0, length(d)) * 0.22 * (0.5 + 0.5 * sin(t * 2.0 + h * 40.0));
	}
	return c;
}
