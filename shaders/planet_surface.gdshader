// Shared material for every low-poly model: terrain, props, characters,
// clouds. Colour comes from the palette texture (UVs point at a swatch)
// times the vertex colour.
shader_type spatial;
render_mode specular_disabled;

#include "res://shaders/planet_lighting.gdshaderinc"

uniform sampler2D palette : source_color, filter_nearest;
uniform bool receive_cloud_shadow = true;
// Swatches in the palette's bottom row glow at night (windows, lamps).
uniform float glow_energy = 2.4;
const float GLOW_ROW_START = 15.0 / 16.0;

varying vec3 world_pos;
varying float sun_height;
varying float cloud_shade;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Vertex colour carries baked ambient occlusion on models and the blended
	// ground colour on terrain.
	vec3 albedo = texture(palette, UV).rgb * COLOR.rgb;
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	vec3 from_center = world_pos - planet_center;
	sun_height = local_sun_height(from_center);
	EMISSION = albedo * sky_fill(sun_height);
	cloud_shade = 1.0;
	if (receive_cloud_shadow) {
		cloud_shade = 1.0 - cloud_shadow_strength * cloud_cover(from_center);
	}
	if (UV.y > GLOW_ROW_START) {
		EMISSION += albedo * glow_energy * mix(1.0, 0.25, daylight(sun_height));
	}
}

void light() {
	// Slightly wrapped diffuse: softer than plain Lambert, for the flat,
	// gently shaded low-poly look.
	float ndl = dot(NORMAL, LIGHT);
	float amount = smoothstep(-0.1, 0.6, ndl) * ATTENUATION;
	if (LIGHT_IS_DIRECTIONAL) {
		amount *= sun_visibility(sun_height) * cloud_shade;
	}
	DIFFUSE_LIGHT += amount * LIGHT_COLOR / PI;
}
