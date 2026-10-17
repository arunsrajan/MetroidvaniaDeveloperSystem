shader_type canvas_item;
// Rooms shown together (the Room view's several rooms, the Full view): the tile layers of a room
// whose rectangles leave notches in its box draw only inside its rectangles. Generate cave fills
// the whole box with rock, and in the notches are other rooms.

// The room's rectangles, x, y, width, height in its scene's coordinates.
uniform vec4 rects[16];
uniform int rect_count = 0;
// Where the room's (0, 0) is on the canvas, and the view's zoom.
uniform vec2 origin = vec2(0.0);
uniform float zoom = 1.0;

varying vec2 canvas_pos;

void vertex() {
	canvas_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = (canvas_pos - origin) / max(zoom, 0.0001);
	bool inside = false;
	for (int i = 0; i < 16; i++) {
		if (i >= rect_count) {
			break;
		}
		vec4 r = rects[i];
		if (p.x >= r.x && p.y >= r.y && p.x < r.x + r.z && p.y < r.y + r.w) {
			inside = true;
		}
	}
	if (!inside) {
		discard;
	}
}
