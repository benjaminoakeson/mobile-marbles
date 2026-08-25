shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A marble with a nebula sealed inside it: dark empty space, a few coloured
// clouds of gas wound into a spiral, and stars burning through the gaps.
//
// Built the same way as glass_marble.gdshader -- the view ray is walked
// STRAIGHT across the chord from where it enters the glass to where it leaves,
// gathering whatever it passes through. So the nebula is a real volume in the
// marble's own space and swings round as the marble rolls, and there is no
// screen texture, so it behaves the same on the mobile renderer as anywhere.
//
// Two things make it read as a nebula rather than as fog:
//
//   * The sample point is twisted around an axis by an angle that grows towards
//     the core, which drags a shapeless cloud out into spiral arms.
//   * The gas is gathered ADDITIVELY, not composited front-to-back. Gas glows;
//     two wisps stacked up should be brighter than one, not merely closer.
//     Coverage is still tracked separately so the shell can turn solid where
//     the cloud is thick.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.80, 0.86, 1.0, 1.0);
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;
// The empty space between the clouds. Not black -- a marble that reads as a
// hole punched in the level is unpleasant to look at.
uniform vec4 void_colour : source_color = vec4(0.03, 0.02, 0.09, 1.0);
uniform float void_opacity : hint_range(0.0, 1.0) = 0.80;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

group_uniforms Nebula;
// Three colours through the cloud: hottest at the dense core, cooling outwards.
// A nebula is never one hue, and mixing by density is what gives it depth.
uniform vec4 core_colour : source_color = vec4(1.0, 0.55, 0.85, 1.0);
uniform vec4 mid_colour : source_color = vec4(0.55, 0.25, 0.95, 1.0);
uniform vec4 outer_colour : source_color = vec4(0.10, 0.45, 0.90, 1.0);
uniform sampler3D nebula_noise : filter_linear, repeat_enable;
// Bigger makes the clouds smaller and more numerous.
uniform float cloud_scale : hint_range(0.2, 6.0) = 1.1;
// Raise it and only the densest knots of gas survive, so the marble empties out.
uniform float cloud_threshold : hint_range(0.0, 0.95) = 0.54;
uniform float cloud_softness : hint_range(0.01, 0.8) = 0.26;
uniform float cloud_density : hint_range(0.0, 4.0) = 1.6;
uniform float nebula_glow : hint_range(0.0, 4.0) = 1.5;
// How far a second noise field drags the first one around before it is read.
// This is what frays the clouds into wisps instead of blobs.
uniform float warp_amount : hint_range(0.0, 1.0) = 0.45;

group_uniforms Spiral;
uniform vec3 spiral_axis = vec3(0.2, 1.0, 0.1);
// Full turns of twist between the shell and the core. Around one is enough to
// read as arms; past two it shears into stripes.
uniform float spiral_turns : hint_range(0.0, 3.0) = 0.8;
// A slow churn so the gas is never quite still. Keep it low -- fast is cheap.
uniform float drift_speed : hint_range(0.0, 0.5) = 0.03;

group_uniforms Stars;
uniform vec4 star_colour : source_color = vec4(1.0, 0.95, 0.88, 1.0);
// Bigger packs more stars in.
uniform float star_scale : hint_range(4.0, 60.0) = 20.0;
// Raise it for fewer stars. Most cells should be empty.
uniform float star_threshold : hint_range(0.5, 0.995) = 0.74;
uniform float star_size : hint_range(0.02, 0.45) = 0.25;
// How deep inside the marble the stars sit, as a fraction of its radius.
uniform float star_shell : hint_range(0.2, 0.95) = 0.78;
uniform float star_brightness : hint_range(0.0, 4.0) = 3.4;
uniform float twinkle_speed : hint_range(0.0, 8.0) = 2.0;

uniform float marble_radius = 0.5;

const int STEPS = 20;

varying vec3 obj_position;
varying vec3 obj_normal;
varying vec3 obj_view;


// Rodrigues' rotation. `axis` must already be normalised.
vec3 twist(vec3 p, vec3 axis, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}


