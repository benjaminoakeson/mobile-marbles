shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Fireworks going off inside a night-dark marble.
//
// A shell is a ring of sparks thrown out from a point, and everything about how
// it looks comes from how that ring moves: fast at first and then slowing, since
// the sparks are fighting the air the whole way. So the radius goes as the
// SQUARE ROOT of the burst's age -- most of the growth in the first instant --
// and the light fades away over the same time.
//
// The sparks themselves are spokes: the ring is cut up by the angle around the
// burst, so it comes apart into separate streaks rather than staying a smooth
// hoop, and the streaks trail back towards the middle behind the front.
//
// Several shells run at once on staggered clocks, each choosing a fresh place
// and a fresh colour every time it goes off.

group_uniforms Night;
uniform vec4 night_colour : source_color = vec4(0.02, 0.025, 0.06, 1.0);
uniform float night_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.06;
uniform vec4 star_colour : source_color = vec4(0.8, 0.85, 1.0, 1.0);
uniform float star_scale : hint_range(4.0, 60.0) = 26.0;

group_uniforms Shells;
uniform int shell_count : hint_range(1, 6) = 4;
// Bursts a second, per shell.
uniform float burst_rate : hint_range(0.1, 3.0) = 0.5;
// How far a burst opens out, as an angle over the marble.
uniform float burst_reach : hint_range(0.2, 3.0) = 2.0;
uniform float front_width : hint_range(0.02, 0.6) = 0.2;
// How many streaks a shell breaks into.
uniform float spoke_count : hint_range(4.0, 60.0) = 14.0;
uniform float trail_length : hint_range(0.0, 1.0) = 0.35;
uniform float glow_strength : hint_range(0.0, 6.0) = 4.2;

group_uniforms Colour;
uniform vec4 first_colour : source_color = vec4(1.0, 0.35, 0.25, 1.0);
uniform vec4 second_colour : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform vec4 third_colour : source_color = vec4(1.0, 0.85, 0.35, 1.0);

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.6, 0.7, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;

const int MAX_SHELLS = 6;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	vec3 light = vec3(0.0);

	for (int k = 0; k < MAX_SHELLS; k++) {
		if (k >= shell_count) {
			break;
		}

		// Each shell keeps its own clock, offset so they do not all fire at once.
		float clock = TIME * burst_rate + float(k) * 0.41;

		// The one going up now, and the one before it. A burst takes longer to
		// die than the gap between them, and cutting it off the instant the next
		// was loaded is what made it disappear rather than fade.
		for (int back = 0; back < 2; back++) {
			float which = floor(clock) - float(back);
			float age = fract(clock) + float(back);

			vec3 seed = hash33(vec3(which * 3.1 + float(k) * 17.0, 5.7, 2.3));
			vec3 centre = normalize(seed * 2.0 - 1.0);

			// Fast out, then slowing: the sparks are losing to the air the whole
			// way, and the light goes with them.
			float front = burst_reach * sqrt(age);
			float fade = exp(-age * 2.2);

			float from_centre = acos(clamp(dot(d, centre), -1.0, 1.0));

			// The front of the burst, and the trail dragging behind it.
			float at_front = 1.0 - smoothstep(0.0, front_width, abs(from_centre - front));
			float behind = clamp((front - from_centre) / max(trail_length, 0.001), 0.0, 1.0);
			float trail = (1.0 - behind) * step(0.0, front - from_centre) * 0.55;

			// Cut into spokes by the angle round the burst.
			vec3 first;
			vec3 second;
			frame_for(centre, first, second);
			float around = atan(dot(d, second), dot(d, first));
			float spokes = pow(0.5 + 0.5 * sin(around * spoke_count + seed.x * TAU), 1.8);

			// Which colour this shell was loaded with this time.
			vec3 colour = mix(first_colour.rgb, second_colour.rgb, smoothstep(0.0, 0.5, seed.y));
			colour = mix(colour, third_colour.rgb, smoothstep(0.5, 1.0, seed.y));

			light += colour * (at_front + trail) * spokes * fade;
		}
	}

	// A few stars behind it all.
	vec3 star_cell = worley3(d * star_scale);
	float star = smoothstep(0.2, 0.0, star_cell.x) * step(0.88, star_cell.z);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = night_colour.rgb;
	ALPHA = clamp(night_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.7;
	ROUGHNESS = surface_roughness;

	EMISSION = light * glow_strength
			+ star_colour.rgb * star * 1.2
			+ rim_tint.rgb * fresnel * rim_strength;
}
