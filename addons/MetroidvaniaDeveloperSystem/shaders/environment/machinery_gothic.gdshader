shader_type canvas_item;
// Gothic castle machinery (MDSMachineryBackground), for Castlevania-style castles: giant
// wheels, clockwork, clock faces, pendulums, bells, chandeliers, rose windows, hanging chains,
// candelabra, winches, spiked rollers, hourglasses, organ pipes, banners, astrolabes, torches,
// windmills, swinging axes, saw blades and castle spires. Soft and out of focus, each moving by
// time alone. See machinery.gdshaderinc for how a machine is drawn.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/machinery.gdshaderinc"

// 0. A giant spoked wheel with paddles round its rim, turning slowly.
vec4 m_giant_wheel(vec2 q, float t, float v, inout float g2) {
	vec2 r = rot(q, t * 0.22);
	float rim = sd_ring(q, 0.84, 0.065);
	float inner_rim = sd_ring(q, 0.68, 0.022);
	float spokes = sd_box(polar_rep(r, 8.0) - vec2(0.42, 0.0), vec2(0.38, 0.032));
	float paddles = sd_box(polar_rep(rot(r, PI / 16.0), 16.0) - vec2(0.95, 0.0), vec2(0.1, 0.03));
	float braces = sd_box(polar_rep(rot(r, PI / 8.0), 8.0) - vec2(0.76, 0.0), vec2(0.08, 0.014));
	float hub = length(q) - 0.15;
	float d = min(min(rim, inner_rim), min(min(spokes, paddles), min(braces, hub)));
	float shade = 0.85 + 0.25 * smoothstep(0.9, 0.2, length(q));
	return vec4(d, 0.0, shade, hub < 0.0 ? 1.0 : 0.0);
}

// 1. Clockwork: a toothed cogwheel with windows cut in it, turning on its axle.
vec4 m_clockwork(vec2 q, float t, float v, inout float g2) {
	float teeth = floor(10.0 + v * 10.0);
	vec2 r = rot(q, t * 0.45 / (0.7 + v * 0.6));
	float g = sd_gear(r, 0.76, teeth, 0.16);
	float windows = length(polar_rep(rot(r, 0.3), 5.0) - vec2(0.44, 0.0)) - 0.16;
	g = max(g, -windows);
	g = max(g, -(length(q) - 0.13));
	float axle = length(q) - 0.07;
	float rim_line = sd_ring(q, 0.62, 0.012);
	float d = min(g, axle);
	float shade = (0.8 + 0.35 * smoothstep(0.85, 0.1, length(q))) * (rim_line < 0.0 ? 0.7 : 1.0);
	return vec4(d, 0.0, shade, 1.0);
}

// 2. A clock face lit from behind, its hands going round.
vec4 m_clock_face(vec2 q, float t, float v, inout float g2) {
	float dial = sd_ring(q, 0.86, 0.06);
	float bezel = sd_ring(q, 0.97, 0.025);
	vec2 k = polar_rep(rot(q, PI * 0.5), 12.0);
	float big = sd_box(k - vec2(0.68, 0.0), vec2(0.09, 0.03));
	float small_ticks = sd_box(polar_rep(rot(q, PI * 0.5), 60.0) - vec2(0.74, 0.0), vec2(0.025, 0.006));
	float quarters = sd_box(polar_rep(rot(q, PI * 0.5), 4.0) - vec2(0.64, 0.0), vec2(0.13, 0.05));
	float hour = sd_seg(rot(q, -t * 0.05 - v * 6.0), vec2(0.0, 0.08), vec2(0.0, -0.42)) - 0.045;
	float minute = sd_seg(rot(q, -t * 0.6 - v * 3.0), vec2(0.0, 0.12), vec2(0.0, -0.64)) - 0.026;
	float hub = length(q) - 0.07;
	float d = min(min(dial, bezel), min(min(big, small_ticks), min(quarters, min(min(hour, minute), hub))));
	// The face glows, as if the moon (or a lamp) were behind it.
	float face = smoothstep(0.83, 0.75, length(q)) * smoothstep(-0.02, 0.02, d);
	float glow = face * (0.32 + 0.06 * sin(t * 0.7));
	return vec4(d, glow, 1.0, (hour < 0.0 || minute < 0.0 || big < 0.0) ? 1.0 : 0.0);
}

