shader_type canvas_item;
// A body of water: a rolling surface with a bright line along it, what is behind showing
// through, bent and tinted deeper toward the bottom, rippling caustic light near the
// surface and bubbles rising. The rectangle reaches `surface_y` px above the water's rest
// line, so the waves can rise.

render_mode blend_mix;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.25, 0.62, 0.72, 0.45);
uniform vec4 deep_color : source_color = vec4(0.04, 0.16, 0.30, 0.85);
uniform vec4 surface_color : source_color = vec4(0.85, 0.97, 1.0, 0.9);
uniform vec4 caustic_color : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float surface_y = 10.0;
uniform float wave_height = 4.0;
uniform float wave_speed = 1.0;
uniform float refraction : hint_range(0.0, 1.0) = 0.5;
uniform float caustics : hint_range(0.0, 1.0) = 0.6;
uniform float bubbles : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	float t = TIME * wave_speed;
	float sx = px.x + seed * 91.0;
	float wave = sin(sx * 0.022 + t * 1.7) * 0.55 + sin(sx * 0.053 - t * 2.3) * 0.3;
	wave += (env_noise(vec2(sx * 0.03, t * 0.7)) - 0.5) * 0.6;
	float surface = surface_y + wave * wave_height;
	float below = px.y - surface;
	vec3 col = vec3(0.0);
	float alpha = 0.0;
	if (below >= 0.0) {
		float deep = clamp(below / max(rect_size.y - surface_y, 1.0), 0.0, 1.0);
		vec2 q = vec2(sx, px.y) / 60.0;
		vec2 bend = vec2(env_noise(q + vec2(t * 0.3, 0.0)) - 0.5, env_noise(q * 1.2 + vec2(0.0, t * 0.25)) - 0.5);
		vec3 behind = texture(screen_tex, SCREEN_UV + bend * refraction * SCREEN_PIXEL_SIZE * 10.0).rgb;
		vec4 tint = mix(shallow_color, deep_color, deep);
		col = mix(behind, tint.rgb, tint.a);
		// Caustics: a thin, rippling net of light just under the surface.
		vec2 cv = env_voronoi(vec2(sx, px.y) / 58.0 + bend * 1.2 + vec2(t * 0.25, t * 0.17));
		float c = pow(smoothstep(0.12, 0.0, cv.y - cv.x), 2.0);
		col += caustic_color.rgb * c * caustics * exp(-below / 70.0) * 0.4;
		// Bubbles rising.
		if (bubbles > 0.0) {
			vec2 bp = vec2(sx + sin(px.y * 0.06 + TIME * 2.0) * 3.0, px.y + TIME * 45.0);
			vec2 g = bp / 30.0;
			vec2 id = floor(g);
			float h = env_hash(id + vec2(seed, 5.0));
			if (h < bubbles * 0.3) {
				vec2 d = (fract(g) - (0.3 + 0.4 * env_hash2(id))) * 30.0;
				float r = 1.5 + 2.0 * fract(h * 9.0);
				float ring = smoothstep(1.0, 0.0, abs(length(d) - r));
				col = mix(col, surface_color.rgb, ring * 0.6 * (1.0 - deep * 0.5));
			}
		}
		// The bright line along the surface.
		col = mix(col, surface_color.rgb, smoothstep(3.0, 0.0, below) * surface_color.a);
		alpha = 1.0;
	}
	COLOR = vec4(col, alpha * intensity);
}
