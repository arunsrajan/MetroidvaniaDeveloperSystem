shader_type canvas_item;
// Alien and space-station machinery (MDSMachineryBackground), for Metroid-style worlds:
// turbines, reactor cores, gyro rings, pistons, energy conduits, radar dishes, holograms, ringed
// planets, robot arms, drills, tesla coils, exhaust fans, bio pods, specimen tanks, data
// streams, laser sweeps, warp portals, crystal pylons, press hammers and cargo lifts. Soft and
// out of focus, each moving by time alone. See machinery.gdshaderinc for how a machine is drawn.

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/machinery.gdshaderinc"

// 0. A turbine spinning in its housing, its hub glowing.
vec4 m_turbine(vec2 q, float t, float v, inout float g2) {
	float rr = length(q);
	float housing = sd_ring(q, 0.9, 0.07);
	vec2 s = polar_rep(rot(q, t * 2.4), 9.0);
	float blades = max(sd_rbox(rot(s - vec2(0.5, 0.0), 0.55), vec2(0.34, 0.055), 0.04), rr - 0.84);
	float hub = rr - 0.18;
	float struts = sd_box(polar_rep(rot(q, 0.5), 3.0) - vec2(0.55, 0.0), vec2(0.35, 0.02));
	float d = min(min(housing, blades), min(hub, struts));
	float glow = glow_at(rr - 0.08, 0.06) * (0.8 + 0.2 * sin(t * 3.0)) + glow_at(abs(rr - 0.86), 0.02) * 0.2;
	return vec4(d, glow, hub < 0.0 ? 1.3 : 1.0, housing < 0.0 ? 1.0 : 0.0);
}

// 1. A reactor core pulsing inside counter-turning shield rings, energy arcing off it.
vec4 m_reactor(vec2 q, float t, float v, inout float g2) {
	float rr = length(q);
	float beat = 0.6 + 0.4 * sin(t * 2.2 + v * 6.0);
	float seg1 = max(sd_ring(q, 0.5, 0.05), 0.06 - abs(polar_rep(rot(q, t * 0.5), 8.0).y));
	float seg2 = max(sd_ring(q, 0.7, 0.035), 0.08 - abs(polar_rep(rot(q, -t * 0.8), 6.0).y));
	float frame = sd_ring(q, 0.92, 0.05);
	float struts = sd_box(polar_rep(rot(q, PI * 0.25), 4.0) - vec2(0.82, 0.0), vec2(0.12, 0.05));
	float d = min(min(seg1, seg2), min(frame, struts));
	vec2 pa = polar_rep(rot(q, floor(t * 7.0) * 1.3), 3.0);
	float jag = (env_noise(vec2(rr * 14.0, floor(t * 14.0) + v * 9.0)) - 0.5) * 0.09;
	float arcs = glow_at(abs(pa.y + jag) - 0.004, 0.012) * smoothstep(0.46, 0.25, rr) * smoothstep(0.14, 0.22, rr) * 0.7;
	float glow = glow_at(rr - 0.17, 0.07) * (0.7 + 0.7 * beat) + halo(rr, 0.42) * 0.25 * beat + arcs;
	g2 = glow_at(abs(rr - 0.5), 0.04) * 0.25 * beat;
	return vec4(d, glow, 1.0, seg1 < 0.0 ? 1.0 : 0.0);
}

// 2. Gyro rings turning about each other round a glowing orb, light running along them.
vec4 m_gyro(vec2 q, float t, float v, inout float g2) {
	float d = length(q) - 0.15;
	float glow = glow_at(length(q) - 0.12, 0.08) * 0.9 + halo(length(q), 0.38) * 0.16;
	for (float i = 0.0; i < 3.0; i += 1.0) {
		float radius = 0.88 - i * 0.2;
		vec2 p = rot(q, i * 1.05 + v * 3.0);
		float b = max(abs(cos(t * (0.6 + i * 0.3) + i)), 0.06);
		float ring = sd_ellipse_ring(p, vec2(radius, radius * b), 0.032);
		d = min(d, ring);
		glow += smoothstep(0.012, 0.0, abs(ring + 0.032)) * 0.5;
	}
	return vec4(d, glow, 1.0, 1.0);
}

