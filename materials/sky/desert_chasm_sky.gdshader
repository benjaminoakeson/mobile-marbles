shader_type sky;

// desert_sky.gdshader with the desert chasm baked into it as a cubemap.
//
// Six 1024px faces rendered out of Blender from the middle of the level at eye
// height: a 234-356 m wide, 120 m deep sandstone chasm, dune fields running
// across the prevailing wind, two pyramids on the skyline, and scattered rock
// outcrops. Alpha is the silhouette, so the dome, the dust band, the glare and
// the sun disc all still show above and through it.
//
// The bake is sampled with the SHIMMERED direction, so the heat haze ripples
// the horizon rock and the pyramids along with the sky rather than sliding over
// the top of them.
//
// Costs one cubemap fetch and no geometry: no draw calls, no triangles, no
// shadow work. A sky cannot parallax, so the chasm will not shift as a level is
// rolled across; it was baked from the origin, and the further a level strays
// from there the more that shows.

group_uniforms Desert;

// Six-face bake. Alpha 1 on terrain and pyramids, 0 where the sky shows.
uniform samplerCube desert : source_color, filter_linear_mipmap;

// The bake is tonemapped a second time by the Environment.
uniform float desert_brightness : hint_range(0.0, 3.0) = 1.1;

// Turns the landscape, to put the pyramids behind a particular level.
uniform float desert_yaw_degrees : hint_range(-180.0, 180.0) = 0.0;

// Fades the landscape out, for levels that want the bare sky.
uniform float desert_opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms Sky;
uniform vec4 zenith : source_color = vec4(0.13, 0.38, 0.82, 1.0);
uniform vec4 horizon : source_color = vec4(0.96, 0.89, 0.72, 1.0);
uniform vec4 below_horizon : source_color = vec4(0.78, 0.66, 0.46, 1.0);
uniform float heat_rise : hint_range(0.05, 2.0) = 0.38;

group_uniforms Sun;
uniform vec4 sun_colour : source_color = vec4(1.0, 0.97, 0.90, 1.0);
uniform float sun_size_degrees : hint_range(0.5, 20.0) = 3.2;
uniform float sun_energy : hint_range(0.0, 30.0) = 14.0;
uniform vec4 glare_colour : source_color = vec4(1.0, 0.94, 0.78, 1.0);
uniform float glare_spread : hint_range(1.0, 64.0) = 9.0;
uniform float glare_strength : hint_range(0.0, 3.0) = 0.5;
uniform vec3 sun_from = vec3(0.4, 0.62, 0.68);

group_uniforms Dust;
uniform sampler3D haze_noise : filter_linear, repeat_enable;
uniform vec4 dust_colour : source_color = vec4(0.88, 0.78, 0.60, 1.0);
uniform float dust_strength : hint_range(0.0, 1.0) = 0.35;
uniform float dust_height : hint_range(0.02, 1.0) = 0.20;
uniform float shimmer : hint_range(0.0, 0.1) = 0.022;
uniform float shimmer_scale : hint_range(1.0, 40.0) = 14.0;
uniform float shimmer_speed : hint_range(0.0, 4.0) = 0.9;


void sky() {
	vec3 dir = normalize(EYEDIR);

	float low = 1.0 - smoothstep(0.0, dust_height * 1.6, abs(dir.y));
	if (!AT_CUBEMAP_PASS && low > 0.001) {
		vec3 at = dir * shimmer_scale + vec3(0.0, TIME * shimmer_speed, 0.0);
		float wobble = texture(haze_noise, at).r * 2.0 - 1.0;
		dir = normalize(dir + vec3(0.0, wobble * shimmer * low, 0.0));
	}

	float up = dir.y;
	vec3 sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(sun_from);
	float towards_sun = dot(dir, sun);

	vec3 colour = mix(horizon.rgb, zenith.rgb, pow(clamp(up, 0.0, 1.0), heat_rise));
	colour = mix(colour, below_horizon.rgb, smoothstep(0.0, -0.18, up));

	float band = 1.0 - smoothstep(0.0, dust_height, abs(up));
	colour = mix(colour, dust_colour.rgb, band * dust_strength);

	colour += glare_colour.rgb * pow(max(towards_sun, 0.0), glare_spread) * glare_strength;

	float edge = radians(sun_size_degrees);
	float angle = acos(clamp(towards_sun, -1.0, 1.0));
	colour += sun_colour.rgb * (1.0 - smoothstep(edge * 0.7, edge, angle)) * sun_energy;

	// The land last and over everything -- it is solid, so a pyramid on the
	// skyline eclipses the sun rather than the other way round.
	float yaw = radians(desert_yaw_degrees);
	float cy = cos(yaw);
	float sy = sin(yaw);
	vec3 look = vec3(dir.x * cy - dir.z * sy, dir.y, dir.x * sy + dir.z * cy);

	vec4 land = texture(desert, look);
	colour = mix(colour, land.rgb * desert_brightness, land.a * desert_opacity);

	// The dust band again, but only a breath of it, laid over the near rim so
	// the baked rock settles into the same air as the sky it sits in.
	colour = mix(colour, dust_colour.rgb, band * dust_strength * 0.35 * land.a);

	COLOR = colour;
}
