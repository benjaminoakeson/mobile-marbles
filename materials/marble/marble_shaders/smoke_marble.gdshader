shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Smoke shut in glass.
//
// This one has to be a volume. Smoke is the one thing in the set with no surface
// to draw -- what makes it read as smoke is seeing the thin parts of it THROUGH
// the thick parts -- so the view ray is walked across the marble and the puffs
// are gathered up front to back.
//
// It rises and rolls at once: the field is carried upwards, and it is also
// dragged sideways by a slower field that is itself rising. A puff therefore
// turns over as it climbs instead of sliding up the glass like a poster.
//
// The noise comes from a texture rather than being worked out per sample.
// Walking a volume means ten or more reads a pixel, and at that rate a lookup is
// far cheaper than the arithmetic.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.86, 0.9, 0.95, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.08;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Smoke;
uniform sampler3D smoke_noise : filter_linear, repeat_enable;
uniform vec4 smoke_colour : source_color = vec4(0.72, 0.74, 0.79, 1.0);
// The underside of a puff, away from the light.
uniform vec4 shadow_colour : source_color = vec4(0.16, 0.17, 0.21, 1.0);
uniform float smoke_scale : hint_range(0.2, 6.0) = 1.5;
// Everything thinner than this is clear glass.
uniform float smoke_threshold : hint_range(0.0, 0.9) = 0.44;
uniform float smoke_softness : hint_range(0.02, 0.6) = 0.26;
uniform float smoke_density : hint_range(0.0, 4.0) = 2.0;

group_uniforms Motion;
uniform float rise_speed : hint_range(0.0, 0.5) = 0.06;
// How hard the slower field drags the smoke sideways as it goes up. This is the
// roll.
uniform float curl_amount : hint_range(0.0, 1.5) = 0.7;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;

uniform float marble_radius = 0.5;

const int STEPS = 14;

varying vec3 obj_position;
varying vec3 obj_view;


void vertex() {
	obj_position = VERTEX;

	vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	obj_view = VERTEX - eye;
}


void fragment() {
	vec3 p = obj_position;
	vec3 v = normalize(obj_view);
	float exit_t = sphere_exit(p, v, marble_radius);

	vec3 lift = vec3(0.0, -TIME * rise_speed, 0.0);
	float jitter = dither(SCREEN_UV);

	vec3 gathered = vec3(0.0);
	float coverage = 0.0;

	for (int i = 0; i < STEPS; i++) {
		float along = (float(i) + jitter) / float(STEPS);
		vec3 q = (p + v * (exit_t * along)) / marble_radius;
		float r = length(q);

		vec3 uvw = q * smoke_scale * 0.5 + vec3(0.5) + lift;

		// The slower field, rising too, that drags the smoke sideways.
		vec3 drag = vec3(
			texture(smoke_noise, uvw * 0.5 + vec3(0.13, 0.71, 0.29)).r,
			texture(smoke_noise, uvw * 0.5 + vec3(0.83, 0.19, 0.47)).r,
			texture(smoke_noise, uvw * 0.5 + vec3(0.37, 0.61, 0.11)).r) * 2.0 - 1.0;

		float puff = texture(smoke_noise, uvw + drag * curl_amount * 0.3).r;
		float amount = smoothstep(smoke_threshold, smoke_threshold + smoke_softness, puff);

		// Ends in clear glass rather than against it, and thins as it climbs.
		amount *= 1.0 - smoothstep(0.55, 1.0, r);
		amount *= mix(1.0, 0.5, clamp(q.y * 0.5 + 0.5, 0.0, 1.0));

		float density = clamp(amount * smoke_density / float(STEPS) * 6.0, 0.0, 1.0);

		// Lit from above: the top of a puff is bright and its underside is not.
		vec3 tint = mix(shadow_colour.rgb, smoke_colour.rgb,
				clamp(q.y * 0.5 + 0.5 + puff * 0.3, 0.0, 1.0));

		// Front to back: what is already in the way hides what is behind it.
		gathered += tint * density * (1.0 - coverage);
		coverage += density * (1.0 - coverage);
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	vec3 inner = gathered / max(coverage, 0.001);

	ALBEDO = mix(glass_tint.rgb, inner, coverage);
	ALPHA = clamp(mix(glass_opacity, 1.0, coverage) + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = rim_tint.rgb * fresnel * rim_strength;
}
