// Stylised ocean: a see-through sphere at sea level with gentle moving
// ripples, a fresnel tint and a soft sun glint.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_disabled;

#include "res://shaders/planet_lighting.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.42, 0.84, 0.86);
uniform vec3 deep_color : source_color = vec3(0.16, 0.46, 0.74);
uniform float clarity = 0.72;
uniform float ripple_strength = 0.05;
// The tide (see Tides): the sea rises in a bulge under the moon and on the
// far side, and drops in between.
global uniform vec3 moon_direction;
global uniform float tide_amplitude;
// Foam where the water meets the shore, from how much water is in front of
// whatever is behind it.
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float foam_width = 0.55;

varying vec3 world_pos;
varying float sun_height;
varying float cloud_shade;

void vertex() {
	vec2 flat_dir = VERTEX.xz;
	float c = dot(flat_dir / max(length(flat_dir), 1e-4), normalize(moon_direction.xz + vec2(1e-5)));
	VERTEX += normalize(VERTEX) * tide_amplitude * (2.0 * c * c - 1.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 from_center = world_pos - planet_center;
	vec3 up = normalize(from_center);
	// A few moving sine waves in 3D. They only bend the normal; the surface
	// itself stays a smooth sphere.
	vec3 p = from_center;
	vec3 wave = vec3(
		sin(p.y * 0.37 + TIME * 0.9) + sin(p.z * 0.23 - TIME * 0.7),
		sin(p.z * 0.41 + TIME * 1.1) + sin(p.x * 0.29 + TIME * 0.6),
		sin(p.x * 0.33 - TIME * 0.8) + sin(p.y * 0.27 + TIME * 1.2));
	vec3 bent = normalize(up + (wave - up * dot(wave, up)) * ripple_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.0);
	vec3 albedo = mix(shallow_color, deep_color, 0.35 + 0.65 * fresnel);
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float thickness = -behind.z / behind.w + VERTEX.z;
	float foam = 1.0 - smoothstep(0.0, foam_width, thickness);
	// Bands washing in and out, broken up along the shore.
	float bands = 0.5 + 0.5 * sin(thickness * 22.0 - TIME * 2.2 + sin(p.x * 0.8 + p.z * 0.6) * 2.0);
	foam *= mix(0.55, 1.0, bands);
	albedo = mix(albedo, vec3(0.97, 0.99, 1.0), foam * 0.85);
	ALBEDO = albedo;
	ALPHA = max(mix(clarity, 1.0, fresnel), foam * 0.9);
	sun_height = local_sun_height(from_center);
	EMISSION = albedo * sky_fill(sun_height);
	cloud_shade = 1.0 - cloud_shadow_strength * cloud_cover(from_center);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float amount = smoothstep(-0.1, 0.6, ndl) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		amount *= sun_visibility(sun_height) * cloud_shade;
	}
	DIFFUSE_LIGHT += amount * LIGHT_COLOR / PI;
	vec3 half_vector = normalize(LIGHT + VIEW);
	float glint = pow(max(dot(NORMAL, half_vector), 0.0), 120.0);
	SPECULAR_LIGHT += glint * amount * LIGHT_COLOR * 0.35;
}
