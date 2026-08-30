shader_type sky;

// Deep space with the level hanging in the middle of it: coloured nebulae
// wound around a band of dust, and stars burning through the gaps.
//
// Built to match `nebula_marble.gdshader`, which is the marble with the same
// thing sealed inside it -- same domain-warped clouds, same cell-hashed stars,
// same trick of colouring the gas by WHERE it is rather than by how thick it is.
// A sky is the easier half of that problem: there is no volume to walk, only a
// direction, so everything here is a handful of reads on the unit sphere.
//
// The direction is used raw, which is what keeps this cheap. A sky shader is
// paid for at every pixel of the screen, so it is deliberately about five
// texture reads deep -- against the marble's eighty -- and the expensive parts
// of the look come from the warp and the colouring rather than from octaves.

group_uniforms Space;
// Empty sky. Not black: a background that is exactly zero reads as a hole in
// the render rather than as distance, and it gives glow nothing to sit on.
uniform vec4 space_colour : source_color = vec4(0.012, 0.011, 0.035, 1.0);
// Where the dust band thickens, space itself lifts towards this.
uniform vec4 haze_colour : source_color = vec4(0.055, 0.045, 0.115, 1.0);

group_uniforms Nebula;
uniform sampler3D cloud_noise : filter_linear, repeat_enable;
// Three colours through the clouds. A nebula is never one hue, and which of the
// three a patch of sky gets is picked by a slow noise field of its own, so the
// sky has warm regions and cool ones rather than one violet wash everywhere.
uniform vec4 warm_colour : source_color = vec4(1.0, 0.32, 0.60, 1.0);
uniform vec4 mid_colour : source_color = vec4(0.46, 0.24, 0.95, 1.0);
uniform vec4 cool_colour : source_color = vec4(0.10, 0.55, 0.95, 1.0);
// Bigger makes the clouds smaller and more numerous.
uniform float cloud_scale : hint_range(0.3, 8.0) = 1.9;
// How far apart the regions of one colour are. Well below `cloud_scale` on
// purpose: the hue has to drift across many clouds, not change within one.
uniform float hue_scale : hint_range(0.1, 3.0) = 0.55;
// Raise it and only the densest gas survives, so the sky empties out.
uniform float cloud_threshold : hint_range(0.0, 0.95) = 0.56;
uniform float cloud_softness : hint_range(0.01, 0.8) = 0.34;
uniform float nebula_glow : hint_range(0.0, 4.0) = 1.0;
// How far a second noise field drags the first one around before it is read.
// This is what frays the clouds into wisps instead of blobs.
uniform float warp_amount : hint_range(0.0, 1.0) = 0.42;
// A very slow churn, so a sky watched for a whole level is never quite still.
// Keep it small: the sky is the one thing on screen that should not move.
uniform float drift_speed : hint_range(0.0, 0.05) = 0.004;

group_uniforms Band;
// The plane the dust gathers in -- a galaxy seen from inside it. This vector is
// the POLE, so the band itself lies around the great circle at right angles.
uniform vec3 band_axis = vec3(0.28, 1.0, -0.16);
// How far off that circle the band reaches, as a fraction of a quarter turn.
uniform float band_width : hint_range(0.05, 1.0) = 0.5;
// How much of the gas is held into the band. At 0 the clouds are spread evenly
// over the whole sky, which reads as fog; at 1 there is nothing outside it.
uniform float band_focus : hint_range(0.0, 1.0) = 0.85;

group_uniforms Stars;
// Two colours, mixed per star, because a field of identical white pinpricks
// reads as noise rather than as stars.
uniform vec4 star_cool : source_color = vec4(0.72, 0.84, 1.0, 1.0);
uniform vec4 star_warm : source_color = vec4(1.0, 0.86, 0.68, 1.0);
// The bright, sparse layer. Bigger packs more in.
uniform float star_scale : hint_range(8.0, 200.0) = 46.0;
// Raise it for fewer stars. Most cells should be empty.
uniform float star_threshold : hint_range(0.5, 0.999) = 0.855;
uniform float star_size : hint_range(0.02, 0.45) = 0.17;
uniform float star_brightness : hint_range(0.0, 6.0) = 2.6;
// And a denser, dimmer one behind it, which is what gives the field depth.
uniform float dust_scale : hint_range(8.0, 400.0) = 128.0;
uniform float dust_threshold : hint_range(0.5, 0.999) = 0.80;
uniform float dust_brightness : hint_range(0.0, 4.0) = 0.75;
uniform float twinkle_speed : hint_range(0.0, 8.0) = 1.4;


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}


