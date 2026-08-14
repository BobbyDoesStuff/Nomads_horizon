shader_type canvas_item;
// Hides the bottom of the sprite as the player submerges in water.
// Uses the local vertex Y (not UV) because the sprite uses AtlasTexture
// frames, whose UV is relative to the full sheet rather than the frame.

uniform float submersion : hint_range(0.0, 1.0) = 0.0;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	// Frame is 160px tall and centered: top = -80, bottom = +80.
	float water_line = 80.0 - 160.0 * submersion;
	if (local_y > water_line) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
