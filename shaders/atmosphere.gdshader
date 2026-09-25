// Atmosphere shell: a sphere a little bigger than the planet.
//
// Only the inside (back faces) of the sphere is drawn, which works from both
// the ground and from orbit: either way those faces sit behind everything the
// air could cover. For each pixel the view ray is traced through the shell in
// a few steps (stopping at the planet). The air thins out exponentially with
// height, so seen from space only rays grazing the planet cross much of it,
// which gives a thin glowing rim. Each step is coloured by where the sun is
// at that point:
// - day side: blue, paler toward the horizon where the path is longer
// - along the day-night line: orange and pink, brightest toward the sun
// - night side: nothing, so the stars show
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

global uniform vec3 sun_direction;

uniform float planet_radius = 134.5;
uniform float atmosphere_radius = 163.0;
// Height (metres) over which the air thins to about a third.
uniform float scale_height = 4.0;
// How opaque one metre of sea-level air is.
uniform float density = 0.45;
const int STEPS = 8;
uniform vec3 day_color : source_color = vec3(0.42, 0.66, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.89, 1.0);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.56, 0.36);
uniform vec3 dusk_pink : source_color = vec3(0.93, 0.52, 0.74);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Distances along the ray to where it enters and leaves a sphere at the
// origin (x < 0 means the ray started inside). (-1, -1) if it misses.
vec2 ray_sphere(vec3 origin, vec3 dir, float radius) {
	float b = dot(origin, dir);
	float c = dot(origin, origin) - radius * radius;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(-1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

void fragment() {
	vec3 center = NODE_POSITION_WORLD;
	vec3 origin = CAMERA_POSITION_WORLD - center;
	vec3 dir = normalize(world_pos - CAMERA_POSITION_WORLD);

	vec2 through_air = ray_sphere(origin, dir, atmosphere_radius);
	if (through_air.y <= 0.0) {
		discard;
	}
	float start = max(through_air.x, 0.0);
	float end = through_air.y;
	vec2 through_planet = ray_sphere(origin, dir, planet_radius);
	if (through_planet.x > 0.0) {
		end = min(end, through_planet.x);
	}
	float step_length = max(end - start, 0.0) / float(STEPS);
	float toward_sun = max(dot(dir, sun_direction), 0.0);
	vec3 dusk_tint = mix(dusk_pink, sunset_color, toward_sun * toward_sun) * (0.55 + 0.9 * pow(toward_sun, 6.0));

	float optical_depth = 0.0;
	vec3 glow = vec3(0.0);
	for (int i = 0; i < STEPS; i++) {
		vec3 p = origin + dir * (start + (float(i) + 0.5) * step_length);
		float r = length(p);
		float air = exp(-max(r - planet_radius, 0.0) / scale_height) * step_length;
		float sun_height = dot(p / r, sun_direction);
		float day = smoothstep(-0.12, 0.25, sun_height);
		float dusk = exp(-pow((sun_height - 0.02) / 0.13, 2.0));
		vec3 sky = mix(day_color, horizon_color, clamp(optical_depth * density * 0.25, 0.0, 1.0));
		glow += air * (sky * day + dusk_tint * dusk);
		optical_depth += air * (day + dusk * 0.9 + 0.02);
	}
	float alpha = 1.0 - exp(-optical_depth * density);
	vec3 color = glow / max(optical_depth, 1e-4);
	// Bright halo around the sun when looking through the air.
	color += vec3(1.0, 0.92, 0.75) * pow(toward_sun, 90.0) * 1.5;
	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
