// Background of space: deep navy, procedural stars and the sun's disc.
// The atmosphere shell is drawn on top of this; under a daytime sky the stars
// are faded out here as well so none peek through the thin blue.
shader_type sky;

global uniform vec3 sun_direction;

uniform vec3 space_color : source_color = vec3(0.03, 0.04, 0.10);
uniform vec3 planet_center = vec3(0.0);
uniform float atmosphere_radius = 163.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Divide space into cells; a few cells hold one star at a random spot.
float stars(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 spot = cell + vec3(hash13(cell + 17.1), hash13(cell + 43.7), hash13(cell + 91.3)) * 0.6 + 0.2;
	float d = length(p - spot);
	return (1.0 - smoothstep(0.0, 0.14, d)) * (h - threshold) / (1.0 - threshold);
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 color = space_color;
	float s = stars(dir, 240.0, 0.982) * 1.4 + stars(dir, 90.0, 0.992) * 2.5;

	vec3 camera = POSITION - planet_center;
	float inside_air = 1.0 - smoothstep(atmosphere_radius, atmosphere_radius * 1.25, length(camera));
	float day_here = smoothstep(-0.2, 0.15, dot(normalize(camera), sun_direction));
	s *= 1.0 - inside_air * day_here;

	float to_sun = dot(dir, sun_direction);
	color += vec3(1.0, 0.92, 0.72) * (smoothstep(0.9993, 0.9997, to_sun) * 8.0 + pow(max(to_sun, 0.0), 400.0) * 0.8);
	COLOR = color + vec3(s);
}
