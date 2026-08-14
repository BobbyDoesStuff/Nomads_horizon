shader_type canvas_item;
// Static blue for the transparent water areas, sized for the minimap.

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.5) {
		COLOR = vec4(0.12, 0.35, 0.6, 1.0);
	} else {
		COLOR = tex;
	}
}
