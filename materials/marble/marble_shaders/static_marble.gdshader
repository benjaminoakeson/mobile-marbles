shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// An untuned television, wrapped round a ball.
//
// Every other skin in the set is smooth in time: it is asked what it looks like
// at this instant and the answer changes a little from the last. This one is the
// opposite, and deliberately so. The noise is held still for a FRAME at a time --
// the time is rounded down to the nearest frame before it is used -- so the
// picture snaps from one arrangement to a completely unrelated one, twenty-odd
// times a second, the way real snow does.
//
// Over the top go the two things that say television rather than noise: fine
// scan lines, and a bar of misaligned picture rolling slowly up the screen with
// the snow inside it shifted sideways.

group_uniforms Screen;
uniform vec4 screen_colour : source_color = vec4(0.62, 0.65, 0.7, 1.0);
uniform vec4 dark_colour : source_color = vec4(0.04, 0.045, 0.06, 1.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.35;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.9;

group_uniforms Snow;
// How fine the grain of the snow is.
uniform float snow_scale : hint_range(20.0, 400.0) = 150.0;
// How many times a second the picture is redrawn.
uniform float frame_rate : hint_range(1.0, 60.0) = 24.0;
// How much of the screen is snow rather than black.
uniform float snow_level : hint_range(0.0, 1.0) = 0.45;

group_uniforms Lines;
uniform float scan_lines : hint_range(10.0, 200.0) = 70.0;
uniform float scan_depth : hint_range(0.0, 1.0) = 0.35;
// How fast the picture rolls.
uniform float roll_speed : hint_range(0.0, 2.0) = 0.15;
uniform float band_height : hint_range(0.02, 0.5) = 0.12;
// How far the picture is thrown sideways inside the rolling band.
uniform float band_shift : hint_range(0.0, 1.0) = 0.3;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	// The frame this is. Rounded down, so the snow holds still between frames
	// and then jumps -- which is the whole character of the thing.
	float frame = floor(TIME * frame_rate);

	// The rolling band of misaligned picture.
	float height = d.y;
	float roll = fract(TIME * roll_speed);
	float band_at = 1.0 - roll * 2.0;
	float in_band = 1.0 - smoothstep(0.0, band_height, abs(height - band_at));

	// Inside the band the picture is thrown sideways.
	vec3 shifted = twist(d, vec3(0.0, 1.0, 0.0), in_band * band_shift);

	float snow = hash13(shifted * snow_scale + frame * 7.13);
	snow = smoothstep(snow_level, snow_level + 0.35, snow);

	// Scan lines, and a brighter edge along the band where the picture tears.
	float lines = 1.0 - scan_depth * (0.5 + 0.5 * sin(height * scan_lines));
	float tear = smoothstep(band_height * 0.6, band_height, abs(height - band_at)) * in_band;

	vec3 picture = mix(dark_colour.rgb, screen_colour.rgb, snow) * lines;
	picture = mix(picture, screen_colour.rgb, tear * 0.5);

	ALBEDO = picture;

	METALLIC = 0.0;
	SPECULAR = 0.3;
	ROUGHNESS = surface_roughness;

	EMISSION = picture * glow_strength * 0.5;
}
