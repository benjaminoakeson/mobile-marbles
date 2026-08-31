shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A handmade-looking marble: clear glass with colour suspended inside it.
//
// What can be suspended is what the old glassblowers actually put in a marble,
// and a skin uses whichever of them it needs:
//
//   veins   ribbons and vanes, folded and twisted, one to six of them
//   core    a ball of colour at the middle
//   shell   a layer of colour just under the surface, the onionskin trick
//   bands   stripes ringing the marble across its axis
//   flecks  grit and glitter scattered through the glass
//
// Everything has a density, and a density of zero costs nothing but the branch
// -- so a plain tinted clearie and a six-vane latticinio are the same shader.
//
// The vein is a volume in the marble's own space, not a texture on the surface.
// The view ray is walked across the chord from where it enters the glass to
// where it leaves, picking up colour wherever it passes through the vein. So the
// vein has real depth and swings round as the marble rolls, with clear glass
// either side of it.
//
// The ray is walked STRAIGHT. An earlier version refracted it on entry, which is
// physically right for a glass ball but reads as a wobbly lens smearing whatever
// is inside -- the glassiness comes from the rim and the specular highlight
// instead, which look like glass without mangling the vein.
//
// No screen texture, so it behaves the same on the mobile renderer as anywhere.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.85, 0.93, 1.0, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.10;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.4;

group_uniforms Vein;
// Colour through the core of the vein and out at its edges. Keeping the two
// apart stops a slab of one flat colour reading like a sticker.
uniform vec4 vein_colour : source_color = vec4(0.10, 0.45, 1.0, 1.0);
uniform vec4 vein_edge_colour : source_color = vec4(0.40, 0.88, 1.0, 1.0);
// Which way the vein runs. Straight up through the marble by default.
uniform vec3 vein_axis = vec3(0.0, 1.0, 0.0);
// How broad the vein is across its face, as a fraction of the marble.
uniform float vein_breadth : hint_range(0.05, 2.0) = 0.5;
// How thick it is through the flat. Raise it towards `vein_breadth` and the
// ribbon fattens into a rope.
uniform float vein_thickness : hint_range(0.02, 2.0) = 0.28;
uniform float vein_softness : hint_range(0.01, 0.8) = 0.35;
uniform float vein_density : hint_range(0.0, 4.0) = 1.8;
uniform float vein_glow : hint_range(0.0, 2.0) = 0.45;
// How many copies of the vein there are, spread evenly round the axis. One is a
// ribbon; four crossed at the middle is a cat's eye.
uniform int vein_count : hint_range(1, 6) = 1;
// Radians the vein turns through over the height of the marble. This is the
// difference between a ribbon and a corkscrew.
uniform float vein_twist : hint_range(-8.0, 8.0) = 0.0;
// How far off the axis the copies are held. At zero they all pass through the
// middle and fan out from it, which is a cat's eye; pushed out they stand off
// the axis in a ring, and with a twist on them that ring becomes the woven cage
// of a latticinio.
uniform float vein_offset : hint_range(0.0, 1.0) = 0.0;

group_uniforms Organic;
// Noise volume used to bend the vein and to scatter the flecks.
uniform sampler3D organic_noise : filter_linear, repeat_enable;
// How far the vein wanders off a straight line. This is what folds it.
uniform float fold_amount : hint_range(0.0, 1.0) = 0.18;
// Bigger makes the folds tighter and more frequent.
uniform float fold_scale : hint_range(0.2, 6.0) = 0.9;
// Carries the noise through the marble over time. The vein is measured against
// that noise, so it writhes slowly rather than holding still, and the flecks
// swim with it. Zero on anything meant to look like set glass.
uniform float drift_speed : hint_range(0.0, 0.5) = 0.0;

group_uniforms Core;
// A ball of colour at the middle of the marble. `core_mottle` breaks it up with
// the same noise the vein is folded by, so it can be a solid bead or a cloud.
uniform vec4 core_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float core_radius : hint_range(0.0, 1.0) = 0.4;
uniform float core_softness : hint_range(0.01, 1.0) = 0.4;
uniform float core_mottle : hint_range(0.0, 1.0) = 0.0;
uniform float core_density : hint_range(0.0, 4.0) = 0.0;