// One layer of stars: the sphere is cut into cells, most of them empty, and the
// few that are not get a point placed somewhere inside them.
//
// Held clear of the cell walls so no star is cut in half by one, and positioned
// from hashes of its own rather than from the seed that selected it -- reusing
// that seed puts every star at the same corner of its cell, which lines the
// whole field up into rows.
vec3 star_layer(vec3 dir, float scale, float threshold, float size, float twinkle) {
	vec3 sd = dir * scale;
	vec3 cell = floor(sd);
	float seed = hash13(cell);
	if (seed < threshold) {
		return vec3(0.0);
	}

	vec3 offset = clamp(
		vec3(hash13(cell + 7.7), hash13(cell + 17.3), hash13(cell + 43.1)),
		vec3(size), vec3(1.0 - size));
	float d = length(fract(sd) - offset);

	// Wide support, tight peak: the falloff reaches most of the cell so the star
	// has a faint halo, but the bright part stays a pinprick.
	float spark = pow(1.0 - min(d / size, 1.0), 3.0);

	// Brightness varies per star as well as over time. Without the first of
	// these every star is the same magnitude, which no sky has ever been.
	spark *= mix(0.35, 1.0, hash13(cell + 61.9));
	spark *= mix(1.0 - twinkle, 1.0, 0.5 + 0.5 * sin(TIME * twinkle_speed + seed * TAU));

	return mix(star_cool.rgb, star_warm.rgb, hash13(cell + 91.7)) * spark;
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float drift = TIME * drift_speed;

	// How near this direction is to the plane the dust gathers in. `band_axis`
	// is the pole, so the band is where the direction is at right angles to it.
	float off_plane = abs(dot(dir, normalize(band_axis)));
	float band = 1.0 - smoothstep(0.0, band_width, off_plane);

	// Read the noise once to displace where the real read lands. Domain warping:
	// cheap, and the only reason these clouds have wisps and hooks rather than
	// the soft even lumps raw fractal noise gives you.
	vec3 q = dir * cloud_scale + vec3(drift, drift * 0.6, -drift * 0.4);
	vec3 warp = vec3(
		texture(cloud_noise, q).r,
		texture(cloud_noise, q + vec3(0.41, 0.17, 0.83)).r,
		texture(cloud_noise, q + vec3(0.77, 0.59, 0.23)).r
	) * 2.0 - 1.0;

	float n = texture(cloud_noise, q + warp * warp_amount).r;

	// Everything below the threshold is empty space, and the band decides how
	// much of what is left survives out at the poles.
	float gas = smoothstep(cloud_threshold, cloud_threshold + cloud_softness, n);
	gas *= mix(1.0, band, band_focus);

	// Colour by WHERE, not by how thick. Keying the hue off density gives one
	// flat violet, because the density hardly ever climbs high enough to reach
	// the far end of the ramp. A slow field of its own instead means the sky has
	// a rose quarter and a blue one, with the violet between them -- and the
	// densest knots are then pushed back towards the warm end, so the bright
	// cores of the clouds glow hotter wherever they happen to sit.
	float hue = texture(cloud_noise, dir * hue_scale + vec3(3.1, 1.7, 5.3)).r;
	vec3 tint = mix(cool_colour.rgb, mid_colour.rgb, smoothstep(0.30, 0.55, hue));
	tint = mix(tint, warm_colour.rgb, smoothstep(0.52, 0.80, hue));
	tint = mix(tint, warm_colour.rgb, smoothstep(0.55, 1.0, gas) * 0.45);

	vec3 colour = mix(space_colour.rgb, haze_colour.rgb, band * 0.85);
	colour += tint * gas * nebula_glow;

	// Stars are skipped while the sky is being baked into the radiance cubemap.
	// At that resolution a pinprick either falls between two texels and vanishes
	// or lands on one and lights the whole level from it, and either way stars
	// contribute nothing to ambient that the gas has not already given. The
	// twinkle would also crawl over everything the sky lights.
	if (!AT_CUBEMAP_PASS) {
		// Dimmed by whatever gas is in front of them, so the clouds read as
		// being nearer than the stars rather than painted over them.
		float behind = 1.0 - gas * 0.7;
		colour += star_layer(dir, star_scale, star_threshold, star_size, 0.55)
				* star_brightness * behind;
		colour += star_layer(dir, dust_scale, dust_threshold, star_size * 1.6, 0.25)
				* dust_brightness * behind;
	}

	COLOR = colour;
}