// 3. A pendulum swinging from above: a bob, or a blade.
vec4 m_pendulum(vec2 q, float t, float v, inout float g2) {
	float ang = (0.32 + 0.12 * v) * sin(t * 1.1);
	vec2 o = q - vec2(0.0, -1.0);
	vec2 r = rot(o, -ang);
	float rod = sd_seg(r, vec2(0.0), vec2(0.0, 1.42)) - 0.026;
	float end;
	if (v > 0.5) {
		end = max(length(r - vec2(0.0, 1.42)) - 0.4, -(length(r - vec2(0.0, 1.22)) - 0.36));
		end = max(end, abs(r.x) - 0.42);
	} else {
		end = min(length(r - vec2(0.0, 1.52)) - 0.22, sd_ring(r - vec2(0.0, 1.52), 0.14, 0.02));
	}
	float pivot = length(o) - 0.08;
	float bracket = sd_rbox(q - vec2(0.0, -1.08), vec2(0.18, 0.05), 0.02);
	float d = min(min(rod, bracket), min(end, pivot));
	float glint = v > 0.5 ? glow_at(abs(length(r - vec2(0.0, 1.42)) - 0.4), 0.02) * 0.25 * step(0.0, r.y - 1.4) : 0.0;
	return vec4(d, glint, 1.0, end < 0.0 && v <= 0.5 ? 1.0 : 0.0);
}

// 4. A great bell swinging in its yoke, its clapper swinging after it.
vec4 m_bell(vec2 q, float t, float v, inout float g2) {
	float ang = 0.32 * sin(t * 1.0 + v * 3.0);
	vec2 r = rot(q - vec2(0.0, -1.0), -ang);
	float yoke = sd_rbox(r - vec2(0.0, 0.08), vec2(0.34, 0.06), 0.03);
	float dome = length(r - vec2(0.0, 0.42)) - 0.28;
	float k = clamp((r.y - 0.42) / 0.62, 0.0, 1.0);
	float half_w = mix(0.28, 0.6, pow(k, 1.8));
	float flare = max(abs(r.x) - half_w, max(0.42 - r.y, r.y - 1.04));
	float lip = sd_rbox(r - vec2(0.0, 1.04), vec2(0.62, 0.045), 0.03);
	float band = sd_box(r - vec2(0.0, 0.62), vec2(0.42, 0.018));
	float bell = min(min(dome, flare), lip);
	float clapper = length(rot(r - vec2(0.0, 0.62), ang * 0.6) - vec2(0.0, 0.5)) - 0.08;
	float rope = sd_box(q - vec2(0.0, -6.0), vec2(0.02, 5.0));
	float d = min(min(yoke, rope), min(bell, clapper));
	float shade = (band < 0.0 ? 1.25 : 1.0) * (0.8 + 0.35 * smoothstep(0.6, -0.3, r.x));
	return vec4(d, 0.0, shade, bell < 0.0 ? 1.0 : 0.0);
}

// 5. A chandelier swaying on its chain, its candles flickering.
vec4 m_chandelier(vec2 q, float t, float v, inout float g2) {
	float ang = 0.07 * sin(t * 0.7 + v * 5.0);
	vec2 r = rot(q - vec2(0.0, -1.1), -ang);
	float chain = min(sd_seg(r, vec2(0.0), vec2(0.0, 0.9)) - 0.018, sd_box(q - vec2(0.0, -6.1), vec2(0.016, 5.0)));
	float ring = sd_ellipse_ring(r - vec2(0.0, 1.0), vec2(0.72, 0.15), 0.035);
	float body = length((r - vec2(0.0, 1.12)) * vec2(1.0, 0.8)) - 0.13;
	float spike = sd_tri(vec2(r.x, r.y - 1.18), vec2(0.06, 0.22));
	float d = min(min(chain, ring), min(body, spike));
	float glow = 0.0;
	for (float i = 0.0; i < 5.0; i += 1.0) {
		if (abs(r.y - 0.85) > 0.6) {
			break;
		}
		float x = (i - 2.0) * 0.34;
		float y = 1.0 + 0.15 * sqrt(max(1.0 - pow(x / 0.72, 2.0), 0.0)) - 0.12;
		d = min(d, sd_box(r - vec2(x, y), vec2(0.032, 0.09)));
		float f = flicker(t + i * 1.7, v + i);
		vec2 fl = r - vec2(x, y - 0.17);
		glow += (glow_at(length(fl * vec2(1.4, 0.8)) - 0.03, 0.03) * 0.9 + halo(length(fl), 0.26) * 0.2) * f;
	}
	return vec4(d, glow, 1.0, 0.0);
}

