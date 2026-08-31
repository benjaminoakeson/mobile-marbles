shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Two ribbons wound round each other and sealed in clear glass.
//
// The helix is written down rather than found: a point is placed at an angle and
// a height that both step together, which is all a helix is, and the ribbon's
// distance from the axis is tapered towards the ends so the whole coil sits
// inside the ball without touching the glass.
//
// A pixel is lit by how near its view ray passes those points -- the same trick
// the plasma arcs use, and for the same reason: it gives a thick, soft, glassy
// thread for the cost of a distance, and nothing has to be marched to find it.
//
// The rungs between the two strands are what stop it reading as a pair of
// unrelated curls. They are drawn on the line joining the strands at matching
// heights, every few steps.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.85, 0.93, 0.98, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.2;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Strands;
uniform vec4 strand_colour : source_color = vec4(0.1, 0.8, 0.9, 1.0);
uniform vec4 rung_colour : source_color = vec4(1.0, 0.65, 0.25, 1.0);
// Turns from one end of the coil to the other.
uniform float turns : hint_range(0.5, 6.0) = 1.6;
uniform float coil_radius : hint_range(0.1, 0.9) = 0.46;
uniform float coil_length : hint_range(0.2, 1.0) = 0.78;
uniform float strand_width : hint_range(0.01, 0.25) = 0.11;
uniform float rung_width : hint_range(0.005, 0.2) = 0.055;
// One rung every so many steps along the coil.
uniform int rung_spacing : hint_range(1, 12) = 6;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.9;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.4;

uniform float marble_radius = 0.5;

// Spaced closer together than a strand is thick, or the coil reads as a row of
// beads instead of a ribbon.
const int COIL_STEPS = 48;

varying vec3 obj_position;
varying vec3 obj_view;


// A point on strand `side` (0 or 1), a fraction `u` of the way up the coil.
vec3 strand_point(float side, float u) {
	float height = (u * 2.0 - 1.0) * coil_length;

	// Drawn in towards the axis at the ends, so the coil is a spindle and fits
	// the ball it is sealed in.
	float reach = coil_radius * sqrt(max(1.0 - height * height, 0.0));

	float angle = u * turns * TAU + side * PI;
	return vec3(cos(angle) * reach, height, sin(angle) * reach);
}


// How brightly a point on the coil lights this ray.
float thread(vec3 ray_from, vec3 ray_dir, vec3 point, float width) {
	vec3 to_point = point - ray_from;
	float along = max(dot(to_point, ray_dir), 0.0);
	float miss = length(to_point - ray_dir * along);

	float fall = width * width / (width * width + miss * miss);
	return fall * fall;
}


void vertex() {
	obj_position = VERTEX;

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 ray_from = obj_position / marble_radius;
	vec3 ray_dir = normalize(obj_view);

	float strands = 0.0;
	float rungs = 0.0;

	for (int i = 0; i < COIL_STEPS; i++) {
		float u = float(i) / float(COIL_STEPS - 1);

		vec3 left = strand_point(0.0, u);
		vec3 right = strand_point(1.0, u);

		strands = max(strands, thread(ray_from, ray_dir, left, strand_width));
		strands = max(strands, thread(ray_from, ray_dir, right, strand_width));

		// Every few steps, a bar across.
		if (i % rung_spacing == 0) {
			rungs = max(rungs, thread(ray_from, ray_dir, mix(left, right, 0.35), rung_width));
			rungs = max(rungs, thread(ray_from, ray_dir, mix(left, right, 0.65), rung_width));
		}
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 inside = strand_colour.rgb * strands + rung_colour.rgb * rungs;
	float cover = clamp(strands + rungs, 0.0, 1.0);

	ALBEDO = mix(glass_tint.rgb, inside / max(cover, 0.001), cover);
	ALPHA = clamp(glass_opacity + cover * 0.8 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = inside * glow_strength * 0.4 + rim_tint.rgb * fresnel * rim_strength;
}
