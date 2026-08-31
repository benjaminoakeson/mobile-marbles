shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Rain running down the inside of the glass.
//
// Water on a window does not fall as a shower of separate drops -- it collects
// and runs in TRACKS, and a drop follows the track the last one left. So the
// marble is divided into narrow columns around its middle, and each column is
// given a track of its own with its own speed and its own timing.
//
// A drop is then two things in that column: a fat head, and a thin tail behind
// it that fades with distance -- which is the water it has not yet dragged with
// it. Both bend the surface, so the drops act as lenses and catch the light,
// which is most of what makes them read as water rather than as paint.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.2, 0.26, 0.33, 1.0);
uniform vec4 fog_colour : source_color = vec4(0.42, 0.5, 0.58, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.8;
uniform float fog_scale : hint_range(1.0, 30.0) = 12.0;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.25;

group_uniforms Rain;
uniform vec4 water_colour : source_color = vec4(0.85, 0.93, 1.0, 1.0);
// How many tracks there are round the marble.
uniform float tracks : hint_range(4.0, 60.0) = 16.0;
uniform float drop_size : hint_range(0.01, 0.3) = 0.1;
uniform float fall_speed : hint_range(0.0, 2.0) = 0.45;
// How long a tail a drop drags behind it.
uniform float tail_length : hint_range(0.0, 2.0) = 0.55;
// How many runs are going at once on each track.
uniform int drops_per_track : hint_range(1, 4) = 3;
// How far a run wanders off its track on the way down.
uniform float wobble_amount : hint_range(0.0, 2.0) = 0.7;
// The beads left standing on the glass between the runs.
uniform float bead_scale : hint_range(4.0, 60.0) = 26.0;
uniform float bead_size : hint_range(0.05, 0.6) = 0.28;
uniform float bead_amount : hint_range(0.0, 1.0) = 0.5;
// How much the water bends the surface.
uniform float lensing : hint_range(0.0, 1.0) = 0.6;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 surface_direction;


// How much water is at a point: heads and tails together.
float water_at(vec3 d, float t) {
	float around = atan(d.z, d.x) / TAU + 0.5;
	float height = d.y;

	// Which track this is, and where across it we are.
	float track = floor(around * tracks);
	float across = (fract(around * tracks) - 0.5) / tracks * TAU;

	float wet = 0.0;

	// This track and the one either side, so a drop is not cut off at the edge
	// of its own column.
	for (int side = -1; side <= 1; side++) {
		float which = track + float(side);
		float lane_across = across - float(side) / tracks * TAU;

		vec3 seed = hash33(vec3(which, 3.7, 8.1));
		float drift = (seed.y - 0.5) * 0.4 / tracks * TAU;

		// More than one run to a track, spaced along it -- a single drop per
		// track reads as a row of dots rather than as rain.
		for (int n = 0; n < 4; n++) {
			if (n >= drops_per_track) {
				break;
			}

			// Every run is a different size, and a bigger one goes faster: it
			// has more weight pulling it and the same skin holding it back.
			float mark = hash13(vec3(which, float(n) * 3.3, 4.9));
			float bulk = mix(0.5, 1.4, mark);
			float size = drop_size * bulk;
			float speed = fall_speed * (0.6 + seed.x * 0.8) * bulk;

			float phase = fract(seed.z + float(n) * 0.37 + mark * 0.23);
			float fallen = fract(phase + t * speed);

			// Falling rather than sliding: it gathers pace on the way down.
			float travelled = fallen * fallen * 0.65 + fallen * 0.35;
			float head = 1.15 - travelled * 2.3;
			float below_head = height - head;

			// Water does not run straight down glass. It wanders off the track
			// and comes back, which is most of what makes a window look wet.
			float wobble = sin(travelled * 9.0 + mark * TAU) * size * wobble_amount;
			float side_off = lane_across + drift + wobble;

			// The head itself.
			float blob = 1.0 - smoothstep(0.0, size,
					length(vec2(side_off, below_head * 0.8)));

			// The tail: only above the head, thinner and fading as it goes back
			// up -- the water the drop has not dragged with it yet.
			float tail = 0.0;
			if (below_head > 0.0) {
				float thin = 1.0 - smoothstep(0.0, size * 0.35, abs(side_off));
				tail = thin * exp(-below_head / max(tail_length, 0.001)) * 0.7;
			}

			wet = max(wet, max(blob, tail));
		}
	}

	// The beads standing on the glass that no run has picked up yet.
	vec3 bead = worley3(d * bead_scale);
	float standing = smoothstep(bead_size, 0.0, bead.x) * step(0.45, bead.z);
	wet = max(wet, standing * bead_amount);

	return wet;
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float t = TIME;

	float wet = water_at(d, t);

	// The water stands proud of the glass, so it bends what is seen through it.
	if (lensing > 0.0) {
		float step_size = 0.01;
		vec3 slope = vec3(
			water_at(normalize(d + vec3(step_size, 0.0, 0.0)), t) - wet,
			water_at(normalize(d + vec3(0.0, step_size, 0.0)), t) - wet,
			water_at(normalize(d + vec3(0.0, 0.0, step_size)), t) - wet) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * lensing * 0.004);
	}

	// Fogged glass everywhere the water has not run.
	float fog = fbm3(d * fog_scale) * 0.5 + 0.5;
	vec3 misted = mix(glass_tint.rgb, fog_colour.rgb, fog * 0.6);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(misted, water_colour.rgb, wet * 0.5);
	ALPHA = clamp(glass_opacity + fresnel * rim_strength - wet * 0.25, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	// The fog is dull and the water is a mirror -- the reason a wet window is
	// clear where the drops have run.
	ROUGHNESS = mix(surface_roughness, 0.02, wet);

	// The water picks up more light than the fogged glass beside it, which is
	// what makes a track stand out on a dull window.
	EMISSION = rim_tint.rgb * fresnel * rim_strength + water_colour.rgb * wet * 0.35;
}