// 6. A rose window: stone tracery, its stained glass glowing and shimmering.
vec4 m_rose_window(vec2 q, float t, float v, inout float g2) {
	float rr = length(q);
	float outer = sd_ring(q, 0.9, 0.065);
	float inner_ring = sd_ring(q, 0.36, 0.035);
	vec2 s = polar_rep(q, 8.0);
	float mullions = sd_box(s - vec2(0.63, 0.0), vec2(0.27, 0.022));
	float petals = sd_ring(s - vec2(0.63, 0.0), 0.19, 0.02);
	vec2 s2 = polar_rep(rot(q, PI / 8.0), 8.0);
	float lobes = sd_ring(s2 - vec2(0.25, 0.0), 0.09, 0.014);
	float hub = sd_ring(q, 0.11, 0.03);
	float d = min(min(outer, inner_ring), min(min(mullions, petals), min(lobes, hub)));
	float glass = smoothstep(0.87, 0.8, rr);
	float n = sector(q, 16.0);
	float shimmer = 0.65 + 0.35 * sin(t * 0.6 + n * 1.9 + v * 6.0);
	// The glass shines between the stone, not over it.
	float light = glass * shimmer * 0.55 * smoothstep(-0.02, 0.02, d);
	float glow = 0.0;
	if (mod(n, 2.0) < 0.5) {
		glow = light;
	} else {
		g2 = light;
	}
	glow += glass * smoothstep(0.4, 0.0, rr) * 0.25 * smoothstep(-0.02, 0.02, d);
	return vec4(d, glow, 1.0, 0.0);
}

// 7. A chain hanging from above, swaying, a hook at its end.
vec4 m_hanging_chain(vec2 q, float t, float v, inout float g2) {
	float ang = 0.05 * sin(t * 0.6 + v * 6.0);
	vec2 r = rot(q - vec2(0.0, -1.2), -ang);
	float len = 1.55 + v * 0.45;
	float cell = floor(r.y / 0.17);
	float ly = r.y - (cell + 0.5) * 0.17;
	float link = mod(cell, 2.0) < 0.5 ? abs(sd_rbox(vec2(r.x, ly), vec2(0.05, 0.1), 0.05)) - 0.014 : sd_rbox(vec2(r.x, ly), vec2(0.017, 0.1), 0.017);
	link = max(link, max(-r.y, r.y - len));
	vec2 h = r - vec2(0.07, len + 0.1);
	float hook = max(sd_ring(h, 0.1, 0.022), -h.y - 0.02);
	hook = min(hook, sd_seg(r, vec2(0.0, len - 0.02), vec2(-0.03, len + 0.08)) - 0.022);
	return vec4(min(link, hook), 0.0, 1.0, 0.0);
}

