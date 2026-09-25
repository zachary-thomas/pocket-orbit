// Stylised ocean: a see-through sphere at sea level with gentle moving
// ripples, a fresnel tint and a soft sun glint.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_disabled;

#include "res://shaders/planet_lighting.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.42, 0.84, 0.86);
uniform vec3 deep_color : source_color = vec3(0.16, 0.46, 0.74);
uniform float clarity = 0.72;
uniform float ripple_strength = 0.05;

varying vec3 world_pos;
varying float sun_height;
varying float cloud_shade;

void vertex() {
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
	ALBEDO = albedo;
	ALPHA = mix(clarity, 1.0, fresnel);
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
