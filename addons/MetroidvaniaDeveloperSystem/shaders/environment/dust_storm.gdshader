shader_type canvas_item;
// A dust storm blowing sideways: banks of dust billowing past in gusts, long wisps racing
// along them, dark grit and pale motes driven by the wind. MDSDustStorm draws it twice, a
// far plane behind the terrain (depth 1) and a near one in front of it (depth 0).

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

/// 1 blows toward the right, -1 toward the left.
uniform float direction = 1.0;
/// How fast the dust travels (px/s).
uniform float speed = 420.0;
/// How thick the banks of dust are.
uniform float density : hint_range(0.0, 1.0) = 0.6;
/// Size of the banks (px).
uniform float scale = 520.0;
uniform vec4 dust_color : source_color = vec4(0.63, 0.63, 0.61, 1.0);
uniform vec4 shade_color : source_color = vec4(0.22, 0.26, 0.30, 1.0);
uniform vec4 grit_color : source_color = vec4(0.06, 0.06, 0.07, 1.0);
uniform vec4 mote_color : source_color = vec4(0.93, 0.94, 0.96, 1.0);
/// Specks driven along by the wind.
uniform float grit : hint_range(0.0, 1.0) = 0.6;
/// How much the wind rises and falls: 0 steady, 1 strong gusts.
uniform float gustiness : hint_range(0.0, 1.0) = 0.5;
/// 0 the near plane, 1 far away: smaller, slower, fainter.
uniform float depth : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;

void vertex() {
	px = VERTEX - rect_origin;
}

// Gust fronts travel with the wind: 1 steady, up to ~1.5 in a gust.
float gust(float x, float t) {
	float g = env_noise(vec2(x / 900.0 - direction * t * speed / 1000.0, t * 0.15 + seed));
	return mix(1.0, 0.45 + 1.1 * g, gustiness);
}

// One speck per cell, for the cells `amount` of them hold, carried along at `spd` and
// smeared along the wind by `stretch`.
float specks(vec2 p, float cell, float spd, float amount, float size, float stretch, float t, float salt) {
	vec2 q = p;
	q.x -= direction * spd * t;
	q.y += sin(q.x * 0.004 + salt) * 30.0;
	vec2 g = q / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = env_hash(id + vec2(salt, seed * 13.0));
	if (h >= amount) {
		return 0.0;
	}
	vec2 r = env_hash2(id + vec2(salt * 2.0, seed));
	vec2 d = (f - (0.2 + 0.6 * r)) * cell;
	d.x /= stretch;
	float s = size * (0.6 + 0.8 * h / max(amount, 0.0001));
	return smoothstep(s, s * 0.3, length(d));
}

void fragment() {
	float t = TIME;
	float near = 1.0 - depth;
	float sc = scale * mix(1.0, 0.6, depth);
	float spd = speed * mix(1.0, 0.45, depth);
	vec2 p = px + vec2(seed * 311.0, seed * 127.0);
	float gusts = gust(p.x, t);

	// Banks of dust: warped noise carried by the wind and stretched along it.
	vec2 q = vec2((p.x - direction * spd * t) / (sc * 1.7), p.y / sc);
	vec2 warp = vec2(env_fbm(q * 0.9 + vec2(0.0, t * 0.06), 4), env_fbm(q * 0.9 + vec2(5.2, -t * 0.05), 4));
	float bank = env_fbm(q + warp * 1.4 + vec2(-direction * t * 0.12, 0.0), 5);
	float detail = env_fbm(q * 2.6 + warp * 0.8 + vec2(-direction * t * 0.5, 3.1), 4);
	float body = bank * 0.75 + detail * 0.35;
	float lo = mix(0.62, 0.30, density);
	float cloud = smoothstep(lo, lo + 0.35, body) * gusts;
	// Lit from above: the tops of the billows are paler.
	vec3 col = mix(shade_color.rgb, dust_color.rgb, smoothstep(0.35, 0.75, detail));
	// A thin veil between the banks, thicker in gusts.
	float veil = (0.18 + 0.25 * density) * gusts * smoothstep(0.2, 0.6, bank);
	float alpha = clamp(max(cloud, veil), 0.0, 1.0) * opacity * mix(1.0, 0.7, depth);

	// Long thin wisps racing ahead of the banks.
	float streak = env_noise(vec2((p.x - direction * spd * 2.2 * t) / 260.0, p.y / 7.0 + seed));
	streak = smoothstep(0.72, 0.95, streak) * 0.35 * gusts;
	col = mix(col, dust_color.rgb * 1.08, streak);
	alpha = max(alpha, streak * opacity);

	// Grit (dark) and motes (pale), smeared more in gusts.
	float g1 = specks(p, 46.0, spd * 1.9, grit * 0.55, 2.2 * near + 1.0, 1.0 + 4.0 * gusts * near, t, 1.7);
	float g2 = specks(p, 31.0, spd * 1.4, grit * 0.45, 1.4 * near + 0.8, 1.0 + 2.5 * gusts, t, 9.3);
	float m1 = specks(p, 83.0, spd * 1.6, grit * 0.35, 1.8 * near + 0.7, 1.0 + 3.0 * gusts, t, 4.4);
	float grit_a = max(g1, g2) * mix(0.9, 0.4, depth);
	col = mix(col, grit_color.rgb, grit_a);
	alpha = max(alpha, grit_a);
	float mote_a = m1 * 0.8 * mix(1.0, 0.5, depth);
	col = mix(col, mote_color.rgb, mote_a);
	alpha = max(alpha, mote_a);

	COLOR = vec4(col, alpha * intensity * env_edge(px));
}
