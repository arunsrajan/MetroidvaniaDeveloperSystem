// Shared by the MDS environment shaders (see MDSEnvironmentEffect, which sets these uniforms).
// Each effect draws a rectangle of its own: `px` is the fragment's distance in pixels from the
// rectangle's top-left corner, so patterns keep their size whatever the rectangle's size.

/// The rectangle's top-left corner, in the node's own coordinates (px).
uniform vec2 rect_origin = vec2(0.0);
/// The rectangle's size (px).
uniform vec2 rect_size = vec2(1152.0, 648.0);
/// How strong the effect is now (its intensity times its fade in or out).
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
/// Varies the pattern, so two effects side by side don't move in step.
uniform float seed = 0.0;
/// The effect fades out over this many px at the rectangle's edges, so it never shows a hard border.
uniform float edge_fade = 32.0;

varying vec2 px;

// Hash without sine (Dave Hoskins, MIT): stable on every GPU for the coordinates used here.
float env_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 env_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Smooth value noise in 0..1.
float env_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = env_hash(i);
	float b = env_hash(i + vec2(1.0, 0.0));
	float c = env_hash(i + vec2(0.0, 1.0));
	float d = env_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal noise: `octaves` layers of env_noise, each twice as fine and half as strong.
float env_fbm(vec2 p, int octaves) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		total += amp * env_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return total;
}

// Cellular noise: the distances to the nearest and second-nearest cell centres.
vec2 env_voronoi(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + env_hash2(n + g) - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(sqrt(f1), sqrt(f2));
}

// 0 on the rectangle's border, 1 deeper inside than edge_fade.
float env_edge(vec2 p) {
	vec2 d = min(p, rect_size - p);
	return clamp(min(d.x, d.y) / max(edge_fade, 0.001), 0.0, 1.0);
}

vec2 env_rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Straight streaks running down a falling sheet (waterfalls, lava falls). The sheet is cut into
// lanes `lane` px wide; each lane's streaks slide down at a pace of its own (`speed` px/s, give
// or take a fifth) and are about `len` px long. Nothing changes across a lane but its soft
// edges, so every streak is a straight vertical line: the flow never bends or curves. 0..1.
float env_fall_streaks(float x, float y, float t, float speed, float lane, float len, float s) {
	float lx = x / max(lane, 1.0);
	float id = floor(lx);
	float f = fract(lx);
	float pace = speed * (0.8 + 0.4 * env_hash(vec2(id, s)));
	float span = len * (0.6 + 0.8 * env_hash(vec2(id, s + 3.0)));
	float n = env_noise(vec2(id * 7.31 + s, (y - t * pace) / span));
	float edge = smoothstep(0.0, 0.4, f) * smoothstep(1.0, 0.6, f);
	return smoothstep(0.5, 0.85, n) * edge;
}

// A shade that changes from lane to lane across a falling sheet, about `lane` px wide, and never
// along it: straight vertical bands (0..1).
float env_fall_lanes(float x, float lane, float s) {
	return env_noise(vec2(x / max(lane, 1.0), s));
}
