shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Water going down a hole.
//
// The marble is measured in the vortex's own terms rather than in x, y and z:
// how far round the axis a point is, and how far it is from the eye. In that
// pair of numbers a spiral is nothing but a straight line -- so the arms are
// drawn by adding the two together, with the LOGARITHM of the distance, which
// is what makes the arms wind tighter and tighter as they close on the middle
// instead of spacing out evenly.
//
// The turn is faster nearer the eye, as it is in real water going down a drain,
// so the arms wind up on themselves and never turn as one piece. The foam rides
// the crests of the arms and is stretched along them.

group_uniforms Water;
uniform vec4 deep_colour : source_color = vec4(0.005, 0.06, 0.14, 1.0);
uniform vec4 water_colour : source_color = vec4(0.06, 0.5, 0.7, 1.0);
uniform vec4 foam_colour : source_color = vec4(0.9, 1.0, 1.0, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.05;

group_uniforms Vortex;
uniform vec3 vortex_axis = vec3(0.25, 1.0, 0.2);
uniform float arms : hint_range(1.0, 8.0) = 4.0;
// How many turns the arms make on their way in.
uniform float tightness : hint_range(0.5, 12.0) = 6.0;
uniform float spin_speed : hint_range(0.0, 2.0) = 0.3;
// How big the still hole in the middle is.
uniform float eye_size : hint_range(0.05, 0.6) = 0.22;

group_uniforms Foam;
uniform float foam_scale : hint_range(1.0, 40.0) = 14.0;
uniform float foam_sharpness : hint_range(1.0, 12.0) = 3.0;
uniform float foam_glow : hint_range(0.0, 2.0) = 0.35;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.7, 0.95, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 axis = normalize(vortex_axis);

	// A frame to measure the turn in.
	vec3 helper = abs(axis.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 first = normalize(cross(axis, helper));
	vec3 second = cross(axis, first);

	float around = atan(dot(d, second), dot(d, first));
	// Zero at the eye, one at the far side of the marble.
	float out_from_eye = acos(clamp(dot(d, axis), -1.0, 1.0)) / PI;

	// The spiral, and the wind-up: the closer in, the faster round.
	float wound = around
			+ log(out_from_eye + 0.08) * tightness
			+ TIME * spin_speed / (out_from_eye + 0.18);

	float arm = sin(wound * arms) * 0.5 + 0.5;

	// Foam rides the crests and is drawn out along the flow -- fine across an
	// arm, long down it.
	float streaks = ridged(vec3(wound * 0.4, out_from_eye * foam_scale, TIME * 0.05));
	float foam = pow(arm, foam_sharpness) * streaks;

	// The eye, and the water piling up around its lip.
	float eye = 1.0 - smoothstep(eye_size * 0.6, eye_size, out_from_eye);
	float lip = smoothstep(eye_size, eye_size * 1.6, out_from_eye)
			* (1.0 - smoothstep(eye_size * 1.6, eye_size * 2.6, out_from_eye));

	// The arms themselves are water pulled up thin, so they show as lighter
	// bands even before the foam goes on them.
	vec3 body = mix(deep_colour.rgb, water_colour.rgb,
			smoothstep(0.05, 0.55, out_from_eye) * mix(0.45, 1.0, arm));
	body = mix(body, deep_colour.rgb * 0.35, eye);
	body = mix(body, foam_colour.rgb, clamp(foam * 0.85 + lip * 0.15, 0.0, 1.0));

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = body;
	ALPHA = clamp(water_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	// Foam is dull, open water is a mirror.
	ROUGHNESS = mix(surface_roughness, 0.55, foam);

	EMISSION = foam_colour.rgb * foam * foam_glow + rim_tint.rgb * fresnel * rim_strength;
}
