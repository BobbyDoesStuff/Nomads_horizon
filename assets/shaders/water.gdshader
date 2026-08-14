shader_type canvas_item;
// Water for the map's transparent edges: layered fbm noise + shoreline foam.

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.3, 7.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.5) {
		float t = TIME;
		float n = fbm(UV * 50.0 + vec2(t * 0.05, -t * 0.04));
		float n2 = fbm(UV * 100.0 - vec2(t * 0.07, t * 0.05));
		float v = clamp(n * 0.65 + n2 * 0.35, 0.0, 1.0);

		vec3 deep = vec3(0.04, 0.16, 0.40);
		vec3 shallow = vec3(0.16, 0.46, 0.76);
		vec3 water = mix(deep, shallow, v);

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
