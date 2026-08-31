shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A small sun.
//
// The face of it is granulation: the tops of convection cells, bright in the
// middle and separated by cooler lanes, sliding slowly past one another as the
// gas below turns over. Scattered points give the cells; each one is handed a
// number so it can flicker at its own rate.
//
// The edge is prominences. A real one is only seen where the line of sight
// grazes the surface and it stands against the sky, so they are drawn where the
// marble is turning away from the eye -- creases in a slowly turning field,
// leaping off the limb.
//
// Almost all of this is emission. A sun is not lit, it lights.

group_uniforms Surface;
uniform vec4 photosphere : source_color = vec4(1.0, 0.72, 0.15, 1.0);
uniform vec4 lane_colour : source_color = vec4(0.6, 0.14, 0.01, 1.0);
uniform float granule_scale : hint_range(2.0, 30.0) = 9.0;
uniform float lane_width : hint_range(0.02, 0.6) = 0.22;
uniform float glow_strength : hint_range(0.0, 6.0) = 1.15;

group_uniforms Churn;
// How fast the cells slide past one another.
uniform float churn_speed : hint_range(0.0, 1.0) = 0.09;
// How fast a single cell brightens and dims.
uniform float flicker_speed : hint_range(0.0, 6.0) = 1.6;

group_uniforms Prominences;
uniform vec4 flare_colour : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float flare_scale : hint_range(1.0, 20.0) = 5.0;
uniform float flare_speed : hint_range(0.0, 2.0) = 0.3;
// How far in from the silhouette the arcs are allowed to show.
uniform float limb_power : hint_range(0.5, 8.0) = 2.5;
uniform float flare_strength : hint_range(0.0, 6.0) = 1.8;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	// The cells drift, rather than the marble's surface moving under them.
	vec3 cell = worley3(d * granule_scale + vec3(TIME * churn_speed));

	// Arcs, and the grazing angles they are seen at.
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);

	float lane = 1.0 - smoothstep(0.0, lane_width, cell.y - cell.x);
	float flicker = mix(0.72, 1.0, 0.5 + 0.5 * sin(TIME * flicker_speed + cell.z * TAU));

	vec3 face = mix(photosphere.rgb * flicker, lane_colour.rgb, lane);

	float arcs = pow(ridged(d * flare_scale + vec3(TIME * flare_speed)), 6.0);
	float limb = pow(facing, limb_power) * arcs;

	// Limb darkening: a real sun is dimmer at its edge, where the line of sight
	// leaves through more of its atmosphere. Without it the disc is one flat
	// blaze and reads as a lamp rather than a body.
	face *= mix(1.0, 0.45, pow(facing, 1.5));

	ALBEDO = face * 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;

	EMISSION = face * glow_strength + flare_colour.rgb * limb * flare_strength;
}