// 3. A hydraulic piston pumping up and down, venting at the bottom of its stroke.
vec4 m_piston(vec2 q, float t, float v, inout float g2) {
	float stroke = 0.5 + 0.5 * sin(t * 1.6 + v * 6.0);
	float housing = sd_rbox(q - vec2(0.0, 0.62), vec2(0.28, 0.36), 0.05);
	float collar = sd_rbox(q - vec2(0.0, 0.24), vec2(0.34, 0.05), 0.02);
	float top = 0.15 - 0.95 * stroke;
	float rod = sd_box(q - vec2(0.0, (top + 0.25) * 0.5), vec2(0.07, (0.25 - top) * 0.5));
	float head = sd_rbox(q - vec2(0.0, top - 0.06), vec2(0.36, 0.08), 0.03);
	float d = min(min(housing, collar), min(rod, head));
	float lamp = length(q - vec2(0.16, 0.48)) - 0.035;
	float glow = smoothstep(0.01, -0.01, lamp) * (0.4 + 0.6 * (1.0 - stroke)) + glow_at(lamp, 0.05) * 0.3;
	g2 = glow_at(length((q - vec2(0.0, 0.2)) * vec2(0.6, 1.0)) - 0.1, 0.12) * pow(1.0 - stroke, 4.0) * 0.7;
	return vec4(d, glow, 1.0, rod < 0.0 ? 1.0 : 0.0);
}

// 4. Energy conduits: pipes with pulses of light racing along them (some upright).
vec4 m_conduit(vec2 q, float t, float v, inout float g2) {
	vec2 p = v > 0.5 ? vec2(q.y, q.x) : q;
	float pipe1 = sd_rbox(p - vec2(0.0, -0.18), vec2(2.4, 0.11), 0.05);
	float pipe2 = sd_rbox(p - vec2(0.0, 0.2), vec2(2.4, 0.07), 0.03);
	float flanges = sd_rbox(vec2(mod(p.x + 0.3, 0.6) - 0.3, p.y), vec2(0.035, 0.32), 0.015);
	float d = min(min(pipe1, pipe2), flanges);
	float pulse = smoothstep(0.18, 0.0, abs(fract(p.x * 0.5 - t * 0.55 + v * 3.0) - 0.5));
	float core = smoothstep(0.05, 0.0, abs(p.y + 0.18)) * step(pipe1, 0.0);
	float glow = core * (0.25 + 0.95 * pulse) + glow_at(abs(p.y + 0.18) - 0.04, 0.05) * pulse * 0.25;
	float pulse2 = smoothstep(0.12, 0.0, abs(fract(p.x * 0.35 + t * 0.3) - 0.5));
	g2 = smoothstep(0.03, 0.0, abs(p.y - 0.2)) * step(pipe2, 0.0) * (0.15 + 0.6 * pulse2);
	return vec4(d, glow, flanges < 0.0 ? 1.25 : 1.0, pipe2 < 0.0 ? 1.0 : 0.0);
}

// 5. A radar dish on its mast, turning, its feed light blinking.
vec4 m_radar(vec2 q, float t, float v, inout float g2) {
	float mast = sd_box(q - vec2(0.0, 0.55), vec2(0.05, 0.45));
	float base = sd_rbox(q - vec2(0.0, 0.97), vec2(0.3, 0.06), 0.02);
	float yoke = sd_rbox(q - vec2(0.0, 0.1), vec2(0.12, 0.08), 0.03);
	float spin = cos(t * 0.7 + v * 6.0);
	float k = max(abs(spin), 0.12);
	vec2 dp = vec2(q.x / k, q.y);
	float dish = max(sd_ring(dp - vec2(0.0, -0.75), 0.75, 0.04), -(dp.y + 0.12));
	dish = max(dish, abs(dp.x) - 0.66) * k;
	float feed = (sd_seg(dp, vec2(0.0, -0.02), vec2(0.0, -0.46)) - 0.018) * k;
	float d = min(min(mast, base), min(yoke, min(dish, feed)));
	float blink = step(0.82, fract(t * 0.6 + v));
	vec2 tip = vec2(0.0, -0.48);
	float glow = glow_at(length(q - tip) - 0.03, 0.05) * (0.25 + 0.9 * blink);
	return vec4(d, glow, dish < 0.0 ? 0.75 + 0.45 * smoothstep(-0.5, 0.5, spin * q.x) : 1.0, dish < 0.0 ? 1.0 : 0.0);
}

