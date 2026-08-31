shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Molten rock with a crust on it, actually flowing.
//
// The flow is the whole point, and it is one trick: the noise field is dragged
// by a SLOWER, COARSER copy of itself, and both of them are moving. Sliding a
// field past the surface would only ever look like a texture being pulled --
// dragging it through another moving field makes it stretch, fold and turn back
// on itself, which is what lava does.
//
// Once the field is flowing, the picture is a level cut through it: above the
// level the rock has cooled into crust, below it the rock is still open. The
// hottest line is the one right at the level, where the crust is breaking --
// which is why the cracks glow brightest and go dark as the plates close.
//
// The crust also bends the surface, so the plates read as slabs standing a
// little proud of the melt between them.

group_uniforms Flow;
uniform float flow_speed : hint_range(0.0, 0.5) = 0.05;
// Bigger breaks the surface into more, smaller plates.
uniform float flow_scale : hint_range(0.5, 8.0) = 2.6;
// How far the coarse field drags the fine one. This is the folding.
uniform float warp_amount : hint_range(0.0, 2.0) = 0.85;

group_uniforms Crust;
uniform vec4 rock_colour : source_color = vec4(0.08, 0.055, 0.055, 1.0);
uniform vec4 scorch_colour : source_color = vec4(0.3, 0.1, 0.05, 1.0);
// Where the cut is taken. Higher leaves more of the marble molten.
uniform float crust_level : hint_range(0.2, 0.8) = 0.34;
uniform float crust_softness : hint_range(0.02, 0.5) = 0.1;
uniform float relief : hint_range(0.0, 1.0) = 0.6;

group_uniforms Heat;
uniform vec4 lava_colour : source_color = vec4(1.0, 0.32, 0.02, 1.0);
uniform vec4 hot_colour : source_color = vec4(1.0, 0.92, 0.55, 1.0);
uniform float glow_strength : hint_range(0.0, 6.0) = 1.15;
// The slow swell of the melt underneath.
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.7;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;

varying vec3 surface_direction;


float lava_at(vec3 d, float t) {
	vec3 carried = vec3(0.0, -t, 0.0);

	// The coarse field, moving at half speed. Its value at a point is how far
	// the fine field is dragged there.
	vec3 drag = vec3(
		fbm3(d * flow_scale * 0.5 + carried * 0.5),
		fbm3(d * flow_scale * 0.5 + carried * 0.5 + vec3(3.7, 1.3, 5.1)),
		fbm3(d * flow_scale * 0.5 + carried * 0.5 + vec3(7.9, 2.6, 1.7))) * 2.0 - 1.0;

	return fbm4(d * flow_scale + drag * warp_amount + carried);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float t = TIME * flow_speed;
	float n = lava_at(d, t);

	// One where the rock has set, zero where it is still open.
	float crust = smoothstep(crust_level, crust_level + crust_softness, n);

	// The break line itself: brightest exactly at the level, gone a step either
	// side of it.
	float crack = 1.0 - min(abs(n - crust_level) / crust_softness, 1.0);

	float swell = 1.0 + sin(TIME * pulse_speed + n * 4.0) * pulse_amount;
	// Squared, so the melt falls away from the break line quickly instead of
	// washing the whole marble in light.
	float heat = clamp(max(1.0 - crust, crack * crack), 0.0, 1.0);
	heat = pow(heat, 2.2) * swell;

	if (relief > 0.0) {
		float step_size = 0.02;
		vec3 slope = vec3(
			lava_at(d + vec3(step_size, 0.0, 0.0), t) - n,
			lava_at(d + vec3(0.0, step_size, 0.0), t) - n,
			lava_at(d + vec3(0.0, 0.0, step_size), t) - n) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * relief * 0.03);
	}

	// Cold rock, scorched at the edges of the plates, and the melt showing
	// through where they have parted.
	vec3 stone = mix(scorch_colour.rgb, rock_colour.rgb, crust);
	ALBEDO = mix(lava_colour.rgb * 0.25, stone, crust);

	METALLIC = 0.0;
	SPECULAR = 0.3;
	// Crust is dry and matte; melt is wet.
	ROUGHNESS = mix(0.3, 0.9, crust);

	// White heat only at the very centre of a river, not across all of it.
	EMISSION = mix(lava_colour.rgb, hot_colour.rgb, pow(heat, 3.0)) * heat * glow_strength;
}
