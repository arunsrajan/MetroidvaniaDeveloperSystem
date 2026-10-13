// A picture with some of its colors cut out (MDSDrawing): the paper around a drawing, or the
// colors another layer of the drawing shows.
//
// palette lists the drawing's colors: rgb the color, a 1 when it stays and 0 when it is cut. Each
// pixel goes with the nearest listed color, so the anti-aliased edge between a kept color and a
// cut one fades out over the blend instead of leaving a fringe. With no kept color listed, a pixel
// is cut only within keep_distance of a cut color (a chroma key).
shader_type canvas_item;

const int MAX_COLORS = 16;

uniform vec4 palette[MAX_COLORS];
uniform int palette_size = 0;
// 0: a hard cut on the halfway line between two colors; 1: a soft one across the blend.
uniform float softness : hint_range(0.0, 1.0) = 0.35;
uniform float keep_distance = 0.2;

void fragment() {
	vec4 c = COLOR;
	if (palette_size > 0) {
		vec3 rgb = texture(TEXTURE, UV).rgb;
		float keep_d = keep_distance;
		float cut_d = 10.0;
		bool any_kept = false;
		for (int i = 0; i < MAX_COLORS; i++) {
			if (i >= palette_size) {
				break;
			}
			float d = distance(rgb, palette[i].rgb);
			if (palette[i].a > 0.5) {
				keep_d = any_kept ? min(keep_d, d) : d;
				any_kept = true;
			} else {
				cut_d = min(cut_d, d);
			}
		}
		float band = max(softness * 0.25, 0.002);
		c.a *= clamp((cut_d - keep_d) / band + 0.5, 0.0, 1.0);
	}
	COLOR = c;
}