// 8. A candelabra on the floor, three candles flickering.
vec4 m_candelabra(vec2 q, float t, float v, inout float g2) {
	float base = min(sd_rbox(q - vec2(0.0, 0.96), vec2(0.3, 0.04), 0.02), max(length(q - vec2(0.0, 0.96)) - 0.18, q.y - 0.96));
	float stem = sd_seg(q, vec2(0.0, 0.9), vec2(0.0, -0.05)) - 0.035;
	float knobs = min(length(q - vec2(0.0, 0.55)) - 0.065, length(q - vec2(0.0, 0.25)) - 0.05);
	float arms = max(sd_ring(q - vec2(0.0, -0.05), 0.42, 0.026), -(q.y + 0.05));
	float d = min(min(base, stem), min(knobs, arms));
	float glow = 0.0;
	for (float i = -1.0; i <= 1.0; i += 1.0) {
		vec2 c = vec2(i * 0.42, -0.05);
		d = min(d, sd_rbox(q - c - vec2(0.0, 0.02), vec2(0.08, 0.03), 0.015));
		d = min(d, sd_box(q - c - vec2(0.0, -0.15), vec2(0.035, 0.13)));
		float f = flicker(t + i * 2.3, v + i);
		vec2 fl = q - c - vec2(0.0, -0.36);
		glow += (glow_at(length(fl * vec2(1.5, 0.75)) - 0.03, 0.03) + halo(length(fl), 0.3) * 0.22) * f;
	}
	return vec4(d, glow, 1.0, base < 0.0 || knobs < 0.0 ? 1.0 : 0.0);
}

// 9. A winch: a spoked wheel turning a drum, its chain winding up.
vec4 m_winch(vec2 q, float t, float v, inout float g2) {
	vec2 wc = q - vec2(-0.4, 0.15);
	vec2 r = rot(wc, t * 0.5);
	float wheel = min(sd_ring(wc, 0.42, 0.04), sd_box(polar_rep(r, 6.0) - vec2(0.2, 0.0), vec2(0.21, 0.022)));
	wheel = min(wheel, length(wc) - 0.07);
	float drum = sd_rbox(q - vec2(0.3, 0.15), vec2(0.4, 0.22), 0.05);
	float frame = min(sd_seg(q, vec2(-0.9, 0.95), vec2(-0.4, 0.15)) - 0.035, sd_seg(q, vec2(0.95, 0.95), vec2(0.5, 0.15)) - 0.035);
	frame = min(frame, sd_box(q - vec2(0.0, 0.97), vec2(1.0, 0.04)));
	vec2 c = q - vec2(0.6, 0.0);
	float cy = c.y - t * 0.12;
	float cell = floor(cy / 0.15);
	float ly = cy - (cell + 0.5) * 0.15;
	float link = mod(cell, 2.0) < 0.5 ? abs(sd_rbox(vec2(c.x, ly), vec2(0.045, 0.09), 0.045)) - 0.012 : sd_rbox(vec2(c.x, ly), vec2(0.015, 0.09), 0.015);
	link = max(link, max(c.y, -1.5 - c.y));
	float d = min(min(wheel, drum), min(frame, link));
	// The drum's bands roll as it turns.
	float shade = drum < 0.0 ? 0.8 + 0.25 * step(0.0, sin((q.y - t * 0.12) * 45.0)) : 1.0;
	return vec4(d, 0.0, shade, drum < 0.0 ? 1.0 : 0.0);
}

// 10. A spiked roller turning on its beam.
vec4 m_spiked_roller(vec2 q, float t, float v, inout float g2) {
	vec2 r = rot(q, t * 0.7);
	float body = length(q) - 0.48;
	vec2 s = polar_rep(r, 10.0);
	float spikes = sd_tri(vec2(s.y, 0.92 - s.x), vec2(0.1, 0.46));
	float beam = sd_box(q, vec2(2.2, 0.05));
	float bands = sd_ring(q, 0.32, 0.02);
	float d = min(min(body, spikes), beam);
	float shade = (bands < 0.0 ? 0.7 : 1.0) * (body < 0.0 ? 0.85 + 0.3 * smoothstep(0.5, -0.4, q.x + q.y) : 1.0);
	return vec4(d, 0.0, shade, spikes < 0.0 && body > 0.0 ? 1.0 : 0.0);
}

