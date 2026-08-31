shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Something that should not be drunk, going off in the glass.
//
// The bubbles are the design. Scattered points give one bubble per cell, and the
// whole field of them is dragged upwards through the marble over time, so every
// bubble rises -- and because they are read as a DISTANCE from their point, each
// one is a round thing with a bright edge and a clear middle, the way a bubble
// in a thick liquid is.
//
// Under them the sludge itself creeps: noise dragged by a slower copy of itself
// so the ooze turns over rather than sliding.

group_uniforms Ooze;
uniform vec4 ooze_colour : source_color = vec4(0.35, 0.85, 0.1, 1.0);
uniform vec4 sludge_colour : source_color = vec4(0.06, 0.22, 0.03, 1.0);
uniform float ooze_opacity : hint_range(0.0, 1.0) = 0.9;
uniform float ooze_scale : hint_range(0.5, 8.0) = 2.6;
uniform float creep_speed : hint_range(0.0, 1.0) = 0.08;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.1;

group_uniforms Bubbles;
uniform vec4 bubble_colour : source_color = vec4(0.75, 1.0, 0.35, 1.0);
// Bigger packs in more, smaller bubbles.
uniform float bubble_scale : hint_range(2.0, 40.0) = 9.0;
uniform float bubble_size : hint_range(0.05, 0.6) = 0.3;
// How much of a bubble is its bright edge rather than its clear middle.
uniform float bubble_edge : hint_range(0.02, 0.4) = 0.11;
uniform float rise_speed : hint_range(0.0, 2.0) = 0.5;
uniform float bubble_relief : hint_range(0.0, 1.0) = 0.5;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.7, 1.0, 0.4, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 surface_direction;


// How near this point is to the skin of the bubble it is inside.
float bubble_at(vec3 d, float t) {
	vec3 rising = d * bubble_scale + vec3(0.0, -t, 0.0);
	vec3 cell = worley3(rising);

	float skin = 1.0 - smoothstep(bubble_size - bubble_edge, bubble_size, cell.x);
	float hollow = 1.0 - smoothstep(bubble_size - bubble_edge * 2.0, bubble_size - bubble_edge, cell.x);

	// Big bubbles and small ones, from the number each cell carries.
	return clamp((skin - hollow * 0.75) * mix(0.4, 1.0, cell.z), 0.0, 1.0);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float t = TIME * rise_speed;

	// The sludge, turning over slowly.
	float creep = TIME * creep_speed;
	vec3 drag = vec3(
		fbm3(d * ooze_scale * 0.5 + creep),
		fbm3(d * ooze_scale * 0.5 + creep + 3.3),
		fbm3(d * ooze_scale * 0.5 + creep + 8.1)) * 2.0 - 1.0;
	float ooze = fbm4(d * ooze_scale + drag * 0.8 + vec3(0.0, -creep, 0.0));

	float bubbles = bubble_at(d, t);

	if (bubble_relief > 0.0) {
		float step_size = 0.02;
		vec3 slope = vec3(
			bubble_at(d + vec3(step_size, 0.0, 0.0), t) - bubbles,
			bubble_at(d + vec3(0.0, step_size, 0.0), t) - bubbles,
			bubble_at(d + vec3(0.0, 0.0, step_size), t) - bubbles) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * bubble_relief * 0.02);
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 body = mix(sludge_colour.rgb, ooze_colour.rgb, smoothstep(0.3, 0.75, ooze));
	ALBEDO = mix(body, bubble_colour.rgb, bubbles * 0.6);
	ALPHA = clamp(ooze_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.8;
	// Wet where the ooze is thick, tacky where the bubbles have dried it out.
	ROUGHNESS = mix(0.15, 0.5, bubbles);

	EMISSION = ooze_colour.rgb * smoothstep(0.55, 0.9, ooze) * glow_strength * 0.35
			+ bubble_colour.rgb * bubbles * glow_strength
			+ rim_tint.rgb * fresnel * rim_strength;
}
