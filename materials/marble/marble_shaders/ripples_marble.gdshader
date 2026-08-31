shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Still water, with something dropping into it.
//
// Each drop sends out a ring: a wave whose crests move steadily outward, growing
// weaker as they spread and dying away as the drop's own energy goes. That is
// one line of arithmetic -- a sine of distance minus time -- and the marble runs
// a few of them at once, landing at different places on different beats.
//
// The point of running several is what happens where two sets of rings meet.
// They are ADDED, so crests falling on crests pile up and crests falling on
// troughs cancel, and the little lattice of light that appears between two drops
// is real interference rather than anything drawn.
//
// The sum is a height, and the surface is tilted along its slope, so the rings
// are seen the way water is seen -- by what the light does on them, not by any
// colour of their own.

group_uniforms Water;
uniform vec4 water_colour : source_color = vec4(0.05, 0.35, 0.5, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.01, 0.1, 0.2, 1.0);
uniform vec4 crest_colour : source_color = vec4(0.75, 0.95, 1.0, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.88;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.03;

group_uniforms Drops;
uniform int drop_count : hint_range(1, 6) = 3;
// Drops a second, per source.
uniform float drop_rate : hint_range(0.1, 3.0) = 0.5;
// How closely the crests are spaced.
uniform float wave_length : hint_range(2.0, 40.0) = 18.0;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.4;
// How quickly a ring weakens as it spreads.
uniform float spread_loss : hint_range(0.0, 4.0) = 0.45;
// How many crests trail the front before the water goes flat again.
uniform float packet_length : hint_range(0.05, 2.0) = 0.75;
uniform float ripple_height : hint_range(0.0, 1.0) = 0.8;
uniform float crest_glow : hint_range(0.0, 3.0) = 1.2;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.7, 0.95, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

const int MAX_DROPS = 6;

varying vec3 surface_direction;


// The height of the water at a point: every ring on it, added up.
float surface_height(vec3 d) {
	float height = 0.0;

	for (int k = 0; k < MAX_DROPS; k++) {
		if (k >= drop_count) {
			break;
		}

		float clock = TIME * drop_rate + float(k) * 0.29;
		float which = floor(clock);
		float age = fract(clock) / drop_rate;

		vec3 seed = hash33(vec3(which * 2.7 + float(k) * 13.0, 4.1, 7.9));
		vec3 landed = normalize(seed * 2.0 - 1.0);

		float from_drop = acos(clamp(dot(d, landed), -1.0, 1.0));

		// The wave front, and everything behind it that has not died away yet.
		float front = age * wave_speed;
		if (from_drop > front) {
			continue;
		}

		float behind = front - from_drop;
		float ring = sin((from_drop - front) * wave_length);

		// Only the few crests just behind the front are still standing.
		ring *= exp(-behind / max(packet_length, 0.001));

		// Weaker the further it has spread, and weaker again as the drop's own
		// energy goes.
		float spread = exp(-from_drop * spread_loss);
		float dying = exp(-age * 0.8);

		height += ring * spread * dying;
	}

	return height;
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float height = surface_height(d);

	// Tilt the surface along the slope of the water, which is what makes the
	// rings visible at all.
	float step_size = 0.012;
	vec3 slope = vec3(
		surface_height(normalize(d + vec3(step_size, 0.0, 0.0))) - height,
		surface_height(normalize(d + vec3(0.0, step_size, 0.0))) - height,
		surface_height(normalize(d + vec3(0.0, 0.0, step_size))) - height) / step_size;

	vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
	view_slope -= dot(view_slope, NORMAL) * NORMAL;
	NORMAL = normalize(NORMAL - view_slope * ripple_height * 0.06);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	// A little colour on the crests, so a still marble is not a flat one.
	float crest = clamp(height, 0.0, 1.0);

	ALBEDO = mix(deep_colour.rgb, water_colour.rgb, clamp(0.5 + height * 1.5, 0.0, 1.0));
	ALPHA = clamp(water_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = crest_colour.rgb * crest * crest_glow * 0.25
			+ rim_tint.rgb * fresnel * rim_strength;
}
