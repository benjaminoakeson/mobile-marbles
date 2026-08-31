shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A storm wrapped round a ball, seen from outside it.
//
// Weather on a spinning world does not move as one piece: the belts near the
// equator run faster than the ones near the poles. That difference is the whole
// design here -- the sample point is turned about the axis by an angle that
// depends on how far up it is, so the bands shear past one another and never
// settle into a pattern.
//
// The noise is then read through a space squashed ALONG the axis, which stretches
// what would be blobs into belts, and a spiral pull is put in around one point so
// the marble has an eye with the belts wound into it.
//
// Lightning is a fixed number of slots a second: most stay dark, and the ones
// that do not light a patch of cloud and fall away over the rest of the slot.

group_uniforms Cloud;
uniform vec4 cloud_colour : source_color = vec4(0.78, 0.8, 0.86, 1.0);
uniform vec4 dark_colour : source_color = vec4(0.17, 0.19, 0.25, 1.0);
// How many belts are wrapped round the marble.
uniform float band_stretch : hint_range(1.0, 12.0) = 5.0;
uniform float band_scale : hint_range(0.5, 8.0) = 2.4;
// How much the belts are churned up within themselves.
uniform float turbulence : hint_range(0.0, 2.0) = 0.5;

group_uniforms Spin;
uniform vec3 storm_axis = vec3(0.15, 1.0, 0.1);
uniform float shear_speed : hint_range(0.0, 0.5) = 0.05;
// Where the eye sits, and how hard it winds the belts in.
uniform vec3 eye_axis = vec3(0.4, 0.5, 0.75);
uniform float eye_pull : hint_range(0.0, 4.0) = 1.6;

group_uniforms Lightning;
uniform vec4 flash_colour : source_color = vec4(0.85, 0.92, 1.0, 1.0);
// Slots a second. Most of them stay dark.
uniform float flash_rate : hint_range(0.2, 8.0) = 2.0;
uniform float flash_chance : hint_range(0.0, 1.0) = 0.45;
uniform float flash_size : hint_range(0.05, 1.0) = 0.45;
uniform float flash_strength : hint_range(0.0, 6.0) = 2.5;

varying vec3 surface_direction;


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 axis = normalize(storm_axis);

	// Belts near the equator run fastest.
	float lat = dot(d, axis);
	float speed = shear_speed * (1.0 - abs(lat) * 0.8);
	vec3 rolled = twist(d, axis, TIME * speed * TAU);

	// Wind the belts into the eye: the closer to it, the further round they go.
	vec3 eye = normalize(eye_axis);
	float to_eye = acos(clamp(dot(rolled, eye), -1.0, 1.0));
	rolled = twist(rolled, eye, eye_pull / (to_eye + 0.35));

	// Squash along the axis, so the noise draws belts rather than blobs.
	vec3 belted = rolled + axis * dot(rolled, axis) * (band_stretch - 1.0);

	vec3 churn = vec3(
		fbm3(belted * band_scale * 0.5),
		fbm3(belted * band_scale * 0.5 + 2.7),
		fbm3(belted * band_scale * 0.5 + 6.1)) * 2.0 - 1.0;

	float cloud = fbm4(belted * band_scale + churn * turbulence);

	// The eye itself is a clear hole punched through the middle of the spiral.
	float eye_hole = 1.0 - smoothstep(0.0, 0.35, to_eye);
	cloud = mix(cloud, 0.05, eye_hole);

	// Lightning. Each slot picks its own place and either fires or does not.
	float slot = floor(TIME * flash_rate);
	float since = fract(TIME * flash_rate);
	vec3 spot = normalize(hash33(vec3(slot, 3.1, 7.7)) * 2.0 - 1.0);
	float fires = step(1.0 - flash_chance, hash13(vec3(slot, 11.3, 5.9)));
	float flash = fires * smoothstep(1.0 - flash_size, 1.0, dot(d, spot)) * exp(-since * 7.0);

	ALBEDO = mix(dark_colour.rgb, cloud_colour.rgb, smoothstep(0.22, 0.88, cloud));

	METALLIC = 0.0;
	SPECULAR = 0.2;
	ROUGHNESS = 0.95;

	// The flash lights the cloud it is inside, so thick cloud takes more of it.
	EMISSION = flash_colour.rgb * flash * flash_strength * mix(0.35, 1.0, cloud);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}