// 11. An hourglass running out, then turned over.
vec4 m_hourglass(vec2 q, float t, float v, inout float g2) {
	float cycle = mod(t + v * 9.0, 10.0);
	float ang = PI * smoothstep(8.6, 10.0, cycle);
	float s = clamp(cycle / 8.4, 0.0, 1.0);
	vec2 r = rot(q, ang);
	float plates = min(sd_rbox(r - vec2(0.0, -0.86), vec2(0.5, 0.06), 0.03), sd_rbox(r - vec2(0.0, 0.86), vec2(0.5, 0.06), 0.03));
	float posts = min(sd_box(r - vec2(-0.42, 0.0), vec2(0.03, 0.82)), sd_box(r - vec2(0.42, 0.0), vec2(0.03, 0.82)));
	float top_bulb = sd_tri(vec2(r.x, -r.y), vec2(0.34, 0.78));
	float bottom_bulb = sd_tri(r, vec2(0.34, 0.78));
	float glass = min(abs(top_bulb), abs(bottom_bulb)) - 0.012;
	float level = 0.72 * (1.0 - s);
	float sand_top = max(top_bulb, -r.y - level);
	float pile = max(bottom_bulb, 0.78 - 0.62 * s + abs(r.x) * 0.55 - r.y);
	float stream = ang < 0.01 && s < 0.999 ? sd_box(r - vec2(0.0, 0.38), vec2(0.008, 0.38)) : 1.0;
	float sand = min(min(sand_top, pile), stream);
	float d = min(min(plates, posts), min(glass, sand));
	float sheen = glow_at(abs(top_bulb + 0.05), 0.02) * 0.12 + glow_at(abs(bottom_bulb + 0.05), 0.02) * 0.12;
	return vec4(d, sheen, sand < 0.0 ? 1.3 : 1.0, sand < 0.0 ? 1.0 : 0.0);
}

// 12. Organ pipes on the floor, sound pulsing up them.
vec4 m_organ_pipes(vec2 q, float t, float v, inout float g2) {
	float d = sd_rbox(q - vec2(0.0, 0.97), vec2(1.02, 0.06), 0.02);
	float glow = 0.0;
	float shade = 1.0;
	// Only the pipes near here: the one under it and its neighbours.
	float near_pipe = clamp(floor(q.x / 0.27 + 3.5), 0.0, 6.0);
	for (float i = max(near_pipe - 1.0, 0.0); i <= min(near_pipe + 1.0, 6.0); i += 1.0) {
		float x = (i - 3.0) * 0.27;
		float h = 1.75 - abs(i - 3.0) * 0.24 - env_hash(vec2(i, v * 13.0)) * 0.12;
		float pipe = sd_rbox(q - vec2(x, 0.93 - h * 0.5), vec2(0.075, h * 0.5), 0.05);
		float mouth = sd_tri(vec2(q.x - x, q.y - 0.55), vec2(0.05, 0.12));
		d = min(d, pipe);
		if (mouth < 0.0 && pipe < 0.0) {
			shade = 0.35;
		}
		float beat = 0.5 + 0.5 * sin(t * 1.6 + i * 1.3 + v * 7.0);
		glow += glow_at(length(q - vec2(x, 0.6)) - 0.02, 0.06) * beat * beat * 0.6;
		float wave = fract((0.93 - q.y) / max(h, 0.1) - t * 0.35 - i * 0.17);
		glow += pipe < 0.0 ? smoothstep(0.08, 0.0, abs(wave - 0.5)) * beat * 0.12 : 0.0;
	}
	return vec4(d, glow, shade, 1.0);
}

// 13. A banner hanging from its rod, waving, tattered at the bottom.
vec4 m_banner(vec2 q, float t, float v, inout float g2) {
	float k = clamp((q.y + 0.9) / 1.75, 0.0, 1.0);
	vec2 w = vec2(q.x - 0.08 * sin(q.y * 3.0 - t * 1.4 + v * 6.0) * k, q.y);
	float bottom = 0.82 - 0.16 * abs(fract(w.x * 2.6 + 0.5 + v) - 0.5) * 2.0;
	float cloth = max(abs(w.x) - 0.38, max(-0.9 - w.y, w.y - bottom));
	float rod = sd_seg(q, vec2(-0.5, -0.93), vec2(0.5, -0.93)) - 0.03;
	float ends = min(length(q - vec2(-0.55, -0.93)) - 0.06, length(q - vec2(0.55, -0.93)) - 0.06);
	float emblem = sd_ring(w - vec2(0.0, -0.25), 0.15, 0.032);
	float cross_mark = min(sd_box(w - vec2(0.0, -0.25), vec2(0.02, 0.1)), sd_box(w - vec2(0.0, -0.27), vec2(0.07, 0.02)));
	float d = min(cloth, min(rod, ends));
	float folds = 0.78 + 0.22 * sin(w.x * 14.0 + sin(q.y * 2.0 - t * 1.4) * 2.0);
	float shade = cloth < 0.0 ? folds * (min(emblem, cross_mark) < 0.0 ? 1.8 : 1.0) : 1.0;
	return vec4(d, 0.0, shade, cloth < 0.0 ? 1.0 : 0.0);
}

