shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A coal, near enough burnt out.
//
// Nothing here flows. A dying fire is a heap of lumps that have stopped moving,
// with heat left in the gaps between them -- so the marble is built from
// scattered points, one lump per point, and the light lives only in the lanes
// where two lumps meet.
//
// Each lump is handed a number of its own, and its heat rises and falls on that
// number's beat. That is what stops the whole marble breathing in time with
// itself: one corner brightens while another is going dark, the way a real bed
// of coals does.
//
// Over the top, sparks: far finer points, drifting upwards and dying out.

group_uniforms Coal;
uniform vec4 coal_colour : source_color = vec4(0.055, 0.045, 0.045, 1.0);
uniform float lump_scale : hint_range(1.0, 20.0) = 4.5;
// How wide the hot lane between two lumps is.
uniform float lane_width : hint_range(0.02, 0.5) = 0.11;
// The fine ash grain over the lumps, so they are not bald.
uniform float ash_scale : hint_range(4.0, 60.0) = 22.0;

group_uniforms Heat;
uniform vec4 ember_colour : source_color = vec4(1.0, 0.3, 0.03, 1.0);
uniform vec4 white_hot : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float glow_strength : hint_range(0.0, 6.0) = 2.2;
// How fast a lump goes round from dull to bright and back.
uniform float breath_speed : hint_range(0.0, 4.0) = 1.1;
// How dark a lump gets at its dullest.
uniform float breath_depth : hint_range(0.0, 1.0) = 0.85;

group_uniforms Sparks;
uniform vec4 spark_colour : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float spark_scale : hint_range(10.0, 80.0) = 34.0;
uniform float spark_rise : hint_range(0.0, 1.0) = 0.25;
uniform float spark_brightness : hint_range(0.0, 6.0) = 2.5;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	vec3 lump = worley3(d * lump_scale);

	// The lane between two lumps, and how hot this lump is keeping it.
	float lane = 1.0 - smoothstep(0.0, lane_width, lump.y - lump.x);
	float beat = 0.5 + 0.5 * sin(TIME * breath_speed + lump.z * TAU);
	float heat = lane * mix(1.0 - breath_depth, 1.0, beat);

	// Sparks rise, so their field is carried upwards through them.
	vec3 spark_cell = worley3(d * spark_scale + vec3(0.0, -TIME * spark_rise, 0.0));
	float spark = smoothstep(0.35, 0.0, spark_cell.x) * step(0.82, spark_cell.z);
	spark *= 0.5 + 0.5 * sin(TIME * 6.0 + spark_cell.z * TAU);

	float ash = fbm3(d * ash_scale) * 0.5 + 0.5;
	ALBEDO = mix(coal_colour.rgb * ash, ember_colour.rgb * 0.25, heat);

	METALLIC = 0.0;
	SPECULAR = 0.2;
	ROUGHNESS = mix(0.95, 0.6, heat);

	EMISSION = mix(ember_colour.rgb, white_hot.rgb, heat * heat) * heat * glow_strength
			+ spark_colour.rgb * spark * spark_brightness;
}
