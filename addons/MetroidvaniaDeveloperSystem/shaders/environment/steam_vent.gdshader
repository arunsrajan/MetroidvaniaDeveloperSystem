shader_type canvas_item;
// A jet of hot steam forced out of a vent: white-hot at the mouth, cooling through salmon to
// a dark red crest as it climbs, swaying and billowing wider the higher it gets, with glitter
// thrown up along it. The rectangle's bottom edge is the vent (MDSSteamVent turns the node to
// point it another way). Between eruptions thin wisps curl out of the vent, and the mouth
// glows as a warning before it blasts.

render_mode blend_mix, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 vent_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.47, 0.36, 1.0);
uniform vec4 crest_color : source_color = vec4(0.64, 0.12, 0.11, 1.0);
uniform vec4 sparkle_color : source_color = vec4(1.0, 0.74, 0.84, 1.0);
/// How fast the billows climb.
uniform float rise_speed : hint_range(0.2, 6.0) = 1.6;
/// How far up the rectangle the jet has reached (0..1).
uniform float progress : hint_range(0.0, 1.0) = 1.0;
/// Takes the whole jet away as it dies.
uniform float fade : hint_range(0.0, 1.0) = 1.0;
/// Thin wisps out of the vent between eruptions.
uniform float wisps : hint_range(0.0, 1.0) = 0.0;
/// The vent's warning glow.
uniform float glow : hint_range(0.0, 1.0) = 0.0;
/// Glitter thrown up with the jet.
uniform float sparkles : hint_range(0.0, 1.0) = 0.6;
/// The jet's length over the 540 px its billows are sized for.
uniform float stretch = 1.0;

void vertex() {
	px = VERTEX - rect_origin;
}

float twinkle(vec2 p, float cell, float salt) {
	vec2 g = p / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float h = env_hash(id + vec2(salt, seed));
	if (h > 0.35) {
		return 0.0;
	}
	vec2 c = 0.2 + 0.6 * env_hash2(id + vec2(seed, salt));
	vec2 d = (f - c) * cell;
	float blink = 0.5 + 0.5 * sin(TIME * (6.0 + 9.0 * h) + h * 40.0);
	// A small four-pointed star.
	float star = max(smoothstep(4.0, 0.0, abs(d.x)) * smoothstep(1.2, 0.0, abs(d.y)),
			smoothstep(4.0, 0.0, abs(d.y)) * smoothstep(1.2, 0.0, abs(d.x)));
	star = max(star, smoothstep(1.8, 0.0, length(d)));
	return star * blink;
}

void fragment() {
	vec2 uv = px / rect_size;
	float h = 1.0 - uv.y; // 0 at the vent, 1 at the top
	float x = uv.x - 0.5;
	float t = TIME * rise_speed + seed * 17.0;
	float hs = h * stretch;
	vec3 col = vec3(0.0);
	float alpha = 0.0;

	if (h <= progress && fade > 0.0) {
		// The column sways, more the higher it has climbed.
		float sway = (env_fbm(vec2(hs * 2.2 - t * 0.5, seed * 3.1), 4) - 0.5) * 0.36 * h;
		float xs = x - sway;
		// Tight at the vent, billowing wider as it rises.
		float w = mix(0.085, 0.31, pow(h, 0.7));
		float billow = env_fbm(vec2(xs * 5.0 + seed * 9.0, hs * 4.5 - t * 1.8), 4);
		float puffs = env_fbm(vec2(xs * 9.0 - seed * 4.0, hs * 9.0 - t * 2.6), 4);
		float edge = w * (0.7 + 0.6 * billow);
		float d = abs(xs) / max(edge, 0.001);
		float body = smoothstep(1.0, 0.38, d);
		// A ragged crest: puffs break off the top.
		float crest = smoothstep(progress, progress - 0.22 - 0.18 * puffs, h);
		// Higher up the steam thins into separate puffs.
		float thin = mix(1.0, smoothstep(0.33, 0.63, puffs), smoothstep(0.35, 1.0, h));
		float dens = body * crest * thin * (0.6 + 0.6 * puffs);
		float heat = clamp((1.0 - h) * 1.12 - d * 0.45 + (puffs - 0.5) * 0.3, 0.0, 1.0);
		col = mix(crest_color.rgb, hot_color.rgb, smoothstep(0.0, 0.55, heat));
		col = mix(col, vent_color.rgb, smoothstep(0.55, 0.95, heat));
		alpha = clamp(dens * 1.5, 0.0, 1.0) * fade;
		// A flare right at the mouth.
		float flare = smoothstep(0.08, 0.0, h) * smoothstep(0.24, 0.0, abs(x)) * step(0.01, progress);
		col = mix(col, vent_color.rgb, flare * (1.0 - alpha));
		alpha = max(alpha, flare * fade);
		// Glitter blown up along the jet, a little wider than it.
		if (sparkles > 0.0 && d < 1.7) {
			vec2 sp = vec2(xs * rect_size.x, h * rect_size.y - TIME * 300.0 * rise_speed / 1.6);
			float s = max(twinkle(sp, 26.0, 1.3), twinkle(sp + vec2(13.0, 7.0), 41.0, 5.9) * 0.8);
			s *= sparkles * crest * fade * smoothstep(1.7, 0.6, d);
			vec3 sc = mix(sparkle_color.rgb, vec3(1.0), step(0.5, fract(sp.y * 0.013)));
			col = mix(col, sc, s);
			alpha = max(alpha, s);
		}
	}

	// Idle wisps: thin curls rising a little way out of the vent.
	if (wisps > 0.0) {
		float wh = 0.24;
		float wx = x - (env_noise(vec2(h * 6.0 - TIME * 0.8, seed)) - 0.5) * 0.14 * h / wh;
		float curl = env_fbm(vec2(wx * 16.0, h * 8.0 - TIME * 1.4 + seed), 3);
		float thread = smoothstep(0.05 + 0.04 * h / wh, 0.0, abs(wx)) * smoothstep(wh, 0.0, h);
		float wa = thread * smoothstep(0.35, 0.7, curl) * wisps * 0.7;
		col = mix(col, mix(hot_color.rgb, vent_color.rgb, 0.5), wa * (1.0 - alpha));
		alpha = max(alpha, wa);
	}

	// The warning glow over the vent.
	if (glow > 0.0) {
		float g = smoothstep(0.32, 0.0, length(vec2(x * 1.6, h * 2.2))) * glow;
		col = mix(col, hot_color.rgb, g * (1.0 - alpha));
		alpha = max(alpha, g * 0.85);
	}

	COLOR = vec4(col, alpha * intensity);
}
