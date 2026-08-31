shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A thousand flowers: the Venetian trick of drawing coloured glass out into a
// rod with a pattern running all the way through it, slicing the rod into discs
// and packing the discs together.
//
// So the marble is built the same way round. The surface is cut into cells, and
// then -- the part that matters -- each cell is worked in ITS OWN coordinates:
// how far a point is from that cell's middle, and what angle it stands at around
// it. Rings come from the distance and petals from the angle, so every cell
// grows a flower of its own rather than sharing one pattern smeared across all
// of them.
//
// Each cell's number picks its colours and turns it, so no two canes in the
// mosaic sit the same way up.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.9, 0.94, 1.0, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.04;

group_uniforms Canes;
// Bigger packs more, smaller canes onto the marble.
uniform float cane_scale : hint_range(1.0, 20.0) = 5.0;
// How much of a cane is glass rather than flower.
uniform float cane_margin : hint_range(0.0, 0.6) = 0.18;
uniform float petal_count : hint_range(3.0, 12.0) = 6.0;
uniform float ring_count : hint_range(1.0, 6.0) = 2.5;

group_uniforms Colour;
// The canes are drawn from three colours, picked per cane by its own number,
// with a pale heart to every flower.
uniform vec4 first_colour : source_color = vec4(0.9, 0.15, 0.3, 1.0);
uniform vec4 second_colour : source_color = vec4(0.15, 0.45, 0.95, 1.0);
uniform vec4 third_colour : source_color = vec4(0.95, 0.75, 0.1, 1.0);
uniform vec4 heart_colour : source_color = vec4(1.0, 0.98, 0.9, 1.0);

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.4;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	vec4 near = worley_near(d * cane_scale);
	vec3 towards = near.xyz;
	float id = near.w;

	// The cane's own coordinates: a distance from its middle, and an angle round
	// it measured in the surface, so the flower lies flat on the marble.
	float across = length(towards - d * dot(towards, d));
	vec3 first;
	vec3 second;
	frame_for(d, first, second);
	float around = atan(dot(towards, second), dot(towards, first)) + id * TAU;

	// Petals: the flower's edge pushed in and out as it goes round.
	float petals = 0.72 + 0.28 * cos(around * petal_count);
	float inside = 1.0 - smoothstep(petals - cane_margin, petals, across);

	// Rings through the cane, and a pale heart at the middle of it.
	float rings = 0.5 + 0.5 * cos(across * ring_count * TAU + id * 3.0);
	float heart = 1.0 - smoothstep(0.12, 0.3, across);

	// Which two colours this cane was pulled from.
	vec3 warm = mix(first_colour.rgb, second_colour.rgb, fract(id * 5.7));
	vec3 cool = mix(third_colour.rgb, second_colour.rgb, fract(id * 11.3));

	vec3 flower = mix(warm, cool, rings);
	flower = mix(flower, heart_colour.rgb, heart);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(glass_tint.rgb, flower, inside);
	ALPHA = clamp(glass_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = rim_tint.rgb * fresnel * rim_strength;
}
