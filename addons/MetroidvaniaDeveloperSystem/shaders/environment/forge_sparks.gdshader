shader_type canvas_item;
// Forge sparks (MDSForgeSparks): sparks spraying from a source (a forge, a grinding wheel, a cut
// chain) in a fan, arcing down, bouncing off the rectangle's bottom edge and dying out, white-hot
// when thrown and cooling to red. A glow pulses at the source. A steady stream or bursts.

render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

uniform vec4 color_hot : source_color = vec4(1.0, 0.96, 0.76, 1.0);
uniform vec4 color : source_color = vec4(1.0, 0.62, 0.2, 1.0);
uniform vec4 color_cool : source_color = vec4(0.82, 0.18, 0.05, 1.0);
/// Where they come from, a share of the rectangle (0.5, 0: the middle of the top edge).
uniform vec2 source = vec2(0.5, 0.0);
uniform int count = 48;
/// How fast the stream runs.
uniform float rate = 1.0;
/// Which way they spray, in degrees from straight down (positive: to the right).
uniform float angle = 0.0;
/// How wide the fan is, in degrees.
uniform float spread = 70.0;
uniform float speed = 420.0;
uniform float gravity = 900.0;
/// How much of their speed they keep after hitting the bottom edge (0: they land and slide).
uniform float bounce : hint_range(0.0, 1.0) = 0.35;
/// 0 a steady stream, 1 bursts every `burst_interval` seconds.
uniform float burst : hint_range(0.0, 1.0) = 0.0;
uniform float burst_interval = 1.6;
uniform float spark_length = 10.0;
/// How long one lives (s).
uniform float life = 1.3;
uniform float glow : hint_range(0.0, 1.0) = 0.6;

void vertex() {
	px = VERTEX - rect_origin;
}

// Where a spark thrown from `src` at `v0` is after `tm` seconds, bouncing on `floor_y`; its
// velocity in `vel`.
vec2 spark_at(vec2 src, vec2 v0, float tm, float floor_y, out vec2 vel) {
	vec2 p = src + v0 * tm + vec2(0.0, 0.5 * gravity * tm * tm);
	vel = v0 + vec2(0.0, gravity * tm);
	if (p.y > floor_y) {
		float a = 0.5 * gravity;
		float c = src.y - floor_y;
		float th = (-v0.y + sqrt(max(v0.y * v0.y - 4.0 * a * c, 0.0))) / max(2.0 * a, 0.001);
		vec2 hit = src + v0 * th + vec2(0.0, 0.5 * gravity * th * th);
		vec2 vb = vec2(v0.x * 0.6, -(v0.y + gravity * th) * bounce);
		float t2 = tm - th;
		p = hit + vb * t2 + vec2(0.0, 0.5 * gravity * t2 * t2);
		vel = vb + vec2(0.0, gravity * t2);
		if (p.y > floor_y) {
			p.y = floor_y;
			vel = vec2(vel.x * 0.3, 0.0);
		}
	}
	return p;
}

void fragment() {
	vec2 src = source * rect_size;
	float floor_y = rect_size.y - 2.0;
	float total = 0.0;
	float heat = 0.0;
	bool bursts = burst > 0.5;
	float slot = floor(TIME / max(burst_interval, 0.05));
	for (int i = 0; i < 128; i++) {
		if (i >= count) {
			break;
		}
		float fi = float(i);
		vec2 r = env_hash2(vec2(fi, seed));
		float r3 = env_hash(vec2(fi * 1.7, seed + 3.0));
		float period = life * (0.7 + 0.6 * r3);
		float tm;
		float salt = 0.0;
		if (bursts) {
			tm = TIME - slot * burst_interval - r.x * 0.12;
			salt = slot;
		} else {
			float cyc = (TIME * (0.6 + 0.8 * rate) + r.x * 10.0 * period) / period;
			tm = fract(cyc) * period;
			salt = floor(cyc);
		}
		if (tm < 0.0 || tm > period) {
			continue;
		}
		vec2 rr = env_hash2(vec2(fi + salt * 7.3, seed + 9.0));
		float a0 = radians(angle + (rr.y - 0.5) * spread);
		vec2 v0 = vec2(sin(a0), cos(a0)) * speed * (0.45 + 0.75 * rr.x);
		vec2 vel;
		vec2 p0 = spark_at(src, v0, tm, floor_y, vel);
		float sp = length(vel);
		vec2 tail = p0 - vel / max(sp, 1.0) * min(spark_length * sp / 400.0, spark_length * 2.0);
		vec2 pa = px - tail;
		vec2 ba = p0 - tail;
		float hseg = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0);
		float d = length(pa - ba * hseg);
		float age = tm / period;
		float b = (1.0 - age) * ((1.0 - smoothstep(0.7, 1.6, d)) + exp(-d / 4.0) * glow * 0.35);
		total += b;
		heat += b * (1.0 - age);
	}
	float pulse = bursts ? exp(-max(TIME - slot * burst_interval, 0.0) * 4.0) : 0.75 + 0.25 * sin(TIME * 11.0);
	float g = exp(-length(px - src) / 26.0) * glow * pulse;
	float h = total > 0.0 ? heat / total : 1.0;
	vec3 c = mix(color_cool.rgb, color.rgb, smoothstep(0.15, 0.55, h));
	c = mix(c, color_hot.rgb, smoothstep(0.55, 0.95, h));
	c = mix(c, color_hot.rgb, g / max(total + g, 0.001));
	// Soft only at the sides: the source may sit on the top edge, and they bounce on the bottom one.
	float side = clamp(min(px.x, rect_size.x - px.x) / max(edge_fade, 0.001), 0.0, 1.0);
	COLOR = vec4(c, clamp(total + g, 0.0, 1.0) * intensity * side);
}
