shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Northern lights, hung round a night-dark ball.
//
// An aurora is not a cloud, it is a CURTAIN: a sheet that is thin one way and
// tall the other, rippling along its length. So the marble is measured in
// longitude and latitude rather than in three dimensions, and the curtain is a
// wave in longitude -- pushed out of true by noise that moves, which is what
// gives it its folds and its slow travel round the marble.
//
// Two more things carry the illusion. The light runs in fine vertical streaks,
// because it is following field lines down into the air. And the colour is keyed
// to HEIGHT, green low and violet where it thins out at the top, which is what
// the eye reads as an aurora rather than as a green smear.

group_uniforms Night;
uniform vec4 night_colour : source_color = vec4(0.02, 0.03, 0.07, 1.0);
uniform float night_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.05;

group_uniforms Curtain;
uniform vec4 low_colour : source_color = vec4(0.15, 1.0, 0.55, 1.0);
uniform vec4 high_colour : source_color = vec4(0.75, 0.25, 0.95, 1.0);
// How many curtains are hung round the marble.
uniform float curtain_folds : hint_range(1.0, 10.0) = 3.0;
// How narrow each one is.
uniform float curtain_sharpness : hint_range(1.0, 12.0) = 3.5;
// How far the moving noise pushes a curtain off its line.
uniform float wander : hint_range(0.0, 4.0) = 1.4;
// The fine vertical streaks the light runs in.
uniform float striae : hint_range(4.0, 120.0) = 45.0;
uniform float sway_speed : hint_range(0.0, 2.0) = 0.3;
uniform float glow_strength : hint_range(0.0, 6.0) = 2.2;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.5, 0.8, 0.9, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	float lon = atan(d.z, d.x);
	float height = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);
	float t = TIME * sway_speed;

	// Where this curtain has been pushed to. Sampled in longitude and height so
	// the fold travels along the curtain rather than across it.
	float bend = fbm3(vec3(lon * 1.5, height * 3.0, t)) * 2.0 - 1.0;

	float wave = sin(lon * curtain_folds + bend * wander + t * 1.5);
	float curtain = pow(clamp(wave, 0.0, 1.0), curtain_sharpness);

	// Fades in off the bottom of the marble and thins away at the top, so it
	// hangs rather than wrapping the whole ball.
	curtain *= smoothstep(0.05, 0.45, height) * (1.0 - smoothstep(0.7, 1.0, height));

	float streak = 0.6 + 0.4 * sin(lon * striae + bend * 5.0);

	vec3 colour = mix(low_colour.rgb, high_colour.rgb, smoothstep(0.25, 0.8, height));
	float lit = curtain * streak;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = night_colour.rgb;
	ALPHA = clamp(night_opacity + lit * 0.4 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.6;
	ROUGHNESS = surface_roughness;

	EMISSION = colour * lit * glow_strength + rim_tint.rgb * fresnel * rim_strength;
}
