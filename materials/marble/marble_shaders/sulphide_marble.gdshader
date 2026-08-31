shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A sulphide: the Victorian trick of sealing a little white figure inside clear
// glass. They came with animals in them, mostly.
//
// This is the only marble in the set with an OBJECT in it rather than a pattern,
// so it is the only one built out of solid shapes: a few spheres making up a
// sitting bear, and the view ray asked which of them it hits first. That gives a
// real surface with a real normal, so the figure is lit and shaded like a thing
// and turns properly as the marble rolls.
//
// Sulphides look silver rather than white, because the glass never quite wets
// the figure and a skin of air is left round it. That is the rim term: the
// figure flares where it is seen edge-on.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.85, 0.92, 0.98, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.16;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Figure;
uniform vec4 figure_colour : source_color = vec4(0.93, 0.94, 0.96, 1.0);
uniform vec4 figure_shade : source_color = vec4(0.42, 0.46, 0.55, 1.0);
uniform vec4 silver_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float figure_scale : hint_range(0.3, 1.6) = 1.0;
uniform float silver_power : hint_range(0.5, 8.0) = 2.2;
uniform float silver_strength : hint_range(0.0, 2.0) = 0.7;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.45;

uniform float marble_radius = 0.5;

const int PARTS = 5;

varying vec3 obj_position;
varying vec3 obj_view;


// The bear, as a body, a head, two ears and a muzzle. Kept well inside the
// marble so the glass is never broken by it.
void figure_part(int index, out vec3 centre, out float size) {
	if (index == 0) {
		centre = vec3(0.0, -0.16, 0.0);
		size = 0.34;
	} else if (index == 1) {
		centre = vec3(0.0, 0.24, 0.0);
		size = 0.22;
	} else if (index == 2) {
		centre = vec3(-0.16, 0.4, 0.0);
		size = 0.08;
	} else if (index == 3) {
		centre = vec3(0.16, 0.4, 0.0);
		size = 0.08;
	} else {
		centre = vec3(0.0, 0.18, 0.19);
		size = 0.11;
	}
}


void vertex() {
	obj_position = VERTEX;

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 ray_from = obj_position / marble_radius;
	vec3 ray_dir = normalize(obj_view);

	float nearest = 1000.0;
	vec3 hit_normal = vec3(0.0);

	for (int k = 0; k < PARTS; k++) {
		vec3 centre;
		float size;
		figure_part(k, centre, size);
		centre *= figure_scale;
		size *= figure_scale;

		// Where the ray meets this sphere, if it does.
		vec3 to_centre = ray_from - centre;
		float b = dot(to_centre, ray_dir);
		float c = dot(to_centre, to_centre) - size * size;
		float under = b * b - c;

		if (under < 0.0) {
			continue;
		}

		float travel = -b - sqrt(under);
		if (travel < 0.0 || travel >= nearest) {
			continue;
		}

		nearest = travel;
		hit_normal = (ray_from + ray_dir * travel - centre) / size;
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	if (nearest < 999.0) {
		// The figure's own shading, worked out from its own surface rather than
		// from the marble's.
		vec3 seen = (VIEW_MATRIX * MODEL_MATRIX * vec4(hit_normal, 0.0)).xyz;
		seen = normalize(seen);

		float lit = clamp(dot(seen, normalize(vec3(0.4, 0.7, 0.6))), 0.0, 1.0);
		float edge = pow(1.0 - clamp(dot(seen, VIEW), 0.0, 1.0), silver_power);

		ALBEDO = mix(figure_shade.rgb, figure_colour.rgb, lit * 0.8 + 0.2);
		ALPHA = 1.0;
		ROUGHNESS = 0.55;
		SPECULAR = 0.3;
		EMISSION = silver_colour.rgb * edge * silver_strength;
	} else {
		ALBEDO = glass_tint.rgb;
		ALPHA = clamp(glass_opacity + fresnel * rim_strength, 0.0, 1.0);
		ROUGHNESS = surface_roughness;
		SPECULAR = 1.0;
		EMISSION = rim_tint.rgb * fresnel * rim_strength;
	}

	METALLIC = 0.0;
}