// 6. A hologram of a world turning above its projector, scanlines rolling through it.
vec4 m_hologram(vec2 q, float t, float v, inout float g2) {
	float base = min(sd_rbox(q - vec2(0.0, 0.9), vec2(0.38, 0.08), 0.04), sd_rbox(q - vec2(0.0, 0.8), vec2(0.16, 0.04), 0.02));
	vec2 g = q - vec2(0.0, -0.15);
	float rr = length(g);
	float lines = smoothstep(0.014, 0.0, abs(rr - 0.55));
	for (float k = -2.0; k <= 2.0; k += 1.0) {
		float y = k * 0.2;
		float hw = sqrt(max(0.3025 - y * y, 0.0));
		lines += smoothstep(0.01, 0.0, abs(g.y - y)) * step(abs(g.x), hw);
		float lon = 0.55 * abs(cos(t * 0.8 + k * 0.63));
		lines += smoothstep(0.012, 0.0, abs(sd_ellipse_ring(g, vec2(lon, 0.55), 0.0))) * step(rr, 0.56);
	}
	float scan = 0.7 + 0.3 * sin(q.y * 70.0 - t * 5.0);
	float stutter = 0.85 + 0.15 * step(0.94, env_hash(vec2(floor(t * 18.0), v)));
	float cone = sd_tri(vec2(q.x, 0.8 - q.y), vec2(0.5, 1.0));
	float glow = (min(lines, 1.5) * 0.55 * scan + smoothstep(0.0, -0.12, cone) * 0.1 + smoothstep(0.56, 0.0, rr) * 0.08) * stutter;
	return vec4(base, glow, 1.0, 0.0);
}

// 7. A ringed planet, its bands drifting, a moon going round it.
vec4 m_planet(vec2 q, float t, float v, inout float g2) {
	vec2 p = rot(q, -0.35 + v * 0.5);
	float planet = length(p) - 0.55;
	float ring = min(sd_ellipse_ring(p, vec2(0.98, 0.24), 0.05), sd_ellipse_ring(p, vec2(0.8, 0.2), 0.02));
	if (p.y < 0.0) {
		ring = max(ring, -planet);
	}
	float a = t * 0.25 + v * 6.0;
	vec2 mp = vec2(cos(a) * 1.2, sin(a) * 0.32);
	float moon = length(p - mp) - 0.075;
	if (sin(a) < 0.0) {
		moon = max(moon, -planet);
	}
	float d = min(min(planet, ring), moon);
	float bands = 0.78 + 0.22 * sin(p.y * 15.0 + env_noise(vec2(p.x * 3.0 + t * 0.06, p.y * 7.0)) * 3.0);
	float sun = clamp(dot(p / 0.55, vec2(-0.6, -0.6)) * 0.55 + 0.6, 0.18, 1.25);
	float shade = planet < 0.0 ? bands * sun : (ring < 0.0 ? 1.35 : 1.0);
	float glow = glow_at(abs(planet), 0.03) * 0.35 * clamp(sun, 0.3, 1.0);
	return vec4(d, glow, shade, planet < 0.0 || ring < 0.0 ? 1.0 : 0.0);
}

// 8. A robot arm on its base, reaching and turning, its claw opening and closing.
vec4 m_robot_arm(vec2 q, float t, float v, inout float g2) {
	float base = min(sd_rbox(q - vec2(0.0, 0.9), vec2(0.32, 0.1), 0.05), length(q - vec2(0.0, 0.75)) - 0.16);
	float a1 = -0.5 + 0.35 * sin(t * 0.7 + v * 6.0);
	vec2 j1 = vec2(0.0, 0.75);
	vec2 d1 = vec2(sin(a1), -cos(a1));
	vec2 j2 = j1 + d1 * 0.78;
	float a2 = a1 + 1.25 + 0.5 * sin(t * 0.9 + 1.0 + v * 3.0);
	vec2 d2 = vec2(sin(a2), -cos(a2));
	vec2 j3 = j2 + d2 * 0.62;
	float seg1 = sd_seg(q, j1, j2) - 0.075;
	float seg2 = sd_seg(q, j2, j3) - 0.055;
	float joint = length(q - j2) - 0.1;
	float open = 0.35 + 0.25 * sin(t * 1.8 + v * 4.0);
	float claw = min(sd_seg(q, j3, j3 + rot(d2, open) * 0.24) - 0.026, sd_seg(q, j3, j3 + rot(d2, -open) * 0.24) - 0.026);
	float d = min(min(base, seg1), min(min(seg2, joint), claw));
	float glow = glow_at(length(q - j2) - 0.03, 0.04) * 0.7 + glow_at(length(q - j1) - 0.03, 0.04) * 0.5;
	return vec4(d, glow, 1.0, seg1 < 0.0 || seg2 < 0.0 ? 1.0 : 0.0);
}

