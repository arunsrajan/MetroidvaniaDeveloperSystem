shader_type canvas_item;
// Parts of an effect that are not its rectangles (a lightning bolt's lines): drawn added, and
// only in the cave's open air (see env_cave and MDSEnvironmentEffect.line_material).
render_mode blend_add, unshaded;

#include "res://addons/MetroidvaniaDeveloperSystem/shaders/environment/mds_env.gdshaderinc"

void vertex() {
	px = VERTEX - rect_origin;
}

void fragment() {
	COLOR.a *= env_cave(px);
}
