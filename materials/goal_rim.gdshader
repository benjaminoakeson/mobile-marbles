shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// The ring the goal's glass sits in: a dark polished band with glitter caught
// inside it and gusts of light running round it.
//
// Both effects hang off the torus's own UVs, which suit them exactly: u runs the
// whole way round the ring and v round the tube, so a gust is a wave in u and
// travels round the rim, and the seam at u = 0 closes because every wave in it
// is a whole number of cycles.

group_uniforms body;

uniform vec4 base_colour : source_color = vec4(0.09, 0.10, 0.14, 1.0);

// The colour of the shaded side of the tube. The rim is a thin band and reads as
// flat without it, whatever the light is doing.
uniform vec4 deep_colour : source_color = vec4(0.02, 0.025, 0.04, 1.0);
uniform float roundness : hint_range(0.0, 1.0, 0.01) = 0.6;

uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.7;

// A cold edge light, so the ring reads against a dark level as well as a bright
// one without waiting on the level's own lamp.
uniform vec4 edge_colour : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float edge_strength : hint_range(0.0, 3.0, 0.01) = 0.5;
uniform float edge_sharpness : hint_range(1.0, 8.0, 0.1) = 3.5;

group_uniforms sparkles;

uniform vec4 sparkle_colour : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform float sparkle_strength : hint_range(0.0, 6.0, 0.05) = 3.0;

// Cells around the ring, then round the tube. They want to come out roughly
// square, and the torus's two ways round are nothing like the same length -- the
// ring is some six metres and the tube a third of one -- so this is two numbers
// rather than one. The defaults suit the goal's own ring.
uniform vec2 sparkle_cells = vec2(90.0, 5.0);
uniform float sparkle_size : hint_range(0.02, 0.5, 0.01) = 0.2;
uniform float sparkle_speed : hint_range(0.0, 8.0, 0.05) = 1.9;

// How much of the time a sparkle is dark. High is the point: glitter is mostly
// off, catching the light for a moment and going out again.
uniform float sparkle_rarity : hint_range(1.0, 40.0, 0.5) = 14.0;

// How far the glitter slides under the surface as the camera moves. This is the
// whole trick behind "inside": nothing that sits exactly on a surface looks like
// it is under one, and a little travel against the view sells the depth.
uniform float sparkle_depth : hint_range(0.0, 0.2, 0.001) = 0.035;

group_uniforms wind;

uniform vec4 wind_colour : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float wind_strength : hint_range(0.0, 4.0, 0.01) = 1.3;
uniform float wind_speed : hint_range(0.0, 2.0, 0.01) = 0.16;

// How tight the gusts are. Low is a broad swell all the way round; high is a
// narrow bright streak chasing itself.
uniform float wind_focus : hint_range(1.0, 12.0, 0.1) = 2.4;

// How much brighter the glitter burns inside a gust. The two effects are worth
// far more together than apart: the wind picks the sparkles up as it passes.
uniform float wind_lifts_sparkles : hint_range(0.0, 6.0, 0.1) = 2.5;


float hash21(vec2 at) {
	vec2 wrapped = fract(at * vec2(233.34, 851.73));
	wrapped += dot(wrapped, wrapped + 23.45);
	return fract(wrapped.x * wrapped.y);
}


// One twinkle per cell, each on its own clock.
//
// The spot is held to the middle half of its cell so it never crosses into the
// next one, which is what lets this look at a single cell instead of the nine
// around it -- a third of the work, and nothing is clipped in half.
float glitter(vec2 at) {
	vec2 grid = at * sparkle_cells;
	vec2 cell = floor(grid);
	vec2 inside = fract(grid);

	vec2 spot = vec2(0.25) + 0.5 * vec2(hash21(cell + 11.3), hash21(cell + 27.7));
	float clock = hash21(cell) * TAU + TIME * sparkle_speed;
	float lit = pow(max(sin(clock), 0.0), sparkle_rarity);

	// Every grain its own size. All of them the same reads as a printed dot
	// screen rather than as anything caught in the material.
	float grain = sparkle_size * (0.55 + 0.9 * hash21(cell + 5.1));

	return (1.0 - smoothstep(0.0, grain, distance(inside, spot))) * lit;
}


// Gusts running round the ring: three waves at speeds that do not divide into
// one another, so the pattern never obviously repeats. Whole numbers of cycles,
// so nothing shows at the seam where u comes back round to zero.
float gust(float around) {
	float swell = sin((around - TIME * wind_speed) * TAU)
			+ 0.62 * sin((around * 2.0 - TIME * wind_speed * 1.63) * TAU + 1.7)
			+ 0.43 * sin((around * 3.0 - TIME * wind_speed * 0.71) * TAU + 3.1);
	return pow(clamp(swell / 2.05, 0.0, 1.0), wind_focus);
}


void fragment() {
	// Round the tube, 0 at one side and 1 at the other. Shades the band so it
	// reads as round rather than as a flat strip.
	float across = abs(UV.y - 0.5) * 2.0;
	ALBEDO = mix(base_colour.rgb, deep_colour.rgb, smoothstep(0.0, 1.0, across) * roundness);

	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	// The glitter is sampled a little off where the surface actually is, in the
	// direction the surface is being looked at from, so it drifts as the camera
	// moves the way something set below the surface would.
	vec3 eye = normalize(VIEW);
	vec2 drift = vec2(dot(eye, normalize(TANGENT)), dot(eye, normalize(BINORMAL)))
			* sparkle_depth;
	float spark = glitter(UV + drift);

	float wind = gust(UV.x);

	float facing = abs(dot(normalize(NORMAL), eye));
	float edge = pow(1.0 - facing, edge_sharpness);

	EMISSION = wind_colour.rgb * wind * wind_strength
			+ sparkle_colour.rgb * spark * sparkle_strength * (1.0 + wind * wind_lifts_sparkles)
			+ edge_colour.rgb * edge * edge_strength;
}
