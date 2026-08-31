shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Moonstone, and the blue drift of light that floats inside one.
//
// The stone is layers of two feldspars, and light bouncing between them comes
// back blue -- but only within a narrow range of angles, which is why the sheen
// swims across the stone as it is turned instead of sitting on it.
//
// Both halves of that are here. The sheen is allowed only in a BAND of viewing
// angle, so it comes and goes as the marble rolls. And where it falls is read at
// a point pushed some way INTO the marble along the line of sight, so it lies
// under the surface and slides against it as the angle changes -- which is what
// makes it look like something floating in the stone rather than painted on it.

group_uniforms Stone;
uniform vec4 body_colour : source_color = vec4(0.86, 0.86, 0.84, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.45, 0.5, 0.6, 1.0);
uniform float stone_opacity : hint_range(0.0, 1.0) = 0.72;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.08;

group_uniforms Sheen;
uniform vec4 sheen_colour : source_color = vec4(0.45, 0.7, 1.0, 1.0);
// The viewing angle the sheen comes back at, and how wide a range of angles it
// is allowed. Zero is edge-on, one is straight down at the surface.
uniform float sheen_angle : hint_range(0.0, 1.0) = 0.72;
uniform float sheen_width : hint_range(0.05, 1.0) = 0.5;
// How far under the surface it lies. This is what gives it its drift.
uniform float sheen_depth : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_scale : hint_range(0.5, 8.0) = 2.2;
uniform float sheen_strength : hint_range(0.0, 3.0) = 1.3;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 obj_position;
varying vec3 obj_view;


void vertex() {
	obj_position = normalize(VERTEX);

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 d = normalize(obj_position);
	vec3 into = normalize(obj_view);

	// A point pushed in along the line of sight. Because it is found by looking
	// THROUGH the surface, it moves against the surface as the angle changes,
	// and the sheen it carries swims.
	vec3 beneath = d + into * sheen_depth;

	float cloud = fbm3(beneath * cloud_scale);
	float veil = smoothstep(0.35, 0.75, cloud);

	// The band of angles the light comes back at.
	float straight_on = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float band = 1.0 - clamp(abs(straight_on - sheen_angle) / sheen_width, 0.0, 1.0);
	band = band * band;

	float sheen = band * veil;

	float fresnel = pow(1.0 - straight_on, rim_power);

	// The stone itself is milky: pale looking into it, greyer at the edges.
	vec3 body = mix(body_colour.rgb, deep_colour.rgb, fresnel * 0.7);

	ALBEDO = mix(body, sheen_colour.rgb, sheen * 0.5);
	ALPHA = clamp(stone_opacity + sheen * 0.25 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 0.8;
	ROUGHNESS = surface_roughness;

	EMISSION = sheen_colour.rgb * sheen * sheen_strength * 0.4
			+ rim_tint.rgb * fresnel * rim_strength;
}
