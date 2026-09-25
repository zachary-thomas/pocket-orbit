// Lighting shared by everything that sits on the planet (terrain, props,
// characters, water).
//
// The planet is lit by one directional sun, so we can't use the renderer's
// ambient light: it is one colour for the whole scene, but here one side of
// the planet is at noon while the other is at midnight. Instead each fragment
// works out its own local time of day from the angle between "up" (away from
// the planet centre) and the sun, and adds a matching sky fill light itself.

global uniform vec3 sun_direction;   // unit vector toward the sun
global uniform float cloud_rotation; // radians the cloud layer has turned around +Y

uniform vec3 planet_center = vec3(0.0);
uniform sampler2D cloud_shadow_map : hint_default_black, filter_linear, repeat_enable;
uniform float cloud_radius = 152.0;
uniform float cloud_shadow_strength = 0.4;

uniform vec3 day_fill : source_color = vec3(0.60, 0.70, 0.92);
uniform vec3 night_fill : source_color = vec3(0.16, 0.20, 0.42);
uniform vec3 dusk_fill : source_color = vec3(0.95, 0.55, 0.60);
uniform float fill_strength = 0.38;

// Sun height at this spot: 1 = overhead, 0 = on the horizon, < 0 = night.
float local_sun_height(vec3 from_center) {
	return dot(normalize(from_center), sun_direction);
}

float daylight(float sun_height) {
	return smoothstep(-0.18, 0.22, sun_height);
}

float dusk_band(float sun_height) {
	return exp(-pow(sun_height / 0.16, 2.0));
}

// Soft light from the sky: blue by day, deep blue at night, warm at dusk.
vec3 sky_fill(float sun_height) {
	vec3 fill = mix(night_fill * 0.8, day_fill, daylight(sun_height));
	fill += dusk_fill * dusk_band(sun_height) * 0.35;
	return fill * fill_strength;
}

vec3 rotate_y(vec3 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}

// How much the cloud layer shades this point (0 = clear, 1 = fully covered).
// Walk from the point toward the sun until reaching the cloud shell, undo the
// layer's rotation, and look the spot up in the equirectangular coverage map
// the CloudLayer baked. Much cheaper on phones than real shadow casting.
float cloud_cover(vec3 from_center) {
	float r = length(from_center);
	vec3 up = from_center / r;
	float h = max(dot(up, sun_direction), 0.08);
	vec3 q = from_center + sun_direction * max(cloud_radius - r, 0.0) / h;
	vec3 d = rotate_y(normalize(q), -cloud_rotation);
	vec2 uv = vec2(atan(d.z, d.x) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	return texture(cloud_shadow_map, uv).r;
}

// Direct sunlight fades out as the sun sets, even on walls that face it, so
// the night side stays dark.
float sun_visibility(float sun_height) {
	return smoothstep(-0.04, 0.06, sun_height);
}
