shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A kaleidoscope: two mirrors and some coloured chips between them.
//
// Everything a kaleidoscope does comes from what happens BEFORE you look at the
// chips. The angle round the marble is folded down into one narrow wedge and
// then mirrored, so a mark made anywhere in that wedge is answered by the same
// mark in every other wedge, and reversed in every other one again. Whatever is
// drawn afterwards comes out symmetrical whether it wants to or not.
//
// So the pattern itself can be the simplest thing going -- a bit of noise and a
// few rings -- and the fold makes it into a rose window. Turning the fold is
// what turns the whole figure, and letting the pattern drift underneath while
// the fold turns is what keeps it from ever repeating.

group_uniforms Fold;
uniform vec3 fold_axis = vec3(0.15, 1.0, 0.1);
// How many wedges the marble is cut into. Each is mirrored against the next.
uniform float segments : hint_range(2.0, 16.0) = 8.0;
uniform float spin_speed : hint_range(0.0, 1.0) = 0.12;
// How fast the chips drift about inside the wedge.
uniform float drift_speed : hint_range(0.0, 1.0) = 0.09;

group_uniforms Chips;
uniform vec4 first_colour : source_color = vec4(0.85, 0.15, 0.55, 1.0);
uniform vec4 second_colour : source_color = vec4(0.15, 0.6, 0.95, 1.0);
uniform vec4 third_colour : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 dark_colour : source_color = vec4(0.05, 0.04, 0.09, 1.0);
uniform float chip_scale : hint_range(0.5, 12.0) = 2.2;
// How hard the edges of the chips are.
uniform float chip_edge : hint_range(0.01, 0.5) = 0.12;
uniform float ring_count : hint_range(0.0, 12.0) = 5.0;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.8;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 axis = normalize(fold_axis);

	vec3 first;
	vec3 second;
	frame_for(axis, first, second);

	float around = atan(dot(d, second), dot(d, first));
	// How far out from the pole the fold turns about.
	float out_from_pole = acos(clamp(dot(d, axis), -1.0, 1.0));

	// The fold. One wedge wide, and mirrored about its middle -- which is the
	// whole trick.
	float wedge = TAU / segments;
	float folded = mod(around + TIME * spin_speed * TAU, wedge);
	folded = abs(folded - wedge * 0.5);

	// The place inside the wedge to read the chips from: the folded angle and
	// the distance out, laid back down as a flat position. Only those two go in,
	// so everything drawn from here is symmetrical by construction -- and it now
	// varies ACROSS the wedge as well as along it, which is what makes a figure
	// rather than a stripe.
	float drift = TIME * drift_speed;
	vec2 flat_spot = vec2(cos(folded), sin(folded)) * out_from_pole;
	vec3 spot = vec3(flat_spot, drift);

	float chips = fbm3(spot * chip_scale + vec3(drift, -drift * 0.7, drift * 0.4));

	// Stepped, so the wedge holds flat pieces of coloured glass with edges,
	// rather than a smooth wash that happens to be symmetrical.
	chips = floor(chips * 5.0) / 5.0;
	float rings = 0.5 + 0.5 * cos(out_from_pole * ring_count + drift * 4.0);

	// Three colours, cut into flat pieces of glass rather than blended.
	float band = smoothstep(0.36 - chip_edge, 0.36 + chip_edge, chips);
	float band_two = smoothstep(0.52 - chip_edge, 0.52 + chip_edge, chips);

	vec3 colour = mix(dark_colour.rgb, first_colour.rgb, band);
	colour = mix(colour, second_colour.rgb, band_two);
	colour = mix(colour, third_colour.rgb, band_two * rings);

	// The mirror lines themselves, catching the light.
	float seam = 1.0 - smoothstep(0.0, 0.02, folded);

	ALBEDO = colour;

	METALLIC = 0.0;
	SPECULAR = 0.8;
	ROUGHNESS = 0.18;

	EMISSION = colour * glow_strength * 0.3 + vec3(1.0) * seam * 0.25;
}