void vertex() {
	obj_position = VERTEX;
	obj_normal = NORMAL;

	// The ray from the eye to this vertex in the marble's own space, so the walk
	// below does not care how the marble is placed or rotated.
	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 p = obj_position;
	vec3 v = normalize(obj_view);

	// Straight through, no bending -- see the note at the top.
	float b = dot(p, v);
	float c = dot(p, p) - marble_radius * marble_radius;
	float exit_t = -b + sqrt(max(b * b - c, 0.0));

	vec3 axis = normalize(spiral_axis);
	float drift = TIME * drift_speed;

	// Break the sampling positions up per pixel. Twenty even steps through soft
	// gas leaves visible rings; a little jitter trades those for a faint grain
	// nobody notices.
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);

	vec3 gas = vec3(0.0);
	float coverage = 0.0;

	for (int i = 0; i < STEPS; i++) {
		float along = (float(i) + jitter) / float(STEPS);
		vec3 unit_q = (p + v * (exit_t * along)) / marble_radius;
		float r = length(unit_q);

		// Wind the arms in towards the core.
		vec3 sp = twist(unit_q, axis, spiral_turns * TAU * (1.0 - clamp(r, 0.0, 1.0)));

		vec3 uvw = sp * cloud_scale * 0.5 + vec3(0.5) + vec3(drift, drift * 0.6, -drift * 0.4);

		// Read the noise once to displace where the second read lands. Domain
		// warping: cheap, and the only reason these clouds have wisps and hooks
		// rather than the soft even lumps raw fractal noise gives you.
		vec3 warp = vec3(
			texture(nebula_noise, uvw).r,
			texture(nebula_noise, uvw + vec3(0.41, 0.17, 0.83)).r,
			texture(nebula_noise, uvw + vec3(0.77, 0.59, 0.23)).r
		) * 2.0 - 1.0;

		float n = texture(nebula_noise, uvw + warp * warp_amount).r;

		// Everything below the threshold is empty space.
		float gas_amount = smoothstep(cloud_threshold, cloud_threshold + cloud_softness, n);

		// Thin the gas out towards the shell so the cloud ends in space rather
		// than in a hard edge against the glass, and keep a little more of it in
		// the middle so the marble has a centre of mass.
		float shell = 1.0 - smoothstep(0.70, 1.0, r);
		gas_amount *= shell * mix(0.55, 1.0, 1.0 - clamp(r, 0.0, 1.0));

		float density = clamp(gas_amount * cloud_density / float(STEPS) * 6.0, 0.0, 1.0);

		// Colour by DEPTH, not by density. Keying the hue off how much gas is at
		// this point looked like one flat violet, because the density hardly ever
		// climbs high enough to reach the far end of the ramp. Reading it off the
		// distance from the centre instead gives the thing real anatomy: a hot
		// core, a violet body, cool blue out at the fringes. Density is then only
		// allowed to push the colour back towards the core hue, so the thick
		// knots glow hotter wherever they happen to sit. The depth is nudged by
		// the same noise the gas came from so the three colours do not settle
		// into tidy concentric shells.
		float hue_depth = clamp(r + (n - 0.5) * 0.6, 0.0, 1.0);
		vec3 tint = mix(core_colour.rgb, mid_colour.rgb, smoothstep(0.0, 0.72, hue_depth));
		tint = mix(tint, outer_colour.rgb, smoothstep(0.62, 1.0, hue_depth));
		tint = mix(tint, core_colour.rgb, smoothstep(0.5, 1.0, gas_amount) * 0.5);

		// Gas glows, so it adds up rather than hiding what is behind it -- but it
		// is still dimmed by whatever is already in front of it.
		gas += tint * density * (1.0 - coverage * 0.6);
		coverage += density * (1.0 - coverage);
	}

	// Stars sit on ONE shell inside the glass rather than scattered through the
	// volume. Twenty raymarch steps cannot resolve a point small enough to read
	// as a star -- it falls between two samples and vanishes, or the samples
	// smear it into a streak along the ray, which near the silhouette turns the
	// whole rim into dashes. Intersecting a single sphere instead gives one
	// exact hit per pixel, so the stars are crisp and hold still, and putting
	// that sphere behind most of the gas keeps them looking deeply set.
	vec3 stars = vec3(0.0);
	vec3 unit_p = p / marble_radius;
	float shell_b = dot(unit_p, v);
	float shell_disc = shell_b * shell_b - (dot(unit_p, unit_p) - star_shell * star_shell);

	if (shell_disc > 0.0) {
		// The far intersection, so the stars sit behind the middle of the marble.
		vec3 on_shell = unit_p + v * (-shell_b + sqrt(shell_disc));
		vec3 sd = normalize(on_shell) * star_scale;
		vec3 cell = floor(sd);
		float seed = hash13(cell);

		if (seed > star_threshold) {
			// Independent hashes for the position -- reusing `seed` here put every
			// star at the same corner of its cell, which lined them up into rows.
			// Held clear of the cell walls so no star is cut in half by one.
			vec3 offset = clamp(
				vec3(hash13(cell + 7.7), hash13(cell + 17.3), hash13(cell + 43.1)),
				vec3(star_size), vec3(1.0 - star_size));
			float d = length(fract(sd) - offset);
			// Wide support, tight peak: the falloff reaches most of the cell so
			// the star has a faint halo, but the bright part stays a pinprick.
			float spark = pow(1.0 - min(d / star_size, 1.0), 3.0);
			spark *= mix(0.45, 1.0, 0.5 + 0.5 * sin(TIME * twinkle_speed + seed * TAU));
			stars = star_colour.rgb * spark * (1.0 - coverage * 0.75);
		}
	}

	// Glancing angles are where glass turns bright and mirror-like. With no
	// refraction, this and the specular are what sell it as glass.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 lit = gas + stars * star_brightness;

	ALBEDO = mix(void_colour.rgb, mix(void_colour.rgb, glass_tint.rgb, 0.18) + gas, coverage);
	ALPHA = clamp(mix(void_opacity, 1.0, coverage) + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;
	EMISSION = rim_tint.rgb * fresnel * rim_strength + lit * nebula_glow;
}