// 9. A giant drill boring down, its spiral turning, its tip glowing hot.
vec4 m_drill(vec2 q, float t, float v, inout float g2) {
	q.y -= 0.06 * sin(t * 0.5 + v * 6.0);
	float housing = sd_rbox(q - vec2(0.0, -0.7), vec2(0.42, 0.28), 0.06);
	float collar = sd_rbox(q - vec2(0.0, -0.38), vec2(0.3, 0.05), 0.02);
	float bit = sd_tri(vec2(q.x, 0.95 - q.y), vec2(0.32, 1.3));
	float d = min(min(housing, collar), bit);
	float grooves = 0.75 + 0.3 * step(0.0, sin(q.y * 10.0 - q.x * 18.0 + t * 9.0));
	float vents = sd_box(vec2(mod(q.x + 0.06, 0.12) - 0.06, q.y + 0.7), vec2(0.02, 0.14));
	float glow = (glow_at(length(q - vec2(0.0, 0.95)) - 0.02, 0.04) * 0.6 + halo(length(q - vec2(0.0, 0.95)), 0.14) * 0.5) + (vents < 0.0 && housing < 0.0 ? 0.35 : 0.0);
	return vec4(d, glow, bit < 0.0 ? grooves : 1.0, bit < 0.0 ? 1.0 : 0.0);
}

// 10. A tesla coil, lightning crackling off its crown.
vec4 m_tesla(vec2 q, float t, float v, inout float g2) {
	float d = sd_rbox(q - vec2(0.0, 0.95), vec2(0.3, 0.06), 0.02);
	// The stack of discs: only the one near here.
	float k = clamp(floor((0.82 - q.y) / 0.15 + 0.5), 0.0, 5.0);
	d = min(d, sd_rbox(q - vec2(0.0, 0.82 - k * 0.15), vec2(0.17 - k * 0.012, 0.05), 0.025));
	d = min(d, sd_box(q - vec2(0.0, 0.0), vec2(0.06, 0.12)));
	vec2 crown = vec2(0.0, -0.18);
	float torus = sd_ellipse_ring(q - crown, vec2(0.34, 0.12), 0.07);
	d = min(d, torus);
	float glow = glow_at(abs(torus), 0.05) * 0.3;
	for (float i = 0.0; i < 3.0; i += 1.0) {
		if (length(q - crown) > 1.0) {
			break;
		}
		float tick = floor(t * 8.0 + i * 0.37);
		float live = step(0.35, env_hash(vec2(tick, i + v * 7.0)));
		float ang = (env_hash(vec2(tick + 1.0, i * 3.0 + v)) - 0.5) * 2.6 - PI * 0.5;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 start = crown + dir * vec2(0.34, 0.12);
		vec2 rel = q - start;
		float along = dot(rel, dir);
		float len = 0.5 + 0.4 * env_hash(vec2(tick, i + 5.0));
		float side = dot(rel, vec2(-dir.y, dir.x));
		float s = clamp(along / len, 0.0, 1.0);
		float bend = (env_noise(vec2(s * 7.0, tick * 1.7 + i)) - 0.5) * 0.22 * sin(s * PI);
		float on_arc = step(0.0, along) * step(along, len);
		glow += live * on_arc * (glow_at(abs(side - bend) - 0.004, 0.01) * 0.9 + glow_at(abs(side - bend), 0.06) * 0.15);
	}
	g2 = halo(length(q - crown), 0.32) * 0.28 * (0.7 + 0.3 * sin(t * 13.0));
	return vec4(d, glow, 1.0, torus < 0.0 ? 1.0 : 0.0);
}