// 14. An astrolabe: nested rings turning about a glowing core, on its stand.
vec4 m_astrolabe(vec2 q, float t, float v, inout float g2) {
	float d = 1e3;
	for (float i = 0.0; i < 3.0; i += 1.0) {
		float radius = 0.84 - i * 0.18;
		vec2 p = rot(q, 0.35 + i * 1.15 + v * 2.0);
		float b = max(abs(cos(t * (0.45 + i * 0.2) + i * 1.3)), 0.07);
		d = min(d, sd_ellipse_ring(p, vec2(radius, radius * b), 0.028));
	}
	float equator = sd_ring(q, 0.92, 0.02);
	float stand = min(sd_seg(q, vec2(0.0, 0.92), vec2(0.0, 1.2)) - 0.045, sd_rbox(q - vec2(0.0, 1.22), vec2(0.36, 0.05), 0.02));
	float core = length(q) - 0.12;
	d = min(min(d, equator), min(stand, core));
	float glow = glow_at(length(q) - 0.1, 0.08) * (0.7 + 0.2 * sin(t * 1.3)) + halo(length(q), 0.42) * 0.14;
	return vec4(d, glow, 1.0, core < 0.0 ? 0.0 : 1.0);
}

// 15. A torch in its wall sconce, its flame flickering.
vec4 m_torch(vec2 q, float t, float v, inout float g2) {
	float plate = sd_rbox(q - vec2(0.0, 0.62), vec2(0.13, 0.18), 0.04);
	float arm = sd_seg(q, vec2(0.0, 0.6), vec2(0.0, 0.08)) - 0.04;
	float cup = max(abs(q.x) - mix(0.07, 0.2, clamp((0.14 - q.y) / 0.16, 0.0, 1.0)), max(q.y - 0.14, -0.04 - q.y));
	float d = min(plate, min(arm, cup));
	float f = flicker(t, v);
	vec2 fp = q - vec2(0.04 * sin(q.y * 9.0 + t * 8.0), -0.2);
	float flame = smin(length(fp * vec2(1.0, 0.85)) - 0.13 * f, sd_tri(vec2(fp.x, fp.y + 0.48 * f), vec2(0.12, 0.42 * f)), 0.08);
	float glow = smoothstep(0.03, -0.06, flame) * 1.2 * f + halo(length(q - vec2(0.0, -0.25)), 0.38) * 0.38 * f;
	g2 = smoothstep(0.0, -0.08, flame) * 0.6;
	return vec4(d, glow, 1.0, cup < 0.0 ? 1.0 : 0.0);
}

// 16. A windmill on its tower, its latticed sails turning.
vec4 m_windmill(vec2 q, float t, float v, inout float g2) {
	vec2 hub_at = vec2(0.0, -0.08);
	float tower = max(abs(q.x) - mix(0.14, 0.33, clamp((q.y + 0.05) / 1.05, 0.0, 1.0)), max(-0.05 - q.y, q.y - 1.0));
	float cap = max(length(q - vec2(0.0, -0.06)) - 0.18, q.y + 0.02);
	vec2 s = polar_rep(rot(q - hub_at, t * 0.35), 4.0);
	float arm = sd_box(s - vec2(0.48, 0.0), vec2(0.48, 0.016));
	float sail = sd_box(s - vec2(0.56, 0.085), vec2(0.38, 0.075));
	float holes = sd_box(vec2(mod(s.x, 0.1) - 0.05, s.y - 0.085), vec2(0.034, 0.052));
	sail = max(sail, -holes);
	float hub = length(q - hub_at) - 0.06;
	float d = min(min(tower, cap), min(min(arm, sail), hub));
	float win = sd_rbox(q - vec2(0.0, 0.45), vec2(0.05, 0.08), 0.04);
	float glow = smoothstep(0.02, -0.02, win) * flicker(t * 0.4, v) * 0.8 + glow_at(win, 0.08) * 0.15;
	return vec4(d, glow, 1.0, sail < 0.0 ? 1.0 : 0.0);
}

