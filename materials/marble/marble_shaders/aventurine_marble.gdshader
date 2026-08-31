shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Goldstone: copper stirred into molten glass and cooled slowly enough that it
// comes back out as thousands of little flat plates.
//
// The plates are why it cannot be done with a speckle. A fleck of colour is the
// same fleck from wherever it is looked at; a PLATE is a tiny mirror, and it is
// only alight when it happens to be turned towards you. Roll the marble and a
// different set of plates catches -- the glitter travels over the surface, which
// is the whole character of the stuff.
//
// So each cell is given a plate with a tilt of its own, and a pixel is lit by how
// squarely that plate faces the eye. Nothing here moves on its own; all of the
// life in it comes from the marble turning.

group_uniforms Glass;
uniform vec4 glass_colour : source_color = vec4(0.18, 0.055, 0.03, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.05, 0.015, 0.01, 1.0);
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.12;

group_uniforms Flakes;
uniform vec4 flake_colour : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform vec4 flake_hot : source_color = vec4(1.0, 0.9, 0.7, 1.0);
// Bigger packs in more, smaller plates.
uniform float flake_scale : hint_range(4.0, 80.0) = 34.0;
// How much of a cell its plate takes up.
uniform float flake_size : hint_range(0.05, 0.6) = 0.32;
// How far a plate can lie over from flat.
uniform float flake_tilt : hint_range(0.0, 1.0) = 0.55;
// How narrowly a plate has to be aimed at the eye before it lights up.
uniform float flash_sharpness : hint_range(1.0, 60.0) = 22.0;
uniform float flash_strength : hint_range(0.0, 6.0) = 2.2;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	vec4 near = worley_near(d * flake_scale);
	float across = length(near.xyz);
	float id = near.w;

	// The plate itself: a small disc lying in its cell.
	float plate = 1.0 - smoothstep(flake_size * 0.7, flake_size, across);

	// Its tilt, from its own number. Mostly lying with the surface, but never
	// exactly -- if they were all flat they would all flash at once.
	vec3 lean = hash33(vec3(id * 37.0, 5.3, 9.7)) * 2.0 - 1.0;
	vec3 plate_normal = normalize(NORMAL + (VIEW_MATRIX * MODEL_MATRIX * vec4(lean, 0.0)).xyz * flake_tilt);

	float aim = clamp(dot(plate_normal, VIEW), 0.0, 1.0);
	float flash = pow(aim, flash_sharpness) * plate;

	// The glass they are suspended in is deeper towards the silhouette.
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 body = mix(glass_colour.rgb, deep_colour.rgb, facing);

	ALBEDO = mix(body, flake_colour.rgb * 0.5, plate * 0.5);

	METALLIC = 0.6;
	SPECULAR = 0.7;
	ROUGHNESS = mix(surface_roughness, 0.35, plate);

	EMISSION = mix(flake_colour.rgb, flake_hot.rgb, flash) * flash * flash_strength;
}