// 11. An exhaust fan spinning behind its grille, lit from behind.
vec4 m_exhaust_fan(vec2 q, float t, float v, inout float g2) {
	float box = sd_box(q, vec2(0.85, 0.85));
	float frame = abs(box) - 0.07;
	float grille = max(sd_box(vec2(mod(q.x + 0.1, 0.2) - 0.1, q.y), vec2(0.014, 0.85)), box);
	vec2 s = polar_rep(rot(q, t * (2.5 + v * 2.0)), 5.0);
	float blades = max(sd_rbox(rot(s - vec2(0.38, 0.0), 0.4), vec2(0.3, 0.1), 0.06), length(q) - 0.72);
	float hub = length(q) - 0.1;
	float d = min(min(frame, grille), min(blades, hub));
	// The light behind it shows between the blades and the bars.
	float behind = glow_at(length(q), 0.6) * 0.5 * (0.8 + 0.2 * sin(t * 1.5)) * step(box, 0.0);
	float glow = behind * smoothstep(-0.02, 0.02, d) + glow_at(length(q) - 0.1, 0.03) * 0.3;
	return vec4(d, glow, 1.0, frame < 0.0 ? 1.0 : 0.0);
}

// 12. Bio pods: soft organic sacs breathing, their nuclei pulsing with light.
vec4 m_bio_pod(vec2 q, float t, float v, inout float g2) {
	if (v > 0.5) {
		q.y = -q.y; // hanging from above instead
	}
	float a = atan(q.y, q.x);
	float wob = 0.035 * sin(t * 1.3 + a * 3.0 + v * 6.0);
	float pod = length(q * vec2(1.0, 0.82)) - 0.52 + wob;
	float pod2 = length((q - vec2(0.45, 0.32)) * vec2(1.0, 0.85)) - 0.3 + wob;
	float pod3 = length(q - vec2(-0.42, 0.42)) - 0.24 - wob;
	float stalk = sd_seg(q, vec2(0.0, 0.45), vec2(0.0 + 0.05 * sin(t * 0.8), 1.15)) - 0.08;
	float d = smin(smin(pod, pod2, 0.15), smin(pod3, stalk, 0.12), 0.15);
	float beat = pow(0.5 + 0.5 * sin(t * 2.0 + v * 6.0), 2.0);
	float glow = glow_at(length(q - vec2(0.0, -0.05)) - 0.12, 0.09) * (0.35 + 0.75 * beat) + glow_at(length(q - vec2(0.45, 0.32)) - 0.06, 0.06) * (0.2 + 0.5 * beat);
	float veins = smoothstep(0.08, 0.0, abs(sin(q.x * 9.0 + sin(q.y * 7.0) * 1.5))) * step(d, 0.0);
	g2 = veins * (0.1 + 0.25 * beat);
	return vec4(d, glow, 0.85 + 0.25 * smoothstep(0.5, -0.4, q.y), 1.0);
}

// 13. A specimen tank: glowing fluid, bubbles rising, a creature floating in it.
vec4 m_specimen_tank(vec2 q, float t, float v, inout float g2) {
	float tank = sd_rbox(q - vec2(0.0, 0.05), vec2(0.36, 0.8), 0.2);
	float glass = abs(tank) - 0.018;
	float caps = min(sd_rbox(q - vec2(0.0, -0.82), vec2(0.44, 0.1), 0.04), sd_rbox(q - vec2(0.0, 0.92), vec2(0.46, 0.1), 0.04));
	float pipes = min(sd_box(q - vec2(-0.2, -1.1), vec2(0.04, 0.22)), sd_box(q - vec2(0.2, -1.1), vec2(0.04, 0.22)));
	float bob = 0.07 * sin(t * 0.8 + v * 6.0);
	vec2 c = q - vec2(0.0, -0.08 + bob);
	float dome = max(length(c * vec2(1.0, 1.35)) - 0.24, c.y - 0.05);
	float fangs = min(sd_tri(vec2(c.x - 0.1, 0.25 - c.y), vec2(0.035, 0.18)), sd_tri(vec2(c.x + 0.1, 0.25 - c.y), vec2(0.035, 0.18)));
	float creature = min(dome, max(fangs, -c.y));
	float d = min(min(glass, caps), min(pipes, creature));
	float inside = step(tank, 0.0);
	float fluid = inside * (0.18 + 0.05 * sin(q.y * 5.0 - t));
	float by = (q.y + t * 0.35) / 0.18;
	float id = floor(by);
	float bx = (env_hash(vec2(id, v * 9.0)) - 0.5) * 0.5;
	float bubble = length(vec2(q.x - bx, (fract(by) - 0.5) * 0.18)) - 0.012 - 0.012 * env_hash(vec2(id, 3.0));
	// The fluid and its bubbles in the accent color, the creature's nuclei in the light color.
	g2 = (fluid + inside * smoothstep(0.01, -0.01, bubble) * 0.6) * smoothstep(-0.02, 0.02, creature);
	float beat = 0.6 + 0.4 * sin(t * 2.5 + v * 3.0);
	float glow = (glow_at(length(c - vec2(-0.09, 0.0)) - 0.045, 0.03) + glow_at(length(c - vec2(0.09, 0.0)) - 0.045, 0.03) + glow_at(length(c - vec2(0.0, -0.1)) - 0.04, 0.03)) * beat * 0.8;
	return vec4(d, glow, creature < 0.0 ? 1.4 : 1.0, creature < 0.0 ? 1.0 : 0.0);
}

