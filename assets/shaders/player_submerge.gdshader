shader_type canvas_item;
// Hides the bottom of the sprite as the player submerges in water.
// Uses local vertex position (not UV) so it works with AtlasTexture frames.
// The water line tilts by `water_slope` so diagonal facings cut at ~20°.

uniform float submersion : hint_range(0.0, 1.0) = 0.0;
uniform float water_slope : hint_range(-1.0, 1.0) = 0.0;

varying float local_x;
varying float local_y;

void vertex() {
	local_x = VERTEX.x;
	local_y = VERTEX.y;
}

void fragment() {
	float water_line = 200.0 - 430.0 * submersion;
	// Fully hidden once submerged, so the tilted line can't leave a top sliver.
	if (submersion >= 1.0 || local_y - water_slope * local_x > water_line) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
