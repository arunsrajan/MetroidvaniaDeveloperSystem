// The machinery backgrounds' drawing (see machinery.gdshaderinc): included after the shader's
// `machine()`. The machines are drawn far to near over the backdrop, each out of focus (its edges
// softened by `blur`, more the nearer or the farther it is) and faded into the haze with its
// depth, its lights added over it.

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	// In the room, fixed in the world (or, far away, moved by `offset` with the camera).
	vec2 local = px + rect_origin - offset;
	vec2 uv = (local - layout_rect.xy) / max(layout_rect.zw, vec2(1.0));
	vec2 p = local / max(unit, 1.0);
	float t = TIME * speed + seed * 7.0;
	vec3 haze_col = mix(back_top.rgb, back_bottom.rgb, clamp(uv.y, 0.0, 1.0));
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (backdrop) {
		col = machinery_backdrop(p, uv, t, haze_col);
		a = 1.0;
	}
	bool rope = machine_rope();
	for (int i = 0; i < MAX_MACHINES; i++) {
		if (i >= count) {
			break;
		}
		vec4 A = inst_a[i];
		vec4 B = inst_b[i];
		float size = max(A.z, 0.001);
		vec2 q = (p - A.xy) / size;
		q.x *= B.w;
		// Outside its box: nothing of it here (its glow included), but for the rope or chain it
		// may hang from, straight above it.
		vec4 bb = machine_bounds(B.z);
		if (q.x < bb.x || q.x > bb.y || q.y > bb.w || (q.y < bb.z && !(rope && abs(q.x) < 0.1))) {
			continue;
		}
		float g2 = 0.0;
		vec4 m = machine(q, t * B.y + B.x, B.z, g2);
		// Out of focus: the nearest and the farthest the most.
		float dof = 0.3 + 1.6 * abs(A.w - 0.35);
		float soft = (0.0015 + blur * 0.011 * dof) / size;
		float cov = 1.0 - smoothstep(-soft, soft, m.x);
		vec3 body = mix(metal_color.rgb, accent_color.rgb, clamp(m.w, 0.0, 1.0)) * m.z;
		body = mix(body, haze_col, clamp(A.w * haze, 0.0, 0.92));
		col = col * (1.0 - cov) + body * cov;
		a = a * (1.0 - cov) + cov;
		float lit = (1.0 - A.w * 0.55) * brightness;
		// The edge catches the light.
		float edge = cov * (1.0 - smoothstep(0.0, 0.05 + soft, -m.x));
		col += mix(light_color.rgb, vec3(1.0), 0.35) * edge * rim_light * 0.2 * lit * (1.0 - A.w * haze * 0.6);
		col += (light_color.rgb * m.y + accent_color.rgb * g2) * lit;
	}
	if (backdrop) {
		// The vignette darkens the screen's corners (it moves nothing).
		float vig = smoothstep(0.35, 1.0, length((SCREEN_UV - 0.5) * vec2(1.0, 0.9)) * 1.45);
		col *= 1.0 - vignette * vig;
		col += (env_hash(FRAGCOORD.xy + floor(TIME * 24.0) * vec2(17.0, 31.0)) - 0.5) * (0.004 + grain * 0.04);
	}
	COLOR = vec4(max(col, vec3(0.0)), clamp(a, 0.0, 1.0)) * intensity * env_edge(px);
}