// 14. A data panel: columns of glowing blocks streaming down it.
vec4 m_data_stream(vec2 q, float t, float v, inout float g2) {
	float frame = abs(sd_rbox(q, vec2(0.45, 0.95), 0.04)) - 0.04;
	float inside = step(sd_box(q, vec2(0.41, 0.91)), 0.0);
	float cx = floor((q.x + 0.41) / 0.082);
	float lx = mod(q.x + 0.41, 0.082) - 0.041;
	float pace = 0.25 + env_hash(vec2(cx, v * 5.0)) * 0.5;
	float yy = q.y + t * pace + env_hash(vec2(cx + 3.0, v)) * 5.0;
	float row = floor(yy / 0.06);
	float ly = mod(yy, 0.06) - 0.03;
	float on = step(0.45, env_hash(vec2(cx, row)));
	float block = step(sd_box(vec2(lx, ly), vec2(0.026, 0.019)), 0.0);
	float head = fract(t * pace * 0.5 + env_hash(vec2(cx, 9.0))) * 2.2 - 1.1;
	float trail = clamp(1.0 - (head - q.y) / 0.9, 0.0, 1.0) * step(q.y, head);
	float glow = inside * block * on * (0.1 + 0.9 * trail) * 0.75;
	g2 = inside * smoothstep(0.02, 0.0, abs(q.y - (fract(t * 0.12 + v) * 1.9 - 0.95))) * 0.4;
	return vec4(frame, glow, 1.0, 0.0);
}

// 15. A security emitter sweeping its laser beam back and forth.
vec4 m_laser(vec2 q, float t, float v, inout float g2) {
	vec2 at = vec2(0.0, -0.9);
	float turret = min(sd_rbox(q - at, vec2(0.22, 0.1), 0.04), length(q - at - vec2(0.0, 0.1)) - 0.08);
	float a = 0.55 * sin(t * 0.7 + v * 6.0);
	vec2 dir = vec2(sin(a), cos(a));
	vec2 rel = q - at - vec2(0.0, 0.1);
	float along = dot(rel, dir);
	float side = abs(dot(rel, vec2(-dir.y, dir.x)));
	float reach = smoothstep(-0.02, 0.06, along) * smoothstep(2.4, 1.7, along);
	g2 = (glow_at(side - 0.004, 0.012) * 0.95 + glow_at(side, 0.07) * 0.15) * reach;
	float hit_x = at.x + tan(a) * 1.8;
	g2 += glow_at(length((q - vec2(hit_x, 0.95)) * vec2(0.5, 1.5)), 0.07) * 0.7;
	float glow = glow_at(length(q - at - vec2(0.0, 0.1)) - 0.04, 0.04) * 0.8;
	return vec4(turret, glow, 1.0, 0.0);
}

// 16. A warp portal: a ring of runes round a swirling vortex.
vec4 m_portal(vec2 q, float t, float v, inout float g2) {
	float rr = length(q);
	float a = atan(q.y, q.x);
	// The frame in twelve segments, turning slowly.
	float frame = max(sd_ring(q, 0.82, 0.08), 0.03 - abs(polar_rep(rot(q, t * 0.1), 12.0).y));
	float feet = min(sd_rbox(q - vec2(-0.55, 0.88), vec2(0.1, 0.16), 0.03), sd_rbox(q - vec2(0.55, 0.88), vec2(0.1, 0.16), 0.03));
	float d = min(frame, feet);
	float runes = step(0.55, env_hash(vec2(sector(q, 24.0), 4.0))) * smoothstep(0.02, 0.0, abs(rr - 0.82)) * (0.4 + 0.6 * (0.5 + 0.5 * sin(a * 3.0 - t * 2.0)));
	float swirl = 0.5 + 0.5 * sin(a * 4.0 + log(rr + 0.02) * 7.0 + t * 2.5);
	float inside = smoothstep(0.74, 0.66, rr);
	g2 = inside * (0.15 + 0.45 * swirl) * smoothstep(0.0, 0.5, rr + 0.1);
	float glow = runes * 0.9 + glow_at(rr, 0.14) * 0.9 * inside;
	return vec4(d, glow, 1.0, 1.0);
}

