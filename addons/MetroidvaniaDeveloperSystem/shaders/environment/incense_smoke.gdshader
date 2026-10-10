shader_type canvas_item;
// Incense smoke (MDSIncenseSmoke): ribbons of smoke curling up from censers along the rectangle's
// bottom edge, spreading and fading as they rise, an ember glowing at each censer and flecks of
// golden ash glinting in the smoke.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color : source_color = vec4(0.86, 0.82, 0.93, 0.6);
/// The censers' embers and the ash in the smoke.
uniform vec4 ember_color : source_color = vec4(1.0, 0.74, 0.36, 1.0);
/// How many censers, spread along the bottom edge.
uniform int plumes = 1;
uniform float rise_speed = 40.0;
/// How wide the smoke fans out as it rises.
uniform float spread : hint_range(0.0, 1.0) = 0.6;
/// How much the ribbons curl.
uniform float curl : hint_range(0.0, 2.0) = 1.0;
uniform float thickness : hint_range(0.0, 1.0) = 0.6;
uniform float flecks : hint_range(0.0, 1.0) = 0.4;
uniform float sway = 1.0;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	float t = TIME;
	float hgt = max(rect_size.y, 1.0);
	float yu = (hgt - px.y) / hgt;
	int n = clamp(plumes, 1, 6);
	float smoke = 0.0;
	float region = 0.0;
	float ember = 0.0;
	for (int k = 0; k < 6; k++) {
		if (k >= n) {
			break;
		}
		float fk = float(k);
		float sx = rect_size.x * (fk + 0.5) / float(n);
		float mid = sx + (sin(t * 0.35 + yu * 4.0 + fk * 2.0) * 18.0 + (env_noise(vec2(yu * 3.0 - t * 0.2, fk * 7.0 + seed)) - 0.5) * 40.0) * sway * yu;
		float width = mix(4.0, rect_size.x * 0.5 * spread / float(n) + 6.0, pow(clamp(yu, 0.0, 1.0), 1.2));
		float dx = (px.x - mid) / max(width, 1.0);
		vec2 q = vec2(dx * 1.4 + fk * 13.0, px.y / 60.0 + t * rise_speed / 60.0);
		vec2 warp = vec2(env_fbm(q * 0.8 + vec2(fk * 3.1, seed), 3), env_fbm(q * 0.8 + vec2(5.2, fk + seed), 3)) - 0.5;
		float v = env_fbm(q + warp * 2.0 * curl, 4);
		float ribbon = 1.0 - abs(v - 0.5) * 2.0;
		ribbon = pow(clamp(ribbon, 0.0, 1.0), mix(7.0, 2.0, clamp(yu, 0.0, 1.0)));
		float envelope = exp(-dx * dx * 2.0) * smoothstep(0.0, 0.04, yu) * (1.0 - smoothstep(0.6, 1.0, yu));
		smoke = max(smoke, ribbon * envelope);
		region = max(region, exp(-dx * dx * 0.8) * (1.0 - smoothstep(0.5, 1.0, yu)));
		ember = max(ember, exp(-length(vec2(px.x - sx, (hgt - px.y) * 1.6)) / 9.0) * (0.75 + 0.25 * sin(t * 3.0 + fk)));
	}
	// Golden ash rising in the smoke.
	vec2 fq = vec2(px.x, px.y + t * rise_speed * 0.9) / 22.0;
	vec2 fid = floor(fq);
	vec2 fr = env_hash2(fid + seed * 2.0);
	float fleck = 0.0;
	if (env_hash(fid + seed) < flecks * 0.35) {
		float d = length((fract(fq) - 0.5 - (fr - 0.5) * 0.6) * 22.0);
		fleck = (1.0 - smoothstep(0.4, 1.4, d)) * (0.5 + 0.5 * sin(t * 4.0 + fr.x * 30.0)) * region;
	}
	float a = clamp(smoke * thickness * 1.6, 0.0, 1.0) * color.a;
	vec3 c = mix(color.rgb, ember_color.rgb, clamp(ember + fleck, 0.0, 1.0));
	a = max(a, max(ember * 0.9, fleck));
	// Soft at the sides and the top; the censers sit on the bottom edge.
	float fade = clamp(min(min(px.x, rect_size.x - px.x), px.y) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(c, a * intensity * fade);
}
