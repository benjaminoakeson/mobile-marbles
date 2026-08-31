shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Crackle glass: a marble taken from the furnace and dropped into cold water, so
// the skin of it shattered without the marble coming apart.
//
// The cracks run over the WHOLE ball, and they are three things at once, which
// is how real broken glass looks:
//
//   shards   the big pieces the skin broke into, and the seams between them
//   crazing  a finer web inside each piece, where it went on splitting
//   rays     the long cracks that shot out from the points the cold struck
//            first, ringed by the arrest lines where each one paused
//
// A crack is a gap in the glass with two faces, so it is drawn as a bright
// hairline and given relief: the surface is bent along the seam, and the light
// runs down it. That is what stops the web reading as ink on a ball.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.78, 0.88, 0.95, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.24;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.02;

group_uniforms Shards;
uniform vec4 crack_colour : source_color = vec4(0.95, 0.99, 1.0, 1.0);
// Bigger breaks the skin into more, smaller pieces.
uniform float shard_scale : hint_range(1.0, 20.0) = 5.0;
uniform float seam_width : hint_range(0.005, 0.2) = 0.028;
// The finer web inside each piece.
uniform float crazing_scale : hint_range(1.0, 8.0) = 2.6;
uniform float crazing_amount : hint_range(0.0, 1.0) = 0.4;

group_uniforms Rays;
uniform int strike_count : hint_range(0, 4) = 2;
// How many cracks shot out from each point the cold struck.
uniform float ray_count : hint_range(3.0, 30.0) = 11.0;
uniform float ray_width : hint_range(0.01, 0.4) = 0.09;
// How far the rays reach before they run out.
uniform float ray_reach : hint_range(0.3, 3.0) = 1.6;
// The rings where a crack stopped for a moment before going on.
uniform float arrest_rings : hint_range(0.0, 20.0) = 4.0;

group_uniforms Light;
uniform float relief : hint_range(0.0, 1.0) = 0.7;
uniform float crack_glow : hint_range(0.0, 3.0) = 0.5;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;

const int MAX_STRIKES = 4;

varying vec3 surface_direction;


float cracks_at(vec3 d) {
	// The seams between the big pieces.
	vec3 shards = worley3(d * shard_scale);
	float web = 1.0 - smoothstep(0.0, seam_width, shards.y - shards.x);

	// The finer web inside each piece.
	vec3 fine = worley3(d * shard_scale * crazing_scale + 11.0);
	float crazing = 1.0 - smoothstep(0.0, seam_width * 0.7, fine.y - fine.x);
	web = max(web, crazing * crazing_amount);

	// The long cracks thrown out from where the cold hit.
	for (int k = 0; k < MAX_STRIKES; k++) {
		if (k >= strike_count) {
			break;
		}

		vec3 struck = normalize(hash33(vec3(float(k) * 9.7, 2.1, 5.3)) * 2.0 - 1.0);
		float out_from = acos(clamp(dot(d, struck), -1.0, 1.0));

		vec3 first;
		vec3 second;
		frame_for(struck, first, second);
		float around = atan(dot(d, second), dot(d, first));

		// Not ruled lines: the noise bends every one of them as it travels.
		float wander = (fbm3(d * 3.0 + float(k) * 4.0) - 0.5) * 0.7;
		float spoke = abs(sin((around + wander) * ray_count * 0.5));
		float ray = 1.0 - smoothstep(0.0, ray_width, spoke);

		// Running out as they go, and gone before the far side.
		ray *= 1.0 - smoothstep(ray_reach * 0.5, ray_reach, out_from);
		ray *= smoothstep(0.0, 0.12, out_from);

		// The rings where each crack paused.
		float arrest = 1.0 - smoothstep(0.0, 0.06, abs(fract(out_from * arrest_rings) - 0.5) * 2.0 - 0.88);
		arrest *= 1.0 - smoothstep(ray_reach * 0.4, ray_reach * 0.9, out_from);

		web = max(web, max(ray, arrest * 0.45));
	}

	return clamp(web, 0.0, 1.0);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float cracks = cracks_at(d);

	if (relief > 0.0) {
		// A crack is a gap with two faces. Bending the surface along it is what
		// makes the light run down the seam instead of sitting on it.
		float step_size = 0.01;
		vec3 slope = vec3(
			cracks_at(d + vec3(step_size, 0.0, 0.0)) - cracks,
			cracks_at(d + vec3(0.0, step_size, 0.0)) - cracks,
			cracks_at(d + vec3(0.0, 0.0, step_size)) - cracks) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * relief * 0.004);
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(glass_tint.rgb, crack_colour.rgb, cracks);
	ALPHA = clamp(glass_opacity + cracks * 0.55 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	// Frosted along the break, polished everywhere else.
	ROUGHNESS = mix(surface_roughness, 0.3, cracks);

	EMISSION = crack_colour.rgb * cracks * crack_glow * 0.4
			+ rim_tint.rgb * fresnel * rim_strength;
}
