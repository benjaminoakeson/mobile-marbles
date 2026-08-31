shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Something alive, in water.
//
// A jellyfish is two parts moving against each other, and the marble is built
// the same way. The bell is the top of the ball, and it SWIMS: its lip is a line
// of latitude that rises and falls, so the bell squeezes shut and opens again.
// The tentacles hang below it and sway -- and they lag, each depth a little
// behind the one above, because the stroke takes time to travel down them. That
// lag is what stops them looking like a stiff skirt.
//
// Both are drawn from the angle round the marble rather than from noise: ribs
// over the bell, strands under it, evenly spaced the way a real one's are.

group_uniforms Water;
uniform vec4 water_colour : source_color = vec4(0.04, 0.09, 0.16, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.16;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.06;

group_uniforms Bell;
uniform vec3 jelly_axis = vec3(0.1, 1.0, 0.05);
uniform vec4 bell_colour : source_color = vec4(0.95, 0.45, 0.8, 1.0);
uniform vec4 edge_colour : source_color = vec4(0.7, 0.95, 1.0, 1.0);
// Where the lip of the bell sits, measured along the axis.
uniform float bell_lip : hint_range(-0.8, 0.8) = 0.1;
uniform float bell_softness : hint_range(0.02, 0.6) = 0.2;
uniform float rib_count : hint_range(2.0, 30.0) = 10.0;

group_uniforms Swim;
uniform float pulse_speed : hint_range(0.0, 4.0) = 1.1;
// How far the lip travels as the bell squeezes.
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.13;

group_uniforms Tentacles;
uniform float strand_count : hint_range(2.0, 30.0) = 15.0;
uniform float strand_sharpness : hint_range(1.0, 16.0) = 9.0;
// How far the stroke has travelled down the strands.
uniform float sway_speed : hint_range(0.0, 4.0) = 1.1;
uniform float sway_amount : hint_range(0.0, 3.0) = 1.2;

group_uniforms Glow;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.2;
uniform vec4 rim_tint : source_color = vec4(0.8, 0.7, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.4;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 axis = normalize(jelly_axis);

	vec3 helper = abs(axis.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 first = normalize(cross(axis, helper));
	vec3 second = cross(axis, first);

	float around = atan(dot(d, second), dot(d, first));
	float height = dot(d, axis);

	// The stroke: the bell squeezes shut and opens again.
	float stroke = sin(TIME * pulse_speed);
	float lip = bell_lip + stroke * pulse_amount;

	float bell = smoothstep(lip - bell_softness, lip + bell_softness, height);
	float ribs = 0.5 + 0.5 * sin(around * rib_count);

	// The lip itself, picked out brighter than the rest of the bell.
	float edge = 1.0 - abs(height - lip) / bell_softness;
	edge = clamp(edge, 0.0, 1.0) * 0.8;

	// The strands, and the lag that travels down them. Deeper is further behind.
	float lag = sin(height * 4.0 - TIME * sway_speed) * sway_amount;
	float strands = pow(clamp(sin(around * strand_count + lag), 0.0, 1.0), strand_sharpness);
	strands *= 1.0 - smoothstep(lip - 0.15, lip + 0.15, height);

	vec3 body = mix(water_colour.rgb, bell_colour.rgb, bell * (0.55 + 0.45 * ribs));
	body = mix(body, edge_colour.rgb, max(strands * 0.75, edge));

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = body;
	ALPHA = clamp(water_opacity + bell * 0.5 + strands * 0.35 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = (bell_colour.rgb * bell * 0.25 + edge_colour.rgb * max(strands, edge) * 0.5)
			* glow_strength
			+ rim_tint.rgb * fresnel * rim_strength;
}
