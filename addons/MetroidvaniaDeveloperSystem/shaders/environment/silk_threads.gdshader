shader_type canvas_item;
// Silk threads (MDSSilkThreads): strands of silk drifting and turning slowly in the air, light
// running along them, and threads hanging from the top edge, swaying, a bead of silk at each end.

render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.96, 0.93, 1.0, 0.85);
/// The light running along them.
uniform vec4 glint_color : source_color = vec4(1.0, 0.82, 0.92, 1.0);
/// How many strands drift in the air.
uniform float density : hint_range(0.0, 1.0) = 0.6;
/// Average distance between drifting strands (px).
uniform float spacing = 150.0;
uniform float strand_length = 120.0;
/// How many threads hang from the top edge.
uniform float hanging : hint_range(0.0, 1.0) = 0.5;
uniform float hang_spacing = 70.0;
/// How far they hang, a share of the height.
uniform float hang_length : hint_range(0.05, 1.0) = 0.45;
uniform float sway = 1.0;
uniform float speed = 1.0;
uniform float glow : hint_range(0.0, 1.0) = 0.5;
uniform float thickness = 1.0;

void vertex() {
	px = VERTEX - rect_origin;
}

// A strand floating in cell `id` (`p` relative to the cell's corner): its light, and in `gl` how
// much of it is the glint running along it.
float strand(vec2 p, vec2 id, float t, out float gl) {
	gl = 0.0;
	float h = env_hash(id + seed * 1.3);
	if (h > density) {
		return 0.0;
	}
	vec2 r = env_hash2(id + seed);
	vec2 c = (vec2(0.5) + (r - 0.5) * 0.5) * spacing + vec2(sin(t * 0.21 + r.x * 6.283), cos(t * 0.17 + r.y * 6.283)) * spacing * 0.12;
	float ang = r.x * 6.283 + sin(t * 0.1 + h * 20.0) * 0.6;
	vec2 q = env_rotate(p - c, -ang);
	float len = strand_length * (0.6 + 0.8 * r.y);
	float along = q.x / (len * 0.5);
	if (abs(along) > 1.05) {
		return 0.0;
	}
	float k = 6.283 / len * (1.0 + r.x);
	float phase = t * (0.8 + r.y) + h * 30.0;
	float amp = (5.0 + 9.0 * r.x) * sway;
	float y = amp * sin(q.x * k + phase);
	float slope = amp * k * cos(q.x * k + phase);
	float d = abs(q.y - y) / sqrt(1.0 + slope * slope);
	float w = 0.6 * thickness;
	float line = (1.0 - smoothstep(w, w + 1.0, d)) + exp(-d / (2.0 + 4.0 * glow)) * glow * 0.45;
	float ends = 1.0 - smoothstep(0.75, 1.05, abs(along));
	float g = fract(t * 0.12 * (0.5 + r.y) + h);
	gl = exp(-pow((along * 0.5 + 0.5 - g) * 6.0, 2.0));
	return line * ends * (0.35 + 0.65 * gl);
}

// The threads hanging from the top edge, near `p`.
float hang(vec2 p, float t, out float gl) {
	gl = 0.0;
	float total = 0.0;
	float col = floor(p.x / hang_spacing);
	for (int i = -1; i <= 1; i++) {
		float id = col + float(i);
		float h = env_hash(vec2(id, seed + 7.0));
		if (h > hanging) {
			continue;
		}
		vec2 r = env_hash2(vec2(id, seed + 3.0));
		float len = rect_size.y * hang_length * (0.4 + 0.6 * r.x);
		float x0 = (id + 0.2 + 0.6 * r.y) * hang_spacing;
		float wave = t * (0.6 + 0.4 * r.x) + h * 20.0;
		float yy = clamp(p.y / len, 0.0, 1.0);
		float x = x0 + sin(wave + p.y * 0.01) * 10.0 * sway * yy * yy;
		float w = 0.5 * thickness;
		float d = abs(p.x - x);
		float line = p.y < len ? (1.0 - smoothstep(w, w + 1.0, d)) * (0.45 + 0.55 * yy) : 0.0;
		float x_end = x0 + sin(wave + len * 0.01) * 10.0 * sway;
		float bd = length(vec2(p.x - x_end, p.y - len));
		float bead = (1.0 - smoothstep(1.4 * thickness, 2.4 * thickness, bd)) + exp(-bd / (3.0 + 5.0 * glow)) * glow * 0.6;
		float g = fract(t * 0.18 * (0.6 + r.y) + h);
		float glint = exp(-pow((yy - g) * 8.0, 2.0));
		float a = line * (0.4 + 0.6 * glint) + bead;
		total += a;
		gl += a * max(glint, bead > 0.5 ? 1.0 : 0.0);
	}
	gl = total > 0.0 ? gl / total : 0.0;
	return total;
}

void fragment() {
	float t = TIME * speed;
	vec2 id = floor(px / spacing);
	float total = 0.0;
	float glint = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cid = id + vec2(float(i), float(j));
			float g;
			float s = strand(px - cid * spacing, cid, t, g);
			total += s;
			glint += s * g;
		}
	}
	float hg;
	float hs = hang(px, t, hg);
	total += hs;
	glint += hs * hg;
	glint = total > 0.0 ? glint / total : 0.0;
	vec3 c = mix(color.rgb, glint_color.rgb, clamp(glint, 0.0, 1.0));
	COLOR = vec4(c, clamp(total, 0.0, 1.0) * color.a * intensity * env_edge(px));
}