group_uniforms Shell;
// A layer of colour held just under the surface with clear glass over it --
// what a marble collector calls an onionskin. `shell_radius` is how far out it
// sits, as a fraction of the marble.
uniform vec4 shell_colour : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float shell_radius : hint_range(0.2, 1.0) = 0.82;
uniform float shell_thickness : hint_range(0.02, 0.5) = 0.12;
uniform float shell_mottle : hint_range(0.0, 1.0) = 0.6;
uniform float shell_density : hint_range(0.0, 4.0) = 0.0;

group_uniforms Bands;
// Stripes ringing the marble across the vein's axis, alternating between two
// colours -- the peppermints and the banded agates.
uniform vec4 band_colour : source_color = vec4(0.9, 0.15, 0.2, 1.0);
uniform vec4 band_alt_colour : source_color = vec4(0.15, 0.3, 0.9, 1.0);
uniform float band_count : hint_range(0.5, 12.0) = 3.0;
// How much of the gap between two stripes a stripe fills.
uniform float band_width : hint_range(0.05, 1.0) = 0.35;
// How far the noise is allowed to push the stripes out of true.
uniform float band_wander : hint_range(0.0, 2.0) = 0.3;
uniform float band_density : hint_range(0.0, 4.0) = 0.0;

group_uniforms Flecks;
uniform vec4 fleck_colour : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float fleck_scale : hint_range(1.0, 20.0) = 7.0;
// Raise it for fewer, rarer flecks.
uniform float fleck_threshold : hint_range(0.4, 0.99) = 0.82;
uniform float fleck_density : hint_range(0.0, 4.0) = 0.7;

uniform float marble_radius = 0.5;

const int STEPS = 20;
const int MAX_VEINS = 6;

