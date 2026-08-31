shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Snow being blown about inside the glass.
//
// One sheet of falling flakes reads as a pattern sliding over the marble. What
// makes it read as WEATHER is depth, and depth here is three sheets rather than
// one: a near one with big bright flakes moving fast, a far one with small dim
// flakes moving slowly, and one in between.
//
// That is parallax, and it is the whole design. The eye takes the fast, large,
// bright flakes as being close and the slow, small, faint ones as being deep
// inside, and the marble gains a thickness it has no other way of showing.
//
// All three sheets are carried sideways as well as down, because snow that only
// falls is rain.

group_uniforms Air;
uniform vec4 air_colour : source_color = vec4(0.5, 0.6, 0.72, 1.0);
uniform vec4 haze_colour : source_color = vec4(0.82, 0.88, 0.95, 1.0);
uniform float air_opacity : hint_range(0.0, 1.0) = 0.7;
uniform float haze_scale : hint_range(0.5, 10.0) = 2.6;
uniform float haze_drift : hint_range(0.0, 0.5) = 0.05;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.1;

group_uniforms Snow;
uniform vec4 flake_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The near sheet. The other two are worked out from it.
uniform float flake_scale : hint_range(4.0, 60.0) = 14.0;
uniform float flake_size : hint_range(0.05, 0.6) = 0.3;
uniform float fall_speed : hint_range(0.0, 2.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 2.0) = 0.35;
uniform float snow_brightness : hint_range(0.0, 3.0) = 1.2;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

const int SHEETS = 3;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	float snow = 0.0;

	for (int layer = 0; layer < SHEETS; layer++) {
		// Deeper sheets are finer grained, slower, and dimmer.
		float depth = float(layer);
		float scale = flake_scale * (1.0 + depth * 0.8);
		float speed = 1.0 / (1.0 + depth * 0.9);
		float dim = 1.0 / (1.0 + depth * 1.1);

		vec3 carried = vec3(
			-TIME * wind_speed * speed,
			-TIME * fall_speed * speed,
			TIME * wind_speed * speed * 0.35);

		vec3 cell = worley3(d * scale + carried + vec3(depth * 13.0));

		// Only some cells hold a flake at all, or the marble is a lace curtain.
		float flake = smoothstep(flake_size, 0.0, cell.x) * step(0.55, cell.z);
		snow = max(snow, flake * dim);
	}

	// The air itself is not clear: there is snow in it too far off to make out.
	float haze = fbm3(d * haze_scale + vec3(0.0, -TIME * haze_drift, 0.0));

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 air = mix(air_colour.rgb, haze_colour.rgb, smoothstep(0.35, 0.75, haze));

	ALBEDO = mix(air, flake_colour.rgb, snow);
	ALPHA = clamp(air_opacity + snow * 0.3 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.7;
	ROUGHNESS = surface_roughness;

	EMISSION = flake_colour.rgb * snow * snow_brightness * 0.4
			+ rim_tint.rgb * fresnel * rim_strength;
}
