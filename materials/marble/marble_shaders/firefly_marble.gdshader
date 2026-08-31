shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A jar with fireflies in it.
//
// The motes are actual points, not a field thresholded until points fall out of
// it. Each one is given a place, a slow wander of its own, and a rise that wraps
// round when it reaches the top -- so they drift apart, cross, and never move as
// a shoal.
//
// A pixel is lit by how near its view ray passes to each mote, falling off with
// the square of the miss. That is what a small light seen through glass does,
// and it costs one distance per mote per pixel: no volume to walk, and the motes
// stay crisp instead of smearing into the ray as marched points do.
//
// They blink rather than glow steadily, each on its own beat, and a firefly is
// dark most of the time -- which is why the beat is raised to a power.

group_uniforms Jar;
uniform vec4 glass_tint : source_color = vec4(0.03, 0.055, 0.035, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.88;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.04;

group_uniforms Motes;
uniform vec4 mote_colour : source_color = vec4(1.0, 0.95, 0.45, 1.0);
uniform vec4 mote_hot : source_color = vec4(1.0, 1.0, 0.85, 1.0);
uniform int mote_count : hint_range(1, 24) = 14;
uniform float mote_size : hint_range(0.005, 0.15) = 0.032;
uniform float glow_strength : hint_range(0.0, 6.0) = 2.6;

group_uniforms Drift;
uniform float rise_speed : hint_range(0.0, 0.5) = 0.045;
uniform float wander_speed : hint_range(0.0, 2.0) = 0.35;
uniform float wander_amount : hint_range(0.0, 0.6) = 0.22;

group_uniforms Blink;
uniform float blink_speed : hint_range(0.0, 6.0) = 1.1;
// Higher leaves a mote dark for longer between flashes.
uniform float blink_sharpness : hint_range(1.0, 10.0) = 4.0;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.6, 0.8, 0.5, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;

uniform float marble_radius = 0.5;

const int MAX_MOTES = 24;

varying vec3 obj_position;
varying vec3 obj_view;


// Where mote `k` is at time `t`, in a marble one unit across.
vec3 mote_position(float k, float t) {
	vec3 seed = hash33(vec3(k * 1.7, 3.3, 9.1));

	// Up, and round again at the top.
	float height = fract(seed.y + t * rise_speed) * 1.7 - 0.85;

	vec3 wander = vec3(
		sin(t * wander_speed * (0.6 + seed.x) + seed.z * TAU),
		sin(t * wander_speed * (0.4 + seed.y) + seed.x * TAU) * 0.4,
		cos(t * wander_speed * (0.5 + seed.z) + seed.y * TAU));

	vec3 place = vec3(seed.x * 1.5 - 0.75, height, seed.z * 1.5 - 0.75)
			+ wander * wander_amount;

	// Kept off the glass, so no mote is ever cut in half by the shell.
	float reach = length(place);
	return place * min(1.0, 0.82 / max(reach, 0.0001));
}


void vertex() {
	obj_position = VERTEX;

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 ray_from = obj_position / marble_radius;
	vec3 ray_dir = normalize(obj_view);
	float t = TIME;

	vec3 light = vec3(0.0);

	for (int k = 0; k < MAX_MOTES; k++) {
		if (k >= mote_count) {
			break;
		}

		vec3 place = mote_position(float(k), t);

		vec3 to_mote = place - ray_from;
		float along = max(dot(to_mote, ray_dir), 0.0);
		float miss = length(to_mote - ray_dir * along);

		float lamp = mote_size * mote_size / (mote_size * mote_size + miss * miss);

		// Dark most of the time, and bright for a moment.
		float phase = hash13(vec3(float(k), 5.5, 1.9)) * TAU;
		float blink = pow(0.5 + 0.5 * sin(t * blink_speed + phase), blink_sharpness);

		light += mix(mote_colour.rgb, mote_hot.rgb, lamp) * lamp * lamp * blink;
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = glass_tint.rgb;
	ALPHA = clamp(glass_opacity + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.7;
	ROUGHNESS = surface_roughness;

	EMISSION = light * glow_strength + rim_tint.rgb * fresnel * rim_strength;
}
