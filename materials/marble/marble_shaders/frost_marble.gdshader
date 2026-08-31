shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Ice, grown rather than painted.
//
// Real frost is two things at once, and the shader is built out of both:
//
//   facets  the walls where one crystal grain stopped growing against the next.
//           Scattered points, and the places where the two nearest are the same
//           distance away -- which is exactly what a grain boundary is.
//   ferns   the feathery spines inside each grain. Creases in the noise, pinched
//           hard so only their centre lines survive.
//
// The growth is what makes it live: every grain is given a number of its own, so
// its ferns thicken and thin on their own beat and the frost creeps over the
// marble instead of sitting on it.
//
// The crystals bend the surface as well as colouring it, so the ice catches the
// light along its spines. Cheap here -- it is a surface shader, one sample and
// three more for the slope, with no volume to walk.

group_uniforms Ice;
uniform vec4 ice_colour : source_color = vec4(0.62, 0.78, 0.92, 1.0);
// What is seen looking into the ice rather than along it.
uniform vec4 deep_colour : source_color = vec4(0.18, 0.38, 0.60, 1.0);
uniform vec4 crystal_colour : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform float ice_opacity : hint_range(0.0, 1.0) = 0.72;

group_uniforms Crystals;
// Bigger packs more grains onto the marble.
uniform float facet_scale : hint_range(1.0, 20.0) = 5.5;
uniform float facet_width : hint_range(0.01, 0.4) = 0.1;
uniform float fern_scale : hint_range(1.0, 40.0) = 13.0;
// How tightly the ferns are pinched. Low is a smear of cloud, high is a spine.
uniform float fern_sharpness : hint_range(1.0, 12.0) = 3.5;
uniform float relief : hint_range(0.0, 1.0) = 0.5;

group_uniforms Growth;
uniform float growth_speed : hint_range(0.0, 2.0) = 0.5;
uniform float shimmer_speed : hint_range(0.0, 6.0) = 1.5;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.45;

varying vec3 surface_direction;


float frost_at(vec3 d, float t) {
	vec3 grain = worley3(d * facet_scale);

	// The wall between two grains: the narrow place where the nearest point and
	// the next nearest are the same distance off.
	float facet = 1.0 - smoothstep(0.0, facet_width, grain.y - grain.x);

	// Each grain grows on its own beat, from its own number.
	float grown = 0.5 + 0.5 * sin(t + grain.z * TAU);
	float fern = pow(ridged(d * fern_scale + grain.z * 17.0), fern_sharpness);

	// Frost grows off an edge, not out of thin air, so the ferns are strongest
	// against the wall they started from and peter out towards the middle of
	// the grain.
	fern *= 1.0 - smoothstep(0.05, 0.55, grain.y - grain.x);

	return clamp(facet * 0.8 + fern * mix(0.3, 1.3, grown), 0.0, 1.0);
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);
	float t = TIME * growth_speed;
	float ice = frost_at(d, t);

	if (relief > 0.0) {
		// Which way the crystal is climbing, from three more samples a short
		// step away. Tilting the normal along that slope is what makes a spine
		// catch the light like something standing off the surface.
		float step_size = 0.015;
		vec3 slope = vec3(
			frost_at(d + vec3(step_size, 0.0, 0.0), t) - ice,
			frost_at(d + vec3(0.0, step_size, 0.0), t) - ice,
			frost_at(d + vec3(0.0, 0.0, step_size), t) - ice) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * relief * 0.02);
	}

	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(facing, rim_power);

	// Clear ice where nothing has grown, milky where it has.
	vec3 body = mix(deep_colour.rgb, ice_colour.rgb, facing * 0.7 + 0.3);
	ALBEDO = mix(body, crystal_colour.rgb, ice);

	ALPHA = clamp(ice_opacity + ice * 0.25 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	// Polished between the crystals, frosted along them.
	ROUGHNESS = mix(0.05, 0.4, ice);

	// A glint that travels through the ice rather than sitting still on it.
	float glint = 0.5 + 0.5 * sin(TIME * shimmer_speed + d.y * 6.0 + d.x * 4.0);
	EMISSION = rim_tint.rgb * fresnel * rim_strength
			+ crystal_colour.rgb * ice * glint * 0.22;
}
