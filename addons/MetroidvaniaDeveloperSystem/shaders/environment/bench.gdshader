shader_type canvas_item;
// A bench to rest on (MDSBench), after Hollow Knight: Silksong's: a wrought-iron bench with a
// wooden seat, a red cushion, a carved back with a medallion, scrolled armrests and a lantern
// hanging from a hook. The lantern flickers and lights the bench, motes drift up in its light.
// When the player is at it (`near`), a warm rim shows; resting on it (`rest`), it glows, threads
// of light rise from the cushion; a ring of light spreads out when the game is saved (`pulse`
// from 0 up to 1).
//
// The bench stands on the bottom middle of the rectangle; `bench_width` px wide. Drawn
// premultiplied: the bench itself covers what is behind, its light adds to it.

render_mode blend_premul_alpha, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 frame_color : source_color = vec4(0.17, 0.15, 0.19, 1.0);
uniform vec4 trim_color : source_color = vec4(0.80, 0.63, 0.36, 1.0);
uniform vec4 seat_color : source_color = vec4(0.42, 0.27, 0.18, 1.0);
uniform vec4 cushion_color : source_color = vec4(0.52, 0.16, 0.22, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.46, 1.0);
uniform float bench_width = 120.0;
uniform bool lamp = true;
/// The player is at the bench (0..1).
uniform float near = 0.0;
/// Resting on it (0..1).
uniform float rest = 0.0;
/// Since the game was last saved here: 0 just saved, 1 over.
uniform float pulse = 1.0;
uniform float motes = 0.6;

void vertex() {
	px = VERTEX - rect_origin;
}

float sd_box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// The top rail's arch over the back: highest in the middle.
float arch_y(float x) {
	float u = clamp(x / 53.0, -1.0, 1.0);
	return -76.0 - 9.0 * (1.0 - u * u);
}

