shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A whole world, the size of a marble, with its own day going round.
//
// The land is the easy half: noise, cut at a level, so the high ground is
// continent and the rest is sea. The day is the half that matters. A sun
// direction is swung round the marble, and everything else is decided by how
// this point stands to it: lit, in twilight, or in the dark.
//
// What sells it is what only happens on the night side. The cities come on --
// scattered points, but only where there is land, and only where the sun has
// gone -- so the terminator sweeps round and leaves a trail of lights behind it.
// Nothing else in the set has a feature that exists only in the part you can
// barely see.
//
// The clouds turn at their own rate over the top of it, and they are lit by the
// same sun, so they go dark as they cross into the night with everything else.

group_uniforms World;
uniform vec4 sea_colour : source_color = vec4(0.03, 0.16, 0.38, 1.0);
uniform vec4 shallow_colour : source_color = vec4(0.1, 0.45, 0.6, 1.0);
uniform vec4 land_colour : source_color = vec4(0.16, 0.4, 0.14, 1.0);
uniform vec4 dry_colour : source_color = vec4(0.55, 0.45, 0.2, 1.0);
uniform vec4 ice_colour : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform float land_scale : hint_range(0.5, 8.0) = 2.1;
// Where the sea level is cut. Higher drowns more of the world.
uniform float sea_level : hint_range(0.2, 0.8) = 0.52;

group_uniforms Day;
uniform vec3 spin_axis = vec3(0.0, 1.0, 0.0);
uniform float day_speed : hint_range(0.0, 1.0) = 0.06;
uniform vec4 night_colour : source_color = vec4(0.02, 0.03, 0.09, 1.0);
uniform vec4 dusk_colour : source_color = vec4(0.9, 0.45, 0.2, 1.0);
// How wide the band of twilight is.
uniform float dusk_width : hint_range(0.02, 0.6) = 0.22;

group_uniforms Cities;
uniform vec4 city_colour : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform float city_scale : hint_range(5.0, 60.0) = 30.0;
uniform float city_brightness : hint_range(0.0, 4.0) = 2.0;

group_uniforms Clouds;
uniform vec4 cloud_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cloud_scale : hint_range(0.5, 8.0) = 3.0;
uniform float cloud_level : hint_range(0.2, 0.9) = 0.55;
uniform float cloud_speed : hint_range(0.0, 0.5) = 0.02;

group_uniforms Air;
uniform vec4 air_colour : source_color = vec4(0.35, 0.6, 1.0, 1.0);
uniform float air_power : hint_range(0.5, 8.0) = 3.0;
uniform float air_strength : hint_range(0.0, 2.0) = 0.8;

varying vec3 surface_direction;


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	// The sun goes round the world rather than the world turning under it, so
	// the land can stay put on the marble and roll with it.
	vec3 axis = normalize(spin_axis);
	float hour = TIME * day_speed * TAU;
	vec3 sun = normalize(twist(normalize(vec3(1.0, 0.25, 0.3)), axis, hour));

	float ground = fbm4(d * land_scale);
	float is_land = smoothstep(sea_level, sea_level + 0.06, ground);

	// Ice at the poles, and a rim of shallow water round every coast.
	float pole = smoothstep(0.78, 0.95, abs(dot(d, axis)));
	float shallow = smoothstep(sea_level - 0.08, sea_level, ground) * (1.0 - is_land);

	vec3 surface = mix(sea_colour.rgb, shallow_colour.rgb, shallow);
	vec3 dirt = mix(land_colour.rgb, dry_colour.rgb, smoothstep(0.55, 0.75, ground));
	surface = mix(surface, dirt, is_land);
	surface = mix(surface, ice_colour.rgb, pole);

	// Cloud, turning at its own rate over the top of everything.
	float cloud = fbm3(d * cloud_scale + vec3(TIME * cloud_speed, 0.0, TIME * cloud_speed * 0.4));
	cloud = smoothstep(cloud_level, cloud_level + 0.18, cloud);
	surface = mix(surface, cloud_colour.rgb, cloud * 0.85);

	// Day, dusk and night.
	float sunward = dot(d, sun);
	float day = smoothstep(-dusk_width, dusk_width, sunward);
	float dusk = 1.0 - abs(sunward / dusk_width);
	dusk = clamp(dusk, 0.0, 1.0);

	vec3 lit = mix(night_colour.rgb, surface, day);
	lit = mix(lit, dusk_colour.rgb, dusk * 0.45);

	// The cities: only on land, only in the dark, and never under cloud.
	vec3 city_cell = worley3(d * city_scale);
	float city = smoothstep(0.3, 0.0, city_cell.x) * step(0.55, city_cell.z);
	city *= is_land * (1.0 - day) * (1.0 - cloud);

	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float air = pow(facing, air_power);

	ALBEDO = lit;

	METALLIC = 0.0;
	// Sea shines, land does not.
	SPECULAR = mix(0.9, 0.15, is_land);
	ROUGHNESS = mix(0.12, 0.85, max(is_land, cloud));

	EMISSION = city_colour.rgb * city * city_brightness
			+ air_colour.rgb * air * air_strength * mix(0.15, 1.0, day);
}
