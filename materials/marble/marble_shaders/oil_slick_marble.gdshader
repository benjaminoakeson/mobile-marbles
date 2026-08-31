shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A film of oil on water.
//
// The colour is not painted on, it is worked out the way the real thing works.
// Light bounces off the top of a film and off the bottom of it, and the two
// paths differ by however far the second one went through the film -- so they
// cancel at some wavelengths and add at others, and what is left is a colour.
//
// Which means two things fall out for free. Turn the marble and the colours
// move, because a glancing look crosses more film than a straight-on one. And
// the bands follow the THICKNESS of the film, so rippling the film ripples the
// colour. Nothing else in the marble moves; the surface is still and only the
// light on it changes.

group_uniforms Film;
uniform vec4 base_colour : source_color = vec4(0.03, 0.03, 0.045, 1.0);
uniform float film_scale : hint_range(0.5, 12.0) = 2.6;
// How many colour bands a full thickness of film goes through.
uniform float band_count : hint_range(0.5, 20.0) = 1.3;
// How strongly the film's colour takes over from the wet black underneath.
uniform float sheen : hint_range(0.0, 1.0) = 0.72;
uniform float ripple_speed : hint_range(0.0, 1.0) = 0.09;
uniform float relief : hint_range(0.0, 1.0) = 0.4;

group_uniforms Surface;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.1;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.7;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.25;

varying vec3 surface_direction;


// How thick the film is at a point, and rippling.
float film_at(vec3 d, float t) {
	vec3 drift = vec3(t * 0.5, -t, t * 0.3);

	vec3 drag = vec3(
		fbm3(d * film_scale * 0.5 + drift * 0.5),
		fbm3(d * film_scale * 0.5 + drift * 0.5 + 4.1),
		fbm3(d * film_scale * 0.5 + drift * 0.5 + 9.3)) * 2.0 - 1.0;

	return fbm4(d * film_scale + drag * 0.6 + drift);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float t = TIME * ripple_speed;
	float thickness = film_at(d, t);

	if (relief > 0.0) {
		float step_size = 0.03;
		vec3 slope = vec3(
			film_at(d + vec3(step_size, 0.0, 0.0), t) - thickness,
			film_at(d + vec3(0.0, step_size, 0.0), t) - thickness,
			film_at(d + vec3(0.0, 0.0, step_size), t) - thickness) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * relief * 0.02);
	}

	// How far the second path travels through the film. Grazing angles cross
	// more of it, which is why the bands crowd towards the silhouette.
	// Held well off zero: right at the silhouette the bands would otherwise
	// crowd tighter than a pixel and break up into noise.
	float straight_on = clamp(dot(NORMAL, VIEW), 0.45, 1.0);
	float path = thickness * band_count / straight_on;

	// The three channels come out of step with one another, which is the whole
	// of the colour.
	vec3 interference = 0.5 + 0.5 * cos(TAU * (path + vec3(0.0, 0.33, 0.67)));

	ALBEDO = mix(base_colour.rgb, interference, sheen);

	METALLIC = metallic_amount;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	// A little of it lifted into light, so the colours still read where the
	// marble is turned away from the lamp.
	EMISSION = interference * glow_strength * 0.35;
}
