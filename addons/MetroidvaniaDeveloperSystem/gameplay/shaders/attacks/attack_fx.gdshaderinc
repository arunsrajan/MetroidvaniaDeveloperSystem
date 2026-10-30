// Shared by the attack effects (MDSAttackFX): drawn on a quad centred on the node, facing right
// (the node flips and turns it), played once as progress goes from 0 to 1.

// How far it has played (0: just started, 1: over).
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// The hot middle, and the light round it: the player's or the enemy's colors, or its element's.
uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 glow_color : source_color = vec4(0.42, 0.85, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// Varies the random parts from one play to the next.
uniform float seed = 0.0;
// The quad's size (px), set by MDSAttackFX.
uniform vec2 rect_size = vec2(128.0, 128.0);

varying vec2 fx_uv;

void vertex() {
	fx_uv = VERTEX / rect_size + vec2(0.5);
}

// -1..1 across the quad's height, its width as much wider as the quad is, (0, 0) in its middle;
// y down.
vec2 fx_centered() {
	vec2 p = fx_uv * 2.0 - vec2(1.0);
	p.x *= rect_size.x / max(rect_size.y, 1.0);
	return p;
}

float fx_hash(float p) {
	p = fract(p * 0.1031 + seed * 0.37);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float fx_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031 + seed * 0.13);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float fx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(fx_hash2(i), fx_hash2(i + vec2(1.0, 0.0)), u.x), mix(fx_hash2(i + vec2(0.0, 1.0)), fx_hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fx_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * fx_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float fx_ease_out(float t) {
	t = clamp(t, 0.0, 1.0);
	return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
}

// 1 until [from], then down to 0 at the end.
float fx_fade(float from) {
	return 1.0 - smoothstep(from, 1.0, progress);
}

// Distance from p to the segment a-b.
float fx_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
	return length(pa - ba * h);
}

// A soft line of half-width w at distance d: 1 on it, 0 past w.
float fx_line(float d, float w) {
	return 1.0 - smoothstep(w * 0.35, w, d);
}

// The glowing look: [core] in the hot color, [glow] in the light round it (additive).
vec4 fx_light(float core, float glow, float fade) {
	core = clamp(core, 0.0, 1.0);
	glow = clamp(glow, 0.0, 1.0);
	vec3 c = glow_color.rgb * glow + core_color.rgb * core;
	float a = clamp(max(core, glow * glow_color.a), 0.0, 1.0) * fade;
	return vec4(c * intensity, a);
}