void fragment() {
	float k = max(bench_width / 120.0, 0.05);
	// Bench units: 120 across, the feet at (0, 0), up is negative.
	vec2 b = (px - vec2(rect_size.x * 0.5, rect_size.y)) / k;
	float aa = 1.0 / k;
	float t = TIME;
	vec2 lamp_at = vec2(70.0, -88.0);
	float flicker = 0.82 + 0.18 * env_noise(vec2(t * 7.0, seed)) + 0.06 * sin(t * 23.0 + seed);

	// --- The bench (iron frame, seat, cushion, trim) ---
	float iron = 1e3;
	for (float sx = -1.0; sx <= 1.0; sx += 2.0) {
		iron = min(iron, sd_seg(b, vec2(sx * 52.0, 0.0), vec2(sx * 54.0, -78.0)) - 2.6); // back posts
		iron = min(iron, sd_seg(b, vec2(sx * 45.0, 0.0), vec2(sx * 48.0, -28.0)) - 3.0); // front legs
		iron = min(iron, sd_box(b - vec2(sx * 45.0, -1.4), vec2(6.0, 1.4), 1.0));       // feet
		// Scrolled armrests: an arm from the post, curling down at its end.
		iron = min(iron, sd_seg(b, vec2(sx * 53.0, -42.0), vec2(sx * 61.0, -42.0)) - 1.7);
		iron = min(iron, abs(length(b - vec2(sx * 61.0, -37.0)) - 5.0) - 1.5);
	}
	// The back: a lower rail, the arched top rail, spindles and a medallion.
	iron = min(iron, sd_seg(b, vec2(-53.0, -45.0), vec2(53.0, -45.0)) - 1.8);
	float top = abs(b.y - arch_y(b.x)) - 2.3;
	top = max(top, abs(b.x) - 54.0);
	iron = min(iron, top);
	for (float s = -2.0; s <= 2.0; s += 1.0) {
		if (s == 0.0) {
			continue;
		}
		float x = s * 19.0;
		iron = min(iron, sd_seg(b, vec2(x, -45.0), vec2(x, arch_y(x))) - 1.3);
	}
	float medallion = abs(length(b - vec2(0.0, -61.0)) - 8.5) - 1.6;
	iron = min(iron, medallion);
	// The lantern's post and hook.
	if (lamp) {
		iron = min(iron, sd_seg(b, vec2(54.0, -78.0), vec2(56.0, -106.0)) - 1.8);
		iron = min(iron, sd_seg(b, vec2(56.0, -106.0), vec2(70.0, -106.0)) - 1.5);
		iron = min(iron, sd_seg(b, vec2(70.0, -106.0), vec2(70.0, -98.0)) - 0.8);
	}
	float seat = sd_box(b - vec2(0.0, -29.5), vec2(58.0, 3.6), 1.5);
	float cushion = sd_box(b - vec2(0.0, -36.0), vec2(51.0, 3.8), 3.2);
	float trim = 1e3;
	for (float sx = -1.0; sx <= 1.0; sx += 2.0) {
		trim = min(trim, length(b - vec2(sx * 54.0, -81.0)) - 3.2); // finials
		trim = min(trim, length(b - vec2(sx * 61.0, -37.0)) - 1.8); // scroll ends
	}
	trim = min(trim, length(b - vec2(0.0, -61.0)) - 3.0); // the medallion's stone
	float lantern = 1e3;
	float glass = 1e3;
	if (lamp) {
		lantern = sd_box(b - vec2(70.0, -89.0), vec2(5.2, 7.4), 2.0);
		lantern = min(lantern, sd_box(b - vec2(70.0, -97.5), vec2(3.6, 1.4), 0.8));
		glass = sd_box(b - vec2(70.0, -88.5), vec2(3.4, 5.4), 1.4);
	}

	// The lantern's light on the bench, and a sheen down the iron.
	float lit = lamp ? exp(-pow(length(b - lamp_at) / 70.0, 2.0)) * flicker * (0.55 + 0.45 * rest) : 0.0;
	float rim = near * 0.6 + rest * 0.8;
	vec3 col = vec3(0.0);
	float a = 0.0;
	float m;
	// Back to front: iron, seat, cushion, trim, lantern.
	m = clamp(0.5 - iron / aa, 0.0, 1.0);
	vec3 iron_col = frame_color.rgb * (0.9 + 0.25 * smoothstep(0.0, -80.0, b.y)) + glow_color.rgb * lit * 0.45;
	iron_col += glow_color.rgb * rim * 0.35 * smoothstep(-2.0 * aa, 0.0, iron);
	col = mix(col, iron_col, m);
	a = max(a, m);
	m = clamp(0.5 - seat / aa, 0.0, 1.0);
	vec3 wood = seat_color.rgb * (0.85 + 0.25 * env_noise(vec2(b.x * 0.35, floor(b.y) * 3.0))) + glow_color.rgb * lit * 0.4;
	col = mix(col, wood, m);
	a = max(a, m);
	m = clamp(0.5 - cushion / aa, 0.0, 1.0);
	// A plump cushion: lighter along its top, buttoned every so often.
	float puff = smoothstep(-39.5, -33.0, b.y);
	vec3 cush = cushion_color.rgb * mix(1.25, 0.75, puff) + glow_color.rgb * lit * 0.35;
	float button = 1.0 - smoothstep(0.6, 1.4, length(vec2(mod(b.x + 12.5, 25.0) - 12.5, b.y + 36.0)));
	cush = mix(cush, cushion_color.rgb * 0.5, button * 0.8);
	cush += glow_color.rgb * rest * 0.25;
	col = mix(col, cush, m);
	a = max(a, m);
	m = clamp(0.5 - trim / aa, 0.0, 1.0);
	col = mix(col, trim_color.rgb * (1.0 + lit * 0.6 + rest * 0.4), m);
	a = max(a, m);
	m = clamp(0.5 - lantern / aa, 0.0, 1.0);
	col = mix(col, frame_color.rgb * 1.2 + trim_color.rgb * 0.25, m);
	a = max(a, m);
	m = clamp(0.5 - glass / aa, 0.0, 1.0);
	col = mix(col, mix(glow_color.rgb, vec3(1.0, 0.98, 0.9), 0.45) * (0.75 + 0.35 * flicker), m);
	a = max(a, m);

	// --- Its light (added) ---
	vec3 light = vec3(0.0);
	// The lantern's halo.
	if (lamp) {
		// Falling to nothing well inside the rectangle, so its edges never show.
		float dl = length(b - lamp_at);
		float halo = exp(-pow(dl / 12.0, 2.0)) * 0.8 + exp(-pow(dl / 42.0, 2.0)) * 0.3;
		light += glow_color.rgb * halo * flicker * (0.7 + 0.5 * rest);
	}
	// A warm aura around the bench while the player is at it, stronger while resting.
	vec2 mid = (b - vec2(0.0, -44.0)) / vec2(95.0, 62.0);
	light += glow_color.rgb * exp(-dot(mid, mid) * 2.2) * (0.06 + 0.18 * near + 0.45 * rest);
	// Motes drifting up in the light.
	if (motes > 0.0) {
		vec2 g = (b + vec2(sin(b.y * 0.05 + t * 0.7) * 5.0, t * 14.0)) / 22.0;
		vec2 id = floor(g);
		float h = env_hash(id + vec2(seed, 3.0));
		if (h < motes * 0.5) {
			vec2 d = (fract(g) - (0.2 + 0.6 * env_hash2(id + 7.0))) * 22.0;
			float mote = smoothstep(1.6, 0.2, length(d)) * (0.5 + 0.5 * sin(t * 3.0 + h * 40.0));
			float zone = exp(-dot(mid * 0.8, mid * 0.8) * 1.6);
			light += glow_color.rgb * mote * zone * (0.5 + 0.8 * rest);
		}
	}
	// Threads of light rising from the cushion while resting.
	if (rest > 0.01) {
		for (float i = 0.0; i < 7.0; i += 1.0) {
			float x0 = -42.0 + i * 14.0 + (env_hash(vec2(i, seed)) - 0.5) * 6.0;
			float rise = 40.0 + 110.0 * rest * (0.6 + 0.4 * env_hash(vec2(i, seed + 2.0)));
			float x = x0 + sin(b.y * 0.06 + t * 1.6 + i * 1.7) * 3.5;
			float along = smoothstep(-36.0, -40.0, b.y) * smoothstep(-36.0 - rise, -36.0 - rise * 0.4, b.y);
			float thread = exp(-abs(b.x - x) / 0.9) * along;
			float shimmer = 0.6 + 0.4 * sin(b.y * 0.15 - t * 5.0 + i);
			light += mix(glow_color.rgb, vec3(1.0), 0.4) * thread * shimmer * rest * 0.6;
		}
	}
	// A ring of light spreading out when the game is saved.
	if (pulse < 0.999) {
		float r = 20.0 + pulse * 150.0;
		float ring = exp(-abs(length((b - vec2(0.0, -44.0)) * vec2(1.0, 1.35)) - r) / 3.5);
		light += glow_color.rgb * ring * (1.0 - pulse) * (1.0 - pulse) * 1.2;
	}
	light *= env_edge(px);
	COLOR = vec4(col * a + light, a) * intensity;
}
