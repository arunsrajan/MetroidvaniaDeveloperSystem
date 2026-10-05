// Example terrain skin for freeform styles (IDPFreeformStyle.fill_material / edge_material).
//
// One shader, two passes:
//   * the fill pass (edge_pass off) paints cut-stone blocks with bevelled edges and dark joints,
//     lit from light_dir, in world space so neighbouring shapes join without a seam;
//   * the edge pass (edge_pass on) paints the band IDPEdgeBand builds along the outline: grass
//     standing up out of floors, a lit bevel on walls, shadow and drips under ceilings.
//     UV.x runs along the outline (px), UV.y across it (0 at the surface, 1 at the band's inner
//     edge, negative outside), COLOR.r says which way the surface faces (0 up .. 1 down).
// Copy it and change the colors, or write your own skin with the same inputs.
shader_type canvas_item;

uniform bool edge_pass = false;
uniform vec4 stone_dark : source_color = vec4(0.30, 0.28, 0.24, 1.0);
uniform vec4 stone_light : source_color = vec4(0.62, 0.58, 0.48, 1.0);
uniform vec4 joint_color : source_color = vec4(0.10, 0.09, 0.07, 1.0);
uniform vec2 block_size = vec2(96.0, 44.0);
uniform vec2 light_dir = vec2(-0.55, -0.85);
uniform float gloss : hint_range(0.0, 1.0) = 0.35;
uniform vec4 grass_dark : source_color = vec4(0.10, 0.25, 0.08, 1.0);
uniform vec4 grass_light : source_color = vec4(0.45, 0.72, 0.25, 1.0);
uniform float grass_height = 24.0;
uniform vec4 shadow_color : source_color = vec4(0.03, 0.03, 0.02, 1.0);
uniform vec4 bevel_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);

varying vec2 world;
varying vec2 facing;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	facing = COLOR.rg;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s / 0.9375;
}

// x: distance (px) to the nearest joint, y: the block's hash.
vec2 blocks(vec2 p) {
	float row = floor(p.y / block_size.y);
	float off = fract(row * 0.5) * block_size.x + hash12(vec2(row, 7.0)) * block_size.x * 0.3;
	float x = p.x + off;
	float col = floor(x / block_size.x);
	vec2 l = vec2(x - col * block_size.x, p.y - row * block_size.y);
	float d = min(min(l.x, block_size.x - l.x), min(l.y, block_size.y - l.y));
	return vec2(d, hash12(vec2(col, row)));
}

float height(vec2 p) {
	vec2 wob = vec2(fbm(p / 70.0), fbm(p / 70.0 + 5.0)) * 5.0;
	vec2 b = blocks(p + wob);
	return smoothstep(1.0, 7.0, b.x) * (0.75 + 0.25 * fbm(p / 18.0)) + b.y * 0.08;
}

vec4 stone(vec2 p) {
	float h = height(p);
	float hx = height(p + vec2(1.5, 0.0)) - height(p - vec2(1.5, 0.0));
	float hy = height(p + vec2(0.0, 1.5)) - height(p - vec2(0.0, 1.5));
	vec3 n = normalize(vec3(-hx * 3.0, -hy * 3.0, 1.0));
	vec3 l = normalize(vec3(light_dir, 0.8));
	float diffuse = clamp(dot(n, l), 0.0, 1.0);
	float spec = pow(clamp(dot(reflect(-l, n), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 24.0) * gloss;
	vec2 b = blocks(p + vec2(fbm(p / 70.0), fbm(p / 70.0 + 5.0)) * 5.0);
	vec3 c = mix(stone_dark.rgb, stone_light.rgb, b.y * 0.7 + fbm(p / 30.0) * 0.3);
	c = mix(joint_color.rgb, c, smoothstep(0.0, 2.5, b.x));
	return vec4(c * (0.45 + 0.75 * diffuse) + spec, 1.0);
}

void fragment() {
	if (!edge_pass) {
		COLOR = stone(world) * vec4(1.0, 1.0, 1.0, COLOR.a);
	} else {
		float v = UV.y;
		float down = facing.r;
		float up = 1.0 - down;
		vec4 c = vec4(0.0);
		if (up > 0.7) {
			// Grass: blades standing out of the floor, a darker turf just under the surface.
			float blade = fbm(vec2(UV.x / 6.0, 0.0)) * 0.6 + vnoise(vec2(UV.x / 2.5, 3.0)) * 0.4;
			float tip = -blade * grass_height / 34.0;
			if (v < 0.0) {
				float a = step(tip, v) * smoothstep(0.0, 0.25, -tip);
				c = vec4(mix(grass_dark.rgb, grass_light.rgb, clamp(1.0 - v / tip, 0.0, 1.0)), a);
			} else {
				float turf = 1.0 - smoothstep(0.15, 0.45 + fbm(vec2(UV.x / 20.0, 1.0)) * 0.3, v);
				c = vec4(grass_dark.rgb, turf);
			}
		} else if (down > 0.7) {
			// Under a ceiling: shadow fading into the rock, drips hanging below.
			if (v >= 0.0) {
				c = vec4(shadow_color.rgb, (1.0 - smoothstep(0.0, 1.0, v)) * 0.75);
			} else {
				float drip = smoothstep(0.82, 0.95, vnoise(vec2(UV.x / 7.0, 9.0)));
				float len = drip * (0.3 + vnoise(vec2(UV.x / 3.0, 2.0)));
				c = vec4(shadow_color.rgb, step(-len, v) * drip * 0.9);
			}
		} else {
			// Walls: a bright bevel on the side facing the light, shade on the other.
			float lit = clamp(dot(vec2(facing.g * 2.0 - 1.0, down * 2.0 - 1.0), -normalize(light_dir)), 0.0, 1.0);
			float rim = v >= 0.0 ? (1.0 - smoothstep(0.0, 0.25, v)) : 0.0;
			c = mix(vec4(shadow_color.rgb, rim * 0.5), vec4(bevel_color.rgb, rim * 0.35), lit);
		}
		COLOR = c;
	}
}
