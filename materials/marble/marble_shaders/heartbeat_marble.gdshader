shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Something with a pulse in it.
//
// The vessels are a fixed network -- creases in noise, which branch and rejoin
// the way vessels do -- and they never move. What moves is a WAVE along them: a
// band of brightness that starts at one point and travels out over the marble,
// so the light runs through the network rather than the network running under
// the light.
//
// The beat is not even, because a heartbeat is not: it is a hard one followed by
// a softer one and then a rest. Two pulses are set going per cycle, a short gap
// apart, the second weaker than the first -- which is the lub-dub -- and the
// flesh itself swells a little with each.

group_uniforms Flesh;
uniform vec4 flesh_colour : source_color = vec4(0.35, 0.06, 0.09, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.12, 0.01, 0.03, 1.0);
uniform float flesh_scale : hint_range(0.5, 8.0) = 2.4;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.45;

group_uniforms Vessels;
uniform vec4 vessel_colour : source_color = vec4(0.7, 0.1, 0.12, 1.0);
uniform vec4 pulse_colour : source_color = vec4(1.0, 0.35, 0.3, 1.0);
uniform vec4 hot_colour : source_color = vec4(1.0, 0.85, 0.7, 1.0);
uniform float vessel_scale : hint_range(1.0, 20.0) = 5.5;
// How tightly the vessels are drawn out of the noise.
uniform float vessel_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float vessel_relief : hint_range(0.0, 1.0) = 0.5;

group_uniforms Beat;
uniform vec3 heart_axis = vec3(0.3, 0.6, 0.75);
// Beats a second.
uniform float beat_rate : hint_range(0.2, 3.0) = 1.1;
// How far behind the first beat the second one follows.
uniform float second_beat : hint_range(0.05, 0.5) = 0.22;
uniform float second_strength : hint_range(0.0, 1.0) = 0.6;
// How fast the wave travels out over the marble.
uniform float wave_speed : hint_range(0.2, 6.0) = 2.6;
// How wide the travelling band is.
uniform float wave_width : hint_range(0.05, 1.5) = 0.45;
uniform float glow_strength : hint_range(0.0, 4.0) = 2.0;

varying vec3 surface_direction;


float vessels_at(vec3 d) {
	return pow(ridged(d * vessel_scale), vessel_sharpness);
}


// How much of the wave has reached a point this far from the heart.
float wave_at(float distance_out, float since, float strength) {
	if (since < 0.0) {
		return 0.0;
	}

	float front = since * wave_speed;
	float band = 1.0 - clamp(abs(distance_out - front) / wave_width, 0.0, 1.0);

	// Weaker the further it has travelled, and weaker again the older it is, so
	// a wave dies away rather than being switched off somewhere.
	return band * band * strength * exp(-distance_out * 0.6) * exp(-since * 0.8);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	float vessels = vessels_at(d);

	if (vessel_relief > 0.0) {
		float step_size = 0.02;
		vec3 slope = vec3(
			vessels_at(d + vec3(step_size, 0.0, 0.0)) - vessels,
			vessels_at(d + vec3(0.0, step_size, 0.0)) - vessels,
			vessels_at(d + vec3(0.0, 0.0, step_size)) - vessels) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * vessel_relief * 0.02);
	}

	// How far round the marble this point is from the heart.
	float from_heart = acos(clamp(dot(d, normalize(heart_axis)), -1.0, 1.0));

	// Two beats a cycle: the hard one, and the softer one just after it.
	//
	// The beats before this one are still counted. A wave takes longer to cross
	// the marble than the gap between beats, so the one thrown by the last beat
	// is still travelling when the next is thrown -- and dropping it at the
	// moment the cycle came round was what made the pulse stop dead instead of
	// running off the far side.
	float cycle = fract(TIME * beat_rate) / beat_rate;
	float gap = 1.0 / beat_rate;

	float pulse = 0.0;
	for (int back = 0; back < 3; back++) {
		float since = cycle + float(back) * gap;
		pulse += wave_at(from_heart, since, 1.0);
		pulse += wave_at(from_heart, since - second_beat, second_strength);
	}
	pulse = clamp(pulse, 0.0, 1.0);

	float meat = fbm3(d * flesh_scale);
	vec3 body = mix(deep_colour.rgb, flesh_colour.rgb, smoothstep(0.35, 0.7, meat));

	// The wave only lights what it runs along.
	float lit = vessels * pulse;

	vec3 vessel = mix(vessel_colour.rgb, pulse_colour.rgb, pulse);
	ALBEDO = mix(body, vessel, vessels * 0.8);

	METALLIC = 0.0;
	SPECULAR = 0.4;
	// Wet where the vessels stand.
	ROUGHNESS = mix(surface_roughness, 0.2, vessels);

	EMISSION = mix(pulse_colour.rgb, hot_colour.rgb, lit) * lit * glow_strength;
}
