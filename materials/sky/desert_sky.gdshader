shader_type sky;

// Noon over sand: a hard blue overhead bleaching to white heat at the horizon,
// a sun with far too much glare to look at, and a band of dust hanging over the
// ground that shimmers where the air is hottest.
//
// The forest sky next door is the same idea dressed for a nice day, and the
// tempting thing was to make one shader serve both on different colours. They
// part company on the two things that actually say DESERT rather than "sunny":
// there are no clouds at all, and the horizon is a wall of haze that wobbles.
// Neither belongs in a shader whose job is fair-weather cumulus.
//
// The sun follows the level's own DirectionalLight, so the glare is where the
// shadows say it is. LIGHT0_DIRECTION already points TOWARDS the light -- it is
// not the way the light travels, and negating it puts the sun underground.

group_uniforms Sky;
uniform vec4 zenith : source_color = vec4(0.13, 0.38, 0.82, 1.0);
uniform vec4 horizon : source_color = vec4(0.96, 0.89, 0.72, 1.0);

// What shows below the horizon. The levels float, so this is on screen a great
// deal -- pale sand, not black, or the track reads as hanging over a pit.
uniform vec4 below_horizon : source_color = vec4(0.78, 0.66, 0.46, 1.0);

// How far up the dome the heat reaches. Low keeps the blue; high bleaches most
// of the sky, which is what a really punishing one looks like.
uniform float heat_rise : hint_range(0.05, 2.0) = 0.38;

group_uniforms Sun;
uniform vec4 sun_colour : source_color = vec4(1.0, 0.97, 0.90, 1.0);
uniform float sun_size_degrees : hint_range(0.5, 20.0) = 3.2;
uniform float sun_energy : hint_range(0.0, 30.0) = 14.0;

// The glare. Wide and strong on purpose: it is most of what makes a desert sky
// read as hot rather than merely cloudless.
uniform vec4 glare_colour : source_color = vec4(1.0, 0.94, 0.78, 1.0);
uniform float glare_spread : hint_range(1.0, 64.0) = 9.0;
uniform float glare_strength : hint_range(0.0, 3.0) = 0.5;

uniform vec3 sun_from = vec3(0.4, 0.62, 0.68);

group_uniforms Dust;
uniform sampler3D haze_noise : filter_linear, repeat_enable;
uniform vec4 dust_colour : source_color = vec4(0.88, 0.78, 0.60, 1.0);

// How thick the band over the horizon is, and how far up it reaches.
uniform float dust_strength : hint_range(0.0, 1.0) = 0.35;
uniform float dust_height : hint_range(0.02, 1.0) = 0.20;

// How hard the air wobbles just above the ground, and how fast. This is the
// sky's own share of the heat warp -- the world's share is a screen effect, see
// heat_haze.gdshader.
uniform float shimmer : hint_range(0.0, 0.1) = 0.022;
uniform float shimmer_scale : hint_range(1.0, 40.0) = 14.0;
uniform float shimmer_speed : hint_range(0.0, 4.0) = 0.9;


void sky() {
	vec3 dir = normalize(EYEDIR);

	// The wobble, strongest at the horizon and gone by the time you look up.
	// Applied to the DIRECTION, so everything downstream -- gradient, dust, even
	// the glare -- ripples together rather than one layer sliding over another.
	float low = 1.0 - smoothstep(0.0, dust_height * 1.6, abs(dir.y));
	if (!AT_CUBEMAP_PASS && low > 0.001) {
		vec3 at = dir * shimmer_scale + vec3(0.0, TIME * shimmer_speed, 0.0);
		float wobble = texture(haze_noise, at).r * 2.0 - 1.0;
		dir = normalize(dir + vec3(0.0, wobble * shimmer * low, 0.0));
	}

	float up = dir.y;
	vec3 sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION) : normalize(sun_from);
	float towards_sun = dot(dir, sun);

	// Blue overhead, white heat at the rim, sand below it.
	vec3 colour = mix(horizon.rgb, zenith.rgb, pow(clamp(up, 0.0, 1.0), heat_rise));
	colour = mix(colour, below_horizon.rgb, smoothstep(0.0, -0.18, up));

	// The dust band. Thickest on the horizon itself and thinning both ways, so
	// it reads as something lying ON the ground rather than as a stripe painted
	// across the sky.
	float band = 1.0 - smoothstep(0.0, dust_height, abs(up));
	colour = mix(colour, dust_colour.rgb, band * dust_strength);

	// Glare, then the disc on top of it.
	colour += glare_colour.rgb * pow(max(towards_sun, 0.0), glare_spread) * glare_strength;

	float edge = radians(sun_size_degrees);
	float angle = acos(clamp(towards_sun, -1.0, 1.0));
	colour += sun_colour.rgb * (1.0 - smoothstep(edge * 0.7, edge, angle)) * sun_energy;

	COLOR = colour;
}
