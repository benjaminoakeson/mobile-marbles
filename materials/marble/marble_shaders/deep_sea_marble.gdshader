shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Looking down into deep water.
//
// The light on it is caustics, and a caustic is made here the way it is made in
// water: by folding a field onto itself. Two copies of the same noise are taken
// a moment apart, and the places where they AGREE are drawn bright. Agreement
// happens along lines rather than in patches, so what comes out is the wandering
// net of light you get on a sea floor -- and because the two copies are moving
// at slightly different times, the net crawls and re-knits itself.
//
// The rest is depth: the light only reaches the top of the marble, the water
// darkens as it goes down, and specks of life drift up through it.

group_uniforms Water;
uniform vec4 water_colour : source_color = vec4(0.015, 0.1, 0.17, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.0, 0.025, 0.07, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.8;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.06;

group_uniforms Caustics;
uniform vec4 caustic_colour : source_color = vec4(0.4, 0.95, 0.9, 1.0);
uniform float caustic_scale : hint_range(1.0, 15.0) = 4.5;
// How tightly the net is drawn. Low is a wash, high is thread.
uniform float caustic_sharpness : hint_range(1.0, 20.0) = 12.0;
// How far apart in time the two copies of the field are read.
uniform float caustic_offset : hint_range(0.01, 1.0) = 0.3;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.12;
uniform float glow_strength : hint_range(0.0, 4.0) = 0.9;

group_uniforms Motes;
uniform vec4 mote_colour : source_color = vec4(0.7, 1.0, 0.9, 1.0);
uniform float mote_scale : hint_range(4.0, 60.0) = 20.0;
uniform float mote_rise : hint_range(0.0, 2.0) = 0.35;
uniform float mote_brightness : hint_range(0.0, 4.0) = 1.4;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.5, 0.9, 0.95, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float t = TIME * flow_speed;

	// The same field, read twice a moment apart.
	float first = fbm3(d * caustic_scale + vec3(0.0, t, 0.0));
	float second = fbm3(d * caustic_scale + vec3(4.3, t + caustic_offset, 1.7));
	float net = pow(1.0 - abs(first - second), caustic_sharpness);

	// Light comes from above and gives out with depth.
	float lit = smoothstep(-0.15, 0.95, d.y);

	// Specks of life, drifting up.
	vec3 mote_cell = worley3(d * mote_scale + vec3(0.0, -TIME * mote_rise, 0.0));
	float mote = smoothstep(0.22, 0.0, mote_cell.x) * step(0.86, mote_cell.z);
	mote *= 0.4 + 0.6 * sin(TIME * 1.5 + mote_cell.z * TAU) * 0.5 + 0.3;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(deep_colour.rgb, water_colour.rgb, lit);
	ALPHA = clamp(water_opacity + net * lit * 0.3 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = caustic_colour.rgb * net * lit * glow_strength
			+ mote_colour.rgb * mote * mote_brightness
			+ rim_tint.rgb * fresnel * rim_strength;
}