// 17. A crystal pylon floating and turning over its pedestal, a beam between them.
vec4 m_crystal(vec2 q, float t, float v, inout float g2) {
	float bob = 0.1 * sin(t * 0.9 + v * 6.0);
	vec2 c = q - vec2(0.0, bob);
	float turn = cos(t * 0.6 + v * 3.0);
	float k = 0.45 + 0.55 * abs(turn);
	float top = sd_tri(vec2(c.x, c.y + 0.75), vec2(0.36 * k, 0.75));
	float bottom = sd_tri(vec2(c.x, 0.5 - c.y), vec2(0.36 * k, 0.5));
	float crystal = min(top, bottom);
	float pedestal = sd_rbox(q - vec2(0.0, 0.95), vec2(0.26, 0.08), 0.03);
	float d = min(crystal, pedestal);
	float facet = c.x * sign(turn) > 0.0 ? 1.3 : 0.8;
	float beat = 0.7 + 0.3 * sin(t * 1.7 + v * 4.0);
	float glow = (glow_at(length(c) - 0.05, 0.05) * 0.8 + halo(length(c), 0.2) * 0.4) * beat + glow_at(abs(crystal), 0.03) * 0.3;
	g2 = smoothstep(0.03, 0.0, abs(q.x)) * step(0.55 + bob, q.y) * step(q.y, 0.88) * 0.6 * beat;
	return vec4(d, glow, crystal < 0.0 ? facet : 1.0, crystal < 0.0 ? 1.0 : 0.0);
}

// 18. A press hammer rising slowly, then slamming down on its anvil in a flash.
vec4 m_press(vec2 q, float t, float v, inout float g2) {
	float cycle = fract(t * 0.35 + v);
	float lift = cycle < 0.75 ? -0.6 * smoothstep(0.0, 0.75, cycle) : (cycle < 0.82 ? mix(-0.6, 0.0, pow((cycle - 0.75) / 0.07, 2.0)) : 0.0);
	float hammer = sd_rbox(q - vec2(0.0, 0.25 + lift), vec2(0.42, 0.22), 0.04);
	float shaft = sd_box(q - vec2(0.0, -0.45 + lift), vec2(0.08, 0.5));
	float housing = sd_rbox(q - vec2(0.0, -0.95), vec2(0.6, 0.12), 0.04);
	float columns = min(sd_box(q - vec2(-0.66, 0.0), vec2(0.06, 1.0)), sd_box(q - vec2(0.66, 0.0), vec2(0.06, 1.0)));
	float anvil = sd_rbox(q - vec2(0.0, 0.82), vec2(0.5, 0.12), 0.04);
	float d = min(min(hammer, shaft), min(min(housing, columns), anvil));
	float since = cycle - 0.82;
	float flash = since > 0.0 ? exp(-since * 25.0) : 0.0;
	float glow = halo(length((q - vec2(0.0, 0.68)) * vec2(0.45, 1.6)), 0.16) * flash * 1.3;
	float lamp = length(q - vec2(0.45, -0.95)) - 0.03;
	g2 = glow_at(lamp, 0.04) * step(0.5, fract(t * 1.2)) * 0.8;
	return vec4(d, glow, 1.0, hammer < 0.0 ? 1.0 : 0.0);
}