// 17. A great axe blade swinging from above.
vec4 m_swinging_axe(vec2 q, float t, float v, inout float g2) {
	float ang = 0.75 * sin(t * 1.25 + v * 6.0);
	vec2 r = rot(q - vec2(0.0, -1.0), -ang);
	float rod = sd_seg(r, vec2(0.0), vec2(0.0, 1.2)) - 0.032;
	float outer = length(r - vec2(0.0, 1.1)) - 0.52;
	float bite = length(r - vec2(0.0, 0.82)) - 0.5;
	float blade = max(max(outer, -bite), abs(r.x) - 0.56);
	float mount = sd_rbox(r - vec2(0.0, 1.2), vec2(0.08, 0.1), 0.03);
	float pivot = length(r) - 0.08;
	float d = min(min(rod, blade), min(mount, pivot));
	float glint = glow_at(abs(outer), 0.015) * step(r.y, 1.62) * step(1.2, r.y) * (0.25 + 0.25 * sin(t * 1.25 + v * 6.0 + 1.6));
	return vec4(d, glint, 1.0, blade < 0.0 ? 0.0 : 1.0);
}

// 18. A saw blade spinning fast, sliding along its slot.
vec4 m_saw_blade(vec2 q, float t, float v, inout float g2) {
	vec2 c = q - vec2(0.4 * sin(t * 0.45 + v * 6.0), 0.0);
	float a = atan(c.y, c.x) + t * 3.5;
	float teeth = 0.56 + 0.09 * fract(a / TAU * 26.0);
	float blade = length(c) - teeth;
	float hole = length(c) - 0.09;
	vec2 s = polar_rep(rot(c, t * 3.5), 3.0);
	float slots = max(sd_ring(c, 0.32, 0.04), -s.y);
	blade = max(blade, -min(hole, slots));
	float slot = sd_box(q, vec2(1.5, 0.03));
	float d = min(blade, slot);
	float glint = glow_at(abs(length(c) - 0.6), 0.02) * 0.25;
	return vec4(d, glint, slot < 0.0 && blade > 0.0 ? 0.4 : 0.8 + 0.3 * smoothstep(0.6, -0.4, c.x + c.y), blade < 0.0 ? 1.0 : 0.0);
}

// 19. Castle spires against the sky: towers, pointed roofs, lit windows, a flag.
vec4 m_spires(vec2 q, float t, float v, inout float g2) {
	float d = 1e3;
	float glow = 0.0;
	float flag = 1e3;
	for (float k = 0.0; k < 3.0; k += 1.0) {
		float x = (k - 1.0) * 0.55 + (env_hash(vec2(k, v * 7.0)) - 0.5) * 0.1;
		float w = k == 1.0 ? 0.24 : 0.15;
		float top = k == 1.0 ? -0.35 : 0.1 + env_hash(vec2(k + 3.0, v * 7.0)) * 0.15;
		float roof_h = w * 2.6;
		if (abs(q.x - x) > w * 1.45 + 0.3) {
			continue;
		}
		d = min(d, sd_box(q - vec2(x, (1.0 + top) * 0.5), vec2(w, (1.0 - top) * 0.5)));
		d = min(d, sd_tri(vec2(q.x - x, q.y - (top - roof_h)), vec2(w * 1.3, roof_h)));
		d = min(d, sd_box(q - vec2(x, top), vec2(w * 1.15, 0.025)));
		for (float j = 0.0; j < 3.0; j += 1.0) {
			vec2 at = vec2(x, top + 0.18 + j * 0.24);
			if (at.y > 0.92) {
				continue;
			}
			float h = env_hash(vec2(k * 7.0 + j, v * 3.0));
			float lit = step(0.35, h);
			float f = 0.7 + 0.3 * sin(t * (0.6 + h) + h * 20.0);
			float win = sd_rbox(q - at, vec2(0.035, 0.06), 0.035);
			glow += lit * (smoothstep(0.015, -0.015, win) * f + glow_at(win, 0.07) * 0.2 * f);
		}
		if (k == 1.0) {
			vec2 apex = vec2(x, top - roof_h);
			d = min(d, sd_seg(q, apex, apex - vec2(0.0, 0.25)) - 0.012);
			vec2 fp = q - apex - vec2(0.0, -0.22);
			float wave = 0.03 * sin(fp.x * 14.0 - t * 4.0) * clamp(fp.x / 0.25, 0.0, 1.0);
			flag = sd_box(vec2(fp.x - 0.13, fp.y - wave), vec2(0.13, 0.05));
		}
	}
	d = min(d, flag);
	return vec4(d, glow, 1.0, flag < 0.0 ? 1.0 : 0.0);
}

