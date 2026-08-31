shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A marble cut into facets, like a stone rather than blown like a bead.
//
// The cut is made by throwing away the sphere's own smooth normal. The surface
// is divided into cells, and every point in a cell is given the SAME normal --
// the one belonging to that cell's own middle. A shared normal is precisely what
// a flat face is, so the ball shades as a solid of flat faces even though the
// mesh under it is still round.
//
// Then the light is bent through each face, and bent by a different amount for
// each of the three colours -- which is dispersion, the reason a cut stone
// throws colour. Red bends least and blue bends most, so the three come out of
// the face pointing slightly differently, pick up slightly different light, and
// the edges of every facet run with colour.

group_uniforms Crystal;
uniform vec4 crystal_tint : source_color = vec4(0.85, 0.93, 1.0, 1.0);
uniform float crystal_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Cut;
// Bigger cuts more, smaller faces.
uniform float facet_scale : hint_range(1.0, 20.0) = 4.5;
// How completely the facet's normal replaces the ball's own.
uniform float facet_amount : hint_range(0.0, 1.0) = 0.85;
// A hairline of light along the join between two faces.
uniform vec4 edge_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float edge_width : hint_range(0.0, 0.5) = 0.07;

group_uniforms Dispersion;
uniform float bend : hint_range(1.0, 2.0) = 1.45;
// How far apart the three colours are bent. This is the whole of the rainbow.
uniform float spread : hint_range(0.0, 0.3) = 0.14;
uniform vec4 high_light : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform vec4 low_light : source_color = vec4(0.14, 0.2, 0.42, 1.0);
uniform float fire_strength : hint_range(0.0, 3.0) = 1.3;

varying vec3 surface_direction;


// The light a bent ray runs into. Standing in for a whole environment: bright
// above, dim below, and a sun somewhere off to one side.
vec3 light_from(vec3 heading) {
	float height = heading.y * 0.5 + 0.5;
	vec3 sky = mix(low_light.rgb, high_light.rgb, smoothstep(0.15, 0.9, height));

	// Banded on purpose. Three rays a hair apart would read the same value off a
	// smooth gradient and come back white -- the fire only appears when there is
	// something fine-grained for them to disagree about.
	float bands = 0.5 + 0.5 * sin(heading.y * 14.0 + heading.x * 9.0 + heading.z * 6.0);
	sky *= 0.55 + 0.75 * bands;

	float sun = pow(clamp(dot(heading, normalize(vec3(0.4, 0.75, 0.5))), 0.0, 1.0), 24.0);
	return sky + high_light.rgb * sun;
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	vec4 near = worley_near(d * facet_scale);

	// The middle of this cell, and so the face's own normal. Every point in the
	// cell gets the same one, which is what makes the face flat.
	vec3 face = normalize(d + near.xyz / facet_scale);
	vec3 face_normal = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(face, 0.0)).xyz);

	NORMAL = normalize(mix(NORMAL, face_normal, facet_amount));

	// Bent three times over, once per colour.
	vec3 red = refract(-VIEW, NORMAL, 1.0 / (bend - spread));
	vec3 green = refract(-VIEW, NORMAL, 1.0 / bend);
	vec3 blue = refract(-VIEW, NORMAL, 1.0 / (bend + spread));

	vec3 fire = vec3(light_from(red).r, light_from(green).g, light_from(blue).b);

	// The join between two faces, where the two nearest cell points are the
	// same distance off.
	vec3 walls = worley3(d * facet_scale);
	float edge = 1.0 - smoothstep(0.0, edge_width, walls.y - walls.x);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	ALBEDO = mix(crystal_tint.rgb * 0.4, fire, 0.82);
	ALPHA = clamp(crystal_opacity + fresnel * 0.5 + edge * 0.3, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = fire * fire_strength * 0.35 + edge_colour.rgb * edge * 0.35;
}
