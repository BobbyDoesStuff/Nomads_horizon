shader_type canvas_item;
// Water for the map's transparent edges: directional waves + specular glint + shoreline foam.
// All procedural — one fragment shader, no extra textures, runs on the GPU.

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.5) {
		float t = TIME;

		// Two layers of anisotropic (stretched) noise -> directional wave streaks,
		// drifting diagonally like wind pushing the surface.
		vec2 q1 = vec2(UV.x * 45.0 + t * 1.2, UV.y * 150.0 - t * 0.9);
		vec2 q2 = vec2(UV.x * 75.0 - t * 0.9, UV.y * 220.0 + t * 0.7);
		float n1 = value_noise(q1);
		float n2 = value_noise(q2);
		float n = n1 * 0.6 + n2 * 0.4;

		// Fake normal from the first layer -> moving sun glint.
		float e = 0.02;
		float hx = value_noise(q1 + vec2(e, 0.0));
		float hy = value_noise(q1 + vec2(0.0, e));
		vec3 nrm = normalize(vec3(n1 - hx, n1 - hy, 1.0));
		vec3 light = normalize(vec3(0.55, -0.35, 0.75));
		float spec = pow(max(dot(nrm, light), 0.0), 20.0);

		vec3 deep = vec3(0.03, 0.13, 0.36);
		vec3 shallow = vec3(0.12, 0.38, 0.68);
		vec3 water = mix(deep, shallow, n);
		water += vec3(0.85, 0.92, 1.0) * spec * 0.7;

		// Shoreline foam where water meets land (neighbour alpha).
		float a0 = texture(TEXTURE, UV + vec2(0.0015, 0.0)).a;
		float a1 = texture(TEXTURE, UV - vec2(0.0015, 0.0)).a;
		float a2 = texture(TEXTURE, UV + vec2(0.0, 0.0015)).a;
		float a3 = texture(TEXTURE, UV - vec2(0.0, 0.0015)).a;
		float shore = step(0.5, max(max(a0, a1), max(a2, a3)));
		float foam = shore * (0.55 + 0.45 * sin(TIME * 2.5 + n * 8.0));
		water = mix(water, vec3(0.82, 0.90, 0.92), foam * 0.55);

		COLOR = vec4(water, 1.0);
	} else {
		COLOR = tex;
	}
}
