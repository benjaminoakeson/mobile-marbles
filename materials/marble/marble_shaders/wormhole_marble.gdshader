shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A hole in the marble that goes somewhere else.
//
// The trick is entirely in the measuring. Distance from the mouth is not taken
// as an angle but as ONE OVER the angle -- so a step taken near the middle
// covers far more of it than the same step taken at the edge. That is what
// perspective does to a tunnel receding from you, and reading the marble that
// way turns a flat disc into a shaft with no bottom.
//
// The rings are then evenly spaced in that measure, which means they crowd
// together towards the middle and rush apart as they come out -- and sliding
// them along it makes the tunnel appear to fall away for ever.
//
// The shaft is given a twist that tightens with depth, so the walls turn as they
// go down and it never reads as a set of flat rings.

group_uniforms Space;
uniform vec4 void_colour : source_color = vec4(0.02, 0.015, 0.05, 1.0);
uniform float void_opacity : hint_range(0.0, 1.0) = 0.95;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.08;

group_uniforms Tunnel;
uniform vec3 mouth_axis = vec3(0.2, 0.9, 0.35);
uniform vec4 wall_colour : source_color = vec4(0.35, 0.15, 0.85, 1.0);
uniform vec4 ring_colour : source_color = vec4(0.6, 0.9, 1.0, 1.0);
// How many rings there are down the shaft.
uniform float ring_count : hint_range(1.0, 20.0) = 6.0;
uniform float fall_speed : hint_range(0.0, 3.0) = 0.6;
// How hard the shaft twists as it goes down.
uniform float twist_amount : hint_range(0.0, 4.0) = 1.2;
// How wide the mouth is, as an angle over the marble.
uniform float mouth_size : hint_range(0.3, 3.0) = 1.5;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.8;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.5, 0.6, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 axis = normalize(mouth_axis);

	float from_mouth = acos(clamp(dot(d, axis), -1.0, 1.0));

	// One over the angle: near the middle this runs away to a great depth, at
	// the edge it barely moves. The shaft's perspective, in one line.
	float depth = 1.0 / (from_mouth + 0.12);

	vec3 first;
	vec3 second;
	frame_for(axis, first, second);
	float around = atan(dot(d, second), dot(d, first));

	// The walls turn as they recede.
	float wound = around + depth * twist_amount;

	// Rings, evenly spaced down the shaft and falling away from the eye.
	float run = depth * ring_count - TIME * fall_speed * ring_count;
	float ring = 1.0 - abs(fract(run) * 2.0 - 1.0);
	ring = pow(ring, 3.0);

	// The wall between the rings, ribbed round the shaft.
	float ribs = 0.5 + 0.5 * sin(wound * 8.0);

	// Everything gives out beyond the mouth, and darkens to nothing down the
	// middle, where the shaft is too far off to light.
	float inside = 1.0 - smoothstep(mouth_size * 0.6, mouth_size, from_mouth);
	float too_deep = smoothstep(0.0, 0.25, from_mouth);

	float lit = inside * too_deep;

	vec3 shaft = mix(wall_colour.rgb * (0.35 + 0.65 * ribs), ring_colour.rgb, ring);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(void_colour.rgb, shaft * 0.4, lit);
	ALPHA = clamp(void_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = surface_roughness;

	EMISSION = shaft * lit * glow_strength + rim_tint.rgb * fresnel * rim_strength;
}
