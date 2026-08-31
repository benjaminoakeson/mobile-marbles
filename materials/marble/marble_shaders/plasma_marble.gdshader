shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A plasma globe in the palm of your hand.
//
// Nothing here is noise. Noise was tried first and it was wrong: thresholding a
// field gives a HAZE of filaments, and what a plasma globe actually has is a
// handful of separate arcs you can count, each reaching from the middle out to
// the glass and moving on its own.
//
// So the arcs are geometry. Each one is a line of points walked from the core to
// the shell, bending further off its heading the further out it goes, and swung
// slowly around by time. A pixel is lit by how NEAR its view ray passes to any
// of those points -- an inverse square falloff, which gives the soft bloom an
// electrical discharge has without needing a volume walked to find it.
//
// That makes it cheap as well as right: a few dozen point-to-ray distances, all
// arithmetic, no texture reads and no marching.

group_uniforms Globe;
uniform vec4 glass_tint : source_color = vec4(0.04, 0.03, 0.1, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.92;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.08;

group_uniforms Arcs;
uniform vec4 arc_colour : source_color = vec4(0.35, 0.55, 1.0, 1.0);
uniform vec4 hot_colour : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform int arc_count : hint_range(1, 8) = 5;
// How near a ray has to pass to be lit. This is the thickness of an arc.
uniform float arc_width : hint_range(0.01, 0.3) = 0.09;
// How far an arc bends off its heading by the time it reaches the glass.
uniform float arc_bend : hint_range(0.0, 2.0) = 0.55;
// How fast the arcs swing round.
uniform float arc_sway : hint_range(0.0, 2.0) = 0.35;
uniform float flicker_speed : hint_range(0.0, 20.0) = 6.0;
uniform float glow_strength : hint_range(0.0, 6.0) = 2.4;

group_uniforms Core;
uniform vec4 core_colour : source_color = vec4(0.8, 0.5, 1.0, 1.0);
uniform float core_size : hint_range(0.02, 0.5) = 0.13;
uniform float core_pulse_speed : hint_range(0.0, 8.0) = 2.5;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.55, 0.7, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.4;

uniform float marble_radius = 0.5;

const int MAX_ARCS = 8;
// Spaced closer together than an arc is wide, or the arc reads as a string of
// beads rather than a line.
const int ARC_SAMPLES = 24;

varying vec3 obj_position;
varying vec3 obj_view;


// A point a fraction `u` of the way along arc `k`, from the core at 0 to the
// glass at 1.
vec3 arc_point(float k, float u, float t) {
	vec3 seed = hash33(vec3(k * 3.7, 1.3, 5.1));

	// Where the arc is pointing at the moment. Every one is given its own rate,
	// so they never sweep as a set.
	float sweep = t * arc_sway * (0.6 + seed.x) + seed.y * TAU;
	float roll = t * arc_sway * (0.4 + seed.z) + seed.x * TAU;
	vec3 heading = normalize(vec3(sin(sweep), cos(roll) * 0.85, cos(sweep * 0.9 + seed.z * 4.0)));

	// The bend grows with distance from the core, so the arc leaves the middle
	// straight and wanders as it goes -- and it wanders in time as well, which
	// is what makes it look like it is being blown about.
	// The wander turns slowly ALONG the arc. Anything faster and the line of
	// points zigzags instead of curving, and the arc reads as a row of beads.
	vec3 wander = vec3(
		sin(roll * 1.7 + u * 1.4 + seed.x * 6.0),
		cos(sweep * 1.3 + u * 1.7 + seed.y * 6.0),
		sin(sweep * 1.1 + u * 1.2 + seed.z * 6.0));

	return normalize(heading + wander * arc_bend * u) * u;
}


void vertex() {
	obj_position = VERTEX;

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	// Everything is measured in a marble one unit across, so the arcs do not
	// have to know how big the ball is.
	vec3 ray_from = obj_position / marble_radius;
	vec3 ray_dir = normalize(obj_view);

	float t = TIME;
	float lit = 0.0;

	for (int k = 0; k < MAX_ARCS; k++) {
		if (k >= arc_count) {
			break;
		}

		// Each arc brightens and dims on its own beat, and now and then nearly
		// goes out.
		float beat = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(t * flicker_speed + float(k) * 2.4), 2.0);

		// The nearest point on the arc decides how bright the pixel is; the rest
		// of them only add a little bloom around it. Summing them all instead
		// would make a long arc seen end-on brighter than a short one seen
		// across, which is not how a line of light works.
		float nearest = 0.0;
		float bloom = 0.0;

		for (int i = 0; i < ARC_SAMPLES; i++) {
			float u = float(i) / float(ARC_SAMPLES - 1);
			vec3 point = arc_point(float(k), u, t);

			// How near the view ray passes this point.
			vec3 to_point = point - ray_from;
			float along = max(dot(to_point, ray_dir), 0.0);
			float miss = length(to_point - ray_dir * along);

			// Thin where it leaves the core, thicker where it fans onto the
			// glass, and brighter at that end where it is striking something.
			float width = arc_width * mix(0.55, 1.5, u);
			// Squared, so an arc has a bright thread down the middle of it
			// rather than being a soft smear all the way through.
			float fall = width * width / (width * width + miss * miss);
			float near = fall * fall * mix(0.4, 1.0, u);

			nearest = max(nearest, near);
			bloom += near;
		}

		lit += (nearest + bloom * 0.15 / float(ARC_SAMPLES)) * beat;
	}

	// The ball of light the arcs are struck from.
	float to_core = length(ray_from - ray_dir * max(dot(-ray_from, ray_dir), 0.0));
	float core = core_size * core_size / (core_size * core_size + to_core * to_core);
	core *= 0.7 + 0.3 * sin(t * core_pulse_speed);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 light = mix(arc_colour.rgb, hot_colour.rgb, clamp(lit, 0.0, 1.0)) * lit
			+ core_colour.rgb * core * core;

	ALBEDO = glass_tint.rgb;
	ALPHA = clamp(glass_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.6;
	ROUGHNESS = surface_roughness;

	EMISSION = light * glow_strength + rim_tint.rgb * fresnel * rim_strength;
}
