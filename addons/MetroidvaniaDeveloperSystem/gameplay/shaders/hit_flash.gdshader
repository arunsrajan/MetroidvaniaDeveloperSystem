shader_type canvas_item;
// The white flash of a body that was hit (MDSHealth sets flash from 1 down to 0).

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 c = COLOR;
	COLOR = vec4(mix(c.rgb, flash_color.rgb, flash * flash_color.a), c.a);
}