varying vec3 obj_position;
varying vec3 obj_normal;
varying vec3 obj_view;


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
	vec3 n = normalize(obj_normal);
	vec3 v = normalize(obj_view);

	// Straight through, no bending -- see the note at the top.
	vec3 through = v;

	// Where that ray leaves the far side of the marble.
	float b = dot(p, through);
	float c = dot(p, p) - marble_radius * marble_radius;
	float exit_t = -b + sqrt(max(b * b - c, 0.0));

	// The frame the vein is measured in: `run` along it, `face` across its
	// width, `flat_n` through its thickness.
	vec3 run = normalize(vein_axis);
	vec3 helper = abs(run.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 face = normalize(cross(run, helper));
	vec3 flat_n = cross(run, face);

	// Break the sampling positions up per pixel. Twenty even steps through a
	// soft edge leaves visible rings; a little jitter trades those for a faint
	// grain nobody notices.
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);

	float drift = TIME * drift_speed;

	vec3 gathered = vec3(0.0);
	float coverage = 0.0;

	for (int i = 0; i < STEPS; i++) {
		float along = (float(i) + jitter) / float(STEPS);
		vec3 q = p + through * (exit_t * along);
		vec3 unit_q = q / marble_radius;
		float depth = length(unit_q);

		vec3 uvw = unit_q * fold_scale * 0.5 + vec3(0.5) + vec3(drift, drift * 0.6, -drift * 0.4);

		// Push the vein's centre line around with noise. Measuring the distance
		// from a line that wanders is what turns a flat slab into something
		// folded and hand-pulled rather than machined.
		float bend_w = texture(organic_noise, uvw).r * 2.0 - 1.0;
		float bend_t = texture(organic_noise, uvw + vec3(0.37, 0.11, 0.71)).r * 2.0 - 1.0;

		// The vein, and its copies. Each one is the same slab turned further
		// round the axis, and the twist turns it further again the higher up the
		// marble it is measured -- which is what draws it out into a spiral.
		// Only the nearest copy counts, so where two cross they do not stack up
		// into something darker than either.
		float vein_mask = 0.0;
		float vein_edge = 1.0;

		for (int k = 0; k < MAX_VEINS; k++) {
			if (k >= vein_count) {
				break;
			}

			// Copies that pass through the middle only need half a turn between
			// them -- a slab is the same seen from either side. Ones standing
			// off the axis need the whole way round.
			float spread = vein_offset > 0.001 ? TAU : PI;
			float spin = float(k) * spread / float(vein_count) + vein_twist * dot(unit_q, run);
			vec3 across = face * cos(spin) + flat_n * sin(spin);
			vec3 through_flat = flat_n * cos(spin) - face * sin(spin);

			float w = abs(dot(unit_q, across) - bend_w * fold_amount)
					/ max(vein_breadth * 0.5, 0.001);
			float t = abs(dot(unit_q, through_flat) - vein_offset - bend_t * fold_amount)
					/ max(vein_thickness * 0.5, 0.001);

			float edge = max(w, t);
			float inside = 1.0 - smoothstep(1.0 - vein_softness, 1.0, edge);

			if (inside > vein_mask) {
				vein_mask = inside;
				vein_edge = edge;
			}
		}

		// The mottling the core and the shell are broken up with. The fold noise
		// is reused rather than sampled again -- at this scale a third lookup
		// buys nothing the eye can find.
		float mottle = bend_t * 0.5 + 0.5;

		float core_mask = 1.0 - smoothstep(core_radius * (1.0 - core_softness), core_radius, depth);
		core_mask *= mix(1.0, mottle, core_mottle);

		// A soft layer either side of `shell_radius`, so it is glass, colour,
		// then glass again on the way through.
		float shell_mask = 1.0 - smoothstep(0.0, shell_thickness, abs(depth - shell_radius));
		shell_mask *= mix(1.0, mottle, shell_mottle);

		// Stripes across the axis. They are the zero crossings of a wave, which
		// is what leaves clear glass between one stripe and the next, and the
		// side of the wave they fall on picks which of the two colours they are.
		float wave = sin(dot(unit_q, run) * band_count * PI + bend_w * band_wander);
		float band_mask = 1.0 - smoothstep(band_width * 0.5, band_width, abs(wave));
		vec3 band_tint = wave > 0.0 ? band_colour.rgb : band_alt_colour.rgb;

		// Flecks: high-frequency noise, thresholded so only the peaks survive.
		float grain = texture(organic_noise,
				unit_q * fleck_scale * 0.5 + vec3(0.19, 0.63, 0.41) + vec3(-drift * 0.5, drift, drift * 0.3)).r;
		float fleck = smoothstep(fleck_threshold, 1.0, grain);

		// Fade everything out before the shell so nothing ends in a hard edge
		// against the glass. The onionskin is left out of it: sitting right
		// under the surface is the whole point of it, and its own soft edges
		// keep it from reaching the glass.
		float edge_fade = 1.0 - smoothstep(0.82, 1.0, depth);
		vein_mask *= edge_fade;
		core_mask *= edge_fade;
		band_mask *= edge_fade;
		fleck *= edge_fade;

		float weight = 6.0 / float(STEPS);
		float vein_bit = vein_mask * vein_density * weight;
		float core_bit = core_mask * core_density * weight;
		float shell_bit = shell_mask * shell_density * weight;
		float band_bit = band_mask * band_density * weight;
		float fleck_bit = fleck * fleck_density * weight;

		vec3 vein_tint = mix(vein_colour.rgb, vein_edge_colour.rgb, clamp(vein_edge, 0.0, 1.0));

		// Whatever is at this point, in the proportions it is there in.
		float total = vein_bit + core_bit + shell_bit + band_bit + fleck_bit;
		vec3 tint = vein_tint * vein_bit
				+ core_colour.rgb * core_bit
				+ shell_colour.rgb * shell_bit
				+ band_tint * band_bit
				+ fleck_colour.rgb * fleck_bit;
		tint /= max(total, 0.0001);

		float density = clamp(total, 0.0, 1.0);

		// Front-to-back: whatever is already in the way hides what is behind it.
		gathered += tint * density * (1.0 - coverage);
		coverage += density * (1.0 - coverage);
	}

	// Glancing angles are where glass turns bright and mirror-like. With no
	// refraction, this and the specular are what sell it as glass.
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 inner = gathered / max(coverage, 0.001);

	ALBEDO = mix(glass_tint.rgb, inner, coverage);
	ALPHA = clamp(mix(glass_opacity, 1.0, coverage) + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;
	EMISSION = rim_tint.rgb * fresnel * rim_strength + inner * coverage * vein_glow;
}
