shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Seed bubbles: the air the glassmaker failed to work out of it.
//
// A bubble is a hole, and a hole in glass behaves like a lens. Looked at
// straight on it is nearly invisible; looked at near its edge the light turns
// hard and it lights up as a bright ring. That ring is the whole of the effect,
// and it is drawn from one number: how near the view ray passes the middle of
// the bubble, as a fraction of its size.
//
// So no intersection is needed and nothing is walked -- the closest approach of
// the ray to each bubble's centre gives both which bubble is in the way and how
// it should look. A few dozen arithmetic operations per bubble.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.72, 0.86, 0.92, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.22;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Bubbles;
uniform vec4 bubble_rim_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 bubble_shade : source_color = vec4(0.35, 0.55, 0.65, 1.0);
uniform int bubble_count : hint_range(1, 24) = 15;
uniform float bubble_size : hint_range(0.03, 0.4) = 0.16;
// How much bigger the biggest bubble is than the smallest.
uniform float size_spread : hint_range(0.0, 1.0) = 0.6;
// Where the bright ring starts, as a fraction of the way out from the middle.
uniform float ring_start : hint_range(0.2, 0.98) = 0.62;
uniform float ring_glow : hint_range(0.0, 3.0) = 0.7;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;

uniform float marble_radius = 0.5;

const int MAX_BUBBLES = 24;

varying vec3 obj_position;
varying vec3 obj_view;


void vertex() {
	obj_position = VERTEX;

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 ray_from = obj_position / marble_radius;
	vec3 ray_dir = normalize(obj_view);

	float ring = 0.0;
	float body = 0.0;

	for (int k = 0; k < MAX_BUBBLES; k++) {
		if (k >= bubble_count) {
			break;
		}

		vec3 seed = hash33(vec3(float(k) * 4.1, 2.7, 8.3));
		vec3 centre = (seed * 2.0 - 1.0) * 0.72;
		float size = bubble_size * mix(1.0 - size_spread, 1.0, hash13(vec3(float(k), 6.1, 2.9)));

		vec3 to_centre = centre - ray_from;
		float along = dot(to_centre, ray_dir);
		float miss = length(to_centre - ray_dir * max(along, 0.0));

		// How near the middle the ray passed, as a fraction of the bubble.
		float across = miss / size;
		if (across > 1.0) {
			continue;
		}

		// Bright where the glass is nearly edge on to the ray, and faintly
		// shaded across the rest of the face.
		ring = max(ring, smoothstep(ring_start, 1.0, across));
		body = max(body, 1.0 - across * across);
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 seen = mix(glass_tint.rgb, bubble_shade.rgb, body * 0.35);
	seen = mix(seen, bubble_rim_colour.rgb, ring);

	ALBEDO = seen;
	ALPHA = clamp(glass_opacity + ring * 0.6 + body * 0.15 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = bubble_rim_colour.rgb * ring * ring_glow * 0.4
			+ rim_tint.rgb * fresnel * rim_strength;
}