// Each machine's box (x0, x1, y0, y1 in its space), its glow included.
vec4 machine_bounds(float v) {
	switch (kind) {
		case 0: return vec4(-1.06, 1.06, -1.06, 1.06);
		case 1: return vec4(-0.98, 0.98, -0.98, 0.98);
		case 2: return vec4(-1.0, 1.0, -1.0, 1.0);
		case 3: return vec4(-1.3, 1.3, -1.15, 1.02);
		case 4: return vec4(-1.02, 1.02, -1.12, 0.2);
		case 5: return vec4(-1.42, 1.42, -1.15, 0.48);
		case 6: return vec4(-1.0, 1.0, -1.0, 1.0);
		case 7: return vec4(-0.32, 0.32, -1.22, 1.08);
		case 8: return vec4(-1.22, 1.22, -1.25, 1.02);
		case 9: return vec4(-0.96, 1.0, -1.52, 1.0);
		case 10: return vec4(-2.22, 2.22, -0.95, 0.95);
		case 11: return vec4(-1.0, 1.0, -1.0, 1.0);
		case 12: return vec4(-1.06, 1.06, -0.96, 1.05);
		case 13: return vec4(-0.64, 0.64, -1.0, 0.86);
		case 14: return vec4(-1.0, 1.0, -1.0, 1.3);
		case 15: return vec4(-1.02, 1.02, -1.3, 0.9);
		case 16: return vec4(-1.02, 1.02, -1.06, 1.0);
		case 17: return vec4(-1.78, 1.78, -1.1, 0.78);
		case 18: return vec4(-1.52, 1.52, -0.72, 0.72);
	}
	return vec4(-0.95, 0.95, -1.38, 1.0);
}

// Bells and chandeliers hang from a rope or chain running up out of sight.
bool machine_rope() {
	return kind == 4 || kind == 5;
}

vec4 machine(vec2 q, float t, float v, inout float g2) {
	switch (kind) {
		case 0: return m_giant_wheel(q, t, v, g2);
		case 1: return m_clockwork(q, t, v, g2);
		case 2: return m_clock_face(q, t, v, g2);
		case 3: return m_pendulum(q, t, v, g2);
		case 4: return m_bell(q, t, v, g2);
		case 5: return m_chandelier(q, t, v, g2);
		case 6: return m_rose_window(q, t, v, g2);
		case 7: return m_hanging_chain(q, t, v, g2);
		case 8: return m_candelabra(q, t, v, g2);
		case 9: return m_winch(q, t, v, g2);
		case 10: return m_spiked_roller(q, t, v, g2);
		case 11: return m_hourglass(q, t, v, g2);
		case 12: return m_organ_pipes(q, t, v, g2);
		case 13: return m_banner(q, t, v, g2);
		case 14: return m_astrolabe(q, t, v, g2);
		case 15: return m_torch(q, t, v, g2);
		case 16: return m_windmill(q, t, v, g2);
		case 17: return m_swinging_axe(q, t, v, g2);
		case 18: return m_saw_blade(q, t, v, g2);
	}
	return m_spires(q, t, v, g2);
}

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/machinery_draw.gdshaderinc"
