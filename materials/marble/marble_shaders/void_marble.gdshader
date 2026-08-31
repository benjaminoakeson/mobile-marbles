shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Something with a hole in the middle of it.
//
// Everything here is measured from ONE plane through the marble. Near that plane
// is the disc: matter on its way in, drawn as streaks that are wound round the
// axis faster the closer to the plane they lie -- so the disc shears against
// itself and nothing in it ever comes back round together.
//
// Away from the plane is the dark, and stars in it. Near the plane the stars are
// swallowed, which is what gives the disc an inside edge to sit against.
//
// It is drawn dim on purpose: the light is what it is doing to the sky around
// it, not the thing itself.

group_uniforms Dark;
uniform vec4 dark_colour : source_color = vec4(0.012, 0.008, 0.03, 1.0);
uniform float dark_opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms Disc;
uniform vec3 disc_axis = vec3(0.25, 1.0, 0.15);
uniform vec4 disc_colour : source_color = vec4(0.55, 0.25, 0.95, 1.0);
uniform vec4 disc_hot : source_color = vec4(1.0, 0.85, 0.95, 1.0);
// How far the disc reaches either side of its plane.
uniform float disc_thickness : hint_range(0.05, 1.0) = 0.42;
// How finely the matter in it is drawn out into streaks.
uniform float streak_scale : hint_range(1.0, 30.0) = 9.0;
uniform float streak_stretch : hint_range(1.0, 20.0) = 7.0;
// How much faster the inside of the disc runs than the outside.
uniform float shear_speed : hint_range(0.0, 2.0) = 0.35;
uniform float disc_glow : hint_range(0.0, 4.0) = 1.5;

group_uniforms Stars;
uniform vec4 star_colour : source_color = vec4(0.9, 0.92, 1.0, 1.0);
uniform float star_scale : hint_range(4.0, 60.0) = 26.0;
uniform float star_threshold : hint_range(0.5, 0.99) = 0.88;
uniform float star_brightness : hint_range(0.0, 6.0) = 2.5;
uniform float twinkle_speed : hint_range(0.0, 6.0) = 1.2;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 axis = normalize(disc_axis);

	// How far off the disc's plane this point lies.
	float height = dot(d, axis);
	float in_disc = 1.0 - smoothstep(0.0, disc_thickness, abs(height));

	// Wound round the axis, and wound faster the nearer the plane.
	float haste = shear_speed / (abs(height) + 0.18);
	vec3 wound = twist(d, axis, TIME * haste);

	// Squashed across the plane, so the noise is drawn out into streaks that
	// run the way the matter is travelling.
	vec3 drawn = wound + axis * dot(wound, axis) * (streak_stretch - 1.0);
	float matter = pow(ridged(drawn * streak_scale), 3.0);

	// Hotter towards the inside edge of the disc.
	float heat = in_disc * in_disc;
	vec3 disc = mix(disc_colour.rgb, disc_hot.rgb, heat) * matter * in_disc;

	// Stars, in the dark and nowhere near the disc.
	vec3 star_cell = worley3(d * star_scale);
	float star = smoothstep(0.22, 0.0, star_cell.x) * step(star_threshold, star_cell.z);
	star *= mix(0.4, 1.0, 0.5 + 0.5 * sin(TIME * twinkle_speed + star_cell.z * TAU));
	star *= 1.0 - in_disc;

	ALBEDO = dark_colour.rgb;
	ALPHA = dark_opacity;

	METALLIC = 0.0;
	SPECULAR = 0.4;
	ROUGHNESS = 0.25;

	EMISSION = disc * disc_glow + star_colour.rgb * star * star_brightness;
}