// 19. A cargo lift: a cage riding up and down its rails, its lamps blinking.
vec4 m_cargo_lift(vec2 q, float t, float v, inout float g2) {
	float rails = min(sd_box(q - vec2(-0.48, 0.0), vec2(0.035, 2.4)), sd_box(q - vec2(0.48, 0.0), vec2(0.035, 2.4)));
	float y = 0.65 * sin(t * 0.35 + v * 6.0);
	vec2 c = q - vec2(0.0, y);
	float cage = abs(sd_box(c, vec2(0.4, 0.28))) - 0.035;
	float braces = min(sd_seg(c, vec2(-0.4, -0.28), vec2(0.4, 0.28)), sd_seg(c, vec2(0.4, -0.28), vec2(-0.4, 0.28))) - 0.014;
	float floor_bar = sd_box(c - vec2(0.0, 0.28), vec2(0.44, 0.05));
	float cables = min(sd_seg(q, vec2(-0.15, y - 0.28), vec2(-0.15, -2.4)), sd_seg(q, vec2(0.15, y - 0.28), vec2(0.15, -2.4))) - 0.012;
	float weight = sd_rbox(q - vec2(0.72, -y * 0.8), vec2(0.1, 0.18), 0.03);
	float d = min(min(rails, cage), min(min(braces, floor_bar), min(cables, weight)));
	float blink = step(0.5, fract(t * 0.9 + v));
	float glow = glow_at(length(c - vec2(-0.3, -0.2)) - 0.03, 0.05) * (0.3 + 0.7 * blink) + glow_at(length(c - vec2(0.3, -0.2)) - 0.03, 0.05) * (1.0 - 0.7 * blink);
	g2 = halo(length(c), 0.28) * 0.14;
	return vec4(d, glow, 1.0, cage < 0.0 || floor_bar < 0.0 ? 1.0 : 0.0);
}

// Each machine's box (x0, x1, y0, y1 in its space), its glow included.
vec4 machine_bounds(float v) {
	switch (kind) {
		case 0: return vec4(-1.0, 1.0, -1.0, 1.0);
		case 1: return vec4(-1.0, 1.0, -1.0, 1.0);
		case 2: return vec4(-0.96, 0.96, -0.96, 0.96);
		case 3: return vec4(-0.45, 0.45, -0.95, 1.02);
		case 4: return v > 0.5 ? vec4(-0.45, 0.45, -2.45, 2.45) : vec4(-2.45, 2.45, -0.45, 0.45);
		case 5: return vec4(-0.72, 0.72, -0.62, 1.05);
		case 6: return vec4(-0.62, 0.62, -0.78, 1.0);
		case 7: return vec4(-1.32, 1.32, -1.0, 1.0);
		case 8: return vec4(-1.65, 1.65, -0.95, 1.02);
		case 9: return vec4(-0.5, 0.5, -1.05, 1.5);
		case 10: return vec4(-1.05, 1.05, -1.25, 1.02);
		case 11: return vec4(-0.95, 0.95, -0.95, 0.95);
		case 12: return vec4(-0.78, 0.82, -1.22, 1.22);
		case 13: return vec4(-0.52, 0.52, -1.35, 1.05);
		case 14: return vec4(-0.52, 0.52, -1.0, 1.0);
		case 15: return vec4(-1.5, 1.5, -1.02, 1.62);
		case 16: return vec4(-0.95, 0.95, -0.95, 1.06);
		case 17: return vec4(-0.46, 0.46, -0.98, 1.06);
		case 18: return vec4(-0.76, 0.76, -1.1, 1.02);
	}
	return vec4(-0.56, 0.86, -2.42, 2.42);
}

bool machine_rope() {
	return false;
}

vec4 machine(vec2 q, float t, float v, inout float g2) {
	switch (kind) {
		case 0: return m_turbine(q, t, v, g2);
		case 1: return m_reactor(q, t, v, g2);
		case 2: return m_gyro(q, t, v, g2);
		case 3: return m_piston(q, t, v, g2);
		case 4: return m_conduit(q, t, v, g2);
		case 5: return m_radar(q, t, v, g2);
		case 6: return m_hologram(q, t, v, g2);
		case 7: return m_planet(q, t, v, g2);
		case 8: return m_robot_arm(q, t, v, g2);
		case 9: return m_drill(q, t, v, g2);
		case 10: return m_tesla(q, t, v, g2);
		case 11: return m_exhaust_fan(q, t, v, g2);
		case 12: return m_bio_pod(q, t, v, g2);
		case 13: return m_specimen_tank(q, t, v, g2);
		case 14: return m_data_stream(q, t, v, g2);
		case 15: return m_laser(q, t, v, g2);
		case 16: return m_portal(q, t, v, g2);
		case 17: return m_crystal(q, t, v, g2);
		case 18: return m_press(q, t, v, g2);
	}
	return m_cargo_lift(q, t, v, g2);
}

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/machinery_draw.gdshaderinc"
