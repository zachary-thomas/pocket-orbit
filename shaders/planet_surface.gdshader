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
// Close-up props dissolve where they block the view of the focus (the player).
uniform bool fade_occluders = false;
uniform vec3 focus_position;
// Radius around the camera-to-focus line that is fully cleared, and the soft
// edge beyond it, in metres.
uniform float fade_radius = 1.1;
uniform float fade_edge = 0.9;
// Terrain and plants follow the seasons: leaves and grass turn golden in
// autumn, and snow settles on everything facing up in winter, more so away
// from the equator. Off for characters and items.
global uniform float season_phase; // north: 0 spring equinox, .25 midsummer, .5 autumn, .75 midwinter
uniform bool seasonal = false;

varying vec3 world_pos;
varying float sun_height;
varying float cloud_shade;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 4x4 ordered dither threshold in [0, 1).
float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int index = i.x + i.y * 4;
	const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[index] + 0.5) / 16.0;
}

vec3 seasonal_tint(vec3 albedo, vec3 up, vec3 normal) {
	float phase = up.y < 0.0 ? fract(season_phase + 0.5) : season_phase;
	float away = smoothstep(0.25, 0.6, abs(up.y));
	float green = clamp((albedo.g - max(albedo.r, albedo.b)) * 6.0, 0.0, 1.0);
	float autumn = away * smoothstep(0.47, 0.56, phase) * (1.0 - smoothstep(0.72, 0.8, phase));
	vec3 fall = vec3(0.96, 0.62, 0.3) * (0.6 + dot(albedo, vec3(0.3)));
	albedo = mix(albedo, fall, autumn * green * 0.6);
	float winter = away * smoothstep(0.74, 0.8, phase) * (1.0 - smoothstep(0.95, 1.0, phase));
	float snow = winter * smoothstep(0.55, 0.85, dot(normal, up)) * smoothstep(0.3, 0.65, abs(up.y));
	return mix(albedo, vec3(0.94, 0.96, 1.0), snow * 0.85);
}

void fragment() {
	if (fade_occluders) {
		vec3 cam = CAMERA_POSITION_WORLD;
		vec3 to_focus = focus_position - cam;
		float span = length(to_focus);
		vec3 dir = to_focus / max(span, 0.001);
		float along = dot(world_pos - cam, dir);
		if (along > 0.0 && along < span - 0.6) {
			float off_line = length(world_pos - cam - dir * along);
			float fade = 1.0 - smoothstep(fade_radius, fade_radius + fade_edge, off_line);
			// Ease in near the focus so props right beside the player stay solid.
			fade *= (1.0 - smoothstep(span - 2.0, span - 0.6, along)) * 0.85;
			if (fade > bayer4(FRAGCOORD.xy)) {
				discard;
			}
		}
	}
	// Vertex colour carries baked ambient occlusion on models and the blended
	// ground colour on terrain.
	vec3 albedo = texture(palette, UV).rgb * COLOR.rgb;
	vec3 from_center = world_pos - planet_center;
	if (seasonal && UV.y < GLOW_ROW_START) {
		vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		albedo = seasonal_tint(albedo, normalize(from_center), world_normal);
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
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
