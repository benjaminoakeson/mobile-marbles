shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A handmade-looking marble: clear glass with one thick vein of colour folded
// through it, and a scatter of flecks around it.
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

group_uniforms Organic;
// Noise volume used to bend the vein and to scatter the flecks.
uniform sampler3D organic_noise : filter_linear, repeat_enable;
// How far the vein wanders off a straight line. This is what folds it.
uniform float fold_amount : hint_range(0.0, 1.0) = 0.18;
// Bigger makes the folds tighter and more frequent.
uniform float fold_scale : hint_range(0.2, 6.0) = 0.9;

group_uniforms Flecks;
uniform vec4 fleck_colour : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float fleck_scale : hint_range(1.0, 20.0) = 7.0;
// Raise it for fewer, rarer flecks.
uniform float fleck_threshold : hint_range(0.4, 0.99) = 0.82;
uniform float fleck_density : hint_range(0.0, 4.0) = 0.7;

uniform float marble_radius = 0.5;

const int STEPS = 20;

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

	vec3 gathered = vec3(0.0);
	float coverage = 0.0;

	for (int i = 0; i < STEPS; i++) {
		float along = (float(i) + jitter) / float(STEPS);
		vec3 q = p + through * (exit_t * along);
		vec3 unit_q = q / marble_radius;

		vec3 uvw = unit_q * fold_scale * 0.5 + vec3(0.5);

		// Push the vein's centre line around with noise. Measuring the distance
		// from a line that wanders is what turns a flat slab into something
		// folded and hand-pulled rather than machined.
		float bend_w = texture(organic_noise, uvw).r * 2.0 - 1.0;
		float bend_t = texture(organic_noise, uvw + vec3(0.37, 0.11, 0.71)).r * 2.0 - 1.0;

		float w = abs(dot(unit_q, face) - bend_w * fold_amount)
				/ max(vein_breadth * 0.5, 0.001);
		float t = abs(dot(unit_q, flat_n) - bend_t * fold_amount)
				/ max(vein_thickness * 0.5, 0.001);

		float edge = max(w, t);
		float inside = 1.0 - smoothstep(1.0 - vein_softness, 1.0, edge);

		// Flecks: high-frequency noise, thresholded so only the peaks survive.
		float grain = texture(organic_noise, unit_q * fleck_scale * 0.5 + vec3(0.19, 0.63, 0.41)).r;
		float fleck = smoothstep(fleck_threshold, 1.0, grain);

		// Fade everything out before the shell so nothing ends in a hard edge
		// against the glass.
		float shell = 1.0 - smoothstep(0.82, 1.0, length(unit_q));
		inside *= shell;
		fleck *= shell;

		float vein_bit = inside * vein_density / float(STEPS) * 6.0;
		float fleck_bit = fleck * fleck_density / float(STEPS) * 6.0;

		vec3 tint = mix(vein_colour.rgb, vein_edge_colour.rgb, clamp(edge, 0.0, 1.0));
		tint = mix(tint, fleck_colour.rgb, clamp(fleck_bit / max(vein_bit + fleck_bit, 0.001), 0.0, 1.0));

		float density = clamp(vein_bit + fleck_bit, 0.0, 1.0);

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
