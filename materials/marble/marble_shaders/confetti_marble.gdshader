shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Confetti glass: chips of coloured glass dropped into a clear gather and rolled
// in, so they end up lying at every angle inside it.
//
// The chips are FLAT, and that is the point of the design. A flake seen face on
// is a full disc of colour; the same flake seen edge on is a sliver, and nearly
// black. So each chip is a real disc -- a centre, a radius and a facing -- and
// the view ray is asked where it crosses the plane of each and whether that
// crossing lands within its edge.
//
// The nearest chip in the way is the one that is seen, and the rest are behind
// it. That is what gives the marble its depth as it turns: chips pass in front
// of each other, and each one opens out and closes again as its face comes round
// to the eye.

group_uniforms Glass;
uniform vec4 glass_tint : source_color = vec4(0.88, 0.93, 0.97, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.2;
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.03;

group_uniforms Chips;
uniform vec4 first_colour : source_color = vec4(0.95, 0.25, 0.45, 1.0);
uniform vec4 second_colour : source_color = vec4(0.2, 0.75, 0.95, 1.0);
uniform vec4 third_colour : source_color = vec4(1.0, 0.82, 0.2, 1.0);
uniform int chip_count : hint_range(1, 28) = 26;
uniform float chip_size : hint_range(0.05, 0.5) = 0.26;
uniform float size_spread : hint_range(0.0, 1.0) = 0.5;
// How much darker a chip goes as it turns edge on.
uniform float edge_fade : hint_range(0.0, 1.0) = 0.6;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.45;

uniform float marble_radius = 0.5;

const int MAX_CHIPS = 28;

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

	float nearest = 1000.0;
	vec3 chip_seen = vec3(0.0);
	float chip_cover = 0.0;

	for (int k = 0; k < MAX_CHIPS; k++) {
		if (k >= chip_count) {
			break;
		}

		vec3 seed = hash33(vec3(float(k) * 5.3, 1.9, 6.7));
		vec3 centre = (seed * 2.0 - 1.0) * 0.78;
		vec3 facing = normalize(hash33(vec3(float(k) * 2.1, 8.3, 3.7)) * 2.0 - 1.0);
		float size = chip_size * mix(1.0 - size_spread, 1.0, seed.y);

		float met = dot(ray_dir, facing);
		if (abs(met) < 0.0015) {
			continue;
		}

		float travel = dot(centre - ray_from, facing) / met;
		if (travel < 0.0 || travel >= nearest) {
			continue;
		}

		vec3 crossing = ray_from + ray_dir * travel;
		float across = length(crossing - centre);
		if (across > size || length(crossing) > 0.95) {
			continue;
		}

		nearest = travel;

		// Which of the three colours this chip was cut from.
		float which = fract(seed.z * 7.3);
		vec3 colour = mix(first_colour.rgb, second_colour.rgb, smoothstep(0.0, 0.5, which));
		colour = mix(colour, third_colour.rgb, smoothstep(0.5, 1.0, which));

		// Edge on it is a sliver of glass with hardly any colour left in it;
		// face on it is the full chip.
		float square_on = abs(met);
		chip_seen = colour * mix(1.0 - edge_fade, 1.0, square_on);

		// A little brighter right at the cut edge.
		chip_seen += vec3(0.25) * smoothstep(size * 0.82, size, across);
		chip_cover = mix(0.55, 1.0, square_on);
	}

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(glass_tint.rgb, chip_seen, chip_cover);
	ALPHA = clamp(glass_opacity + chip_cover * 0.7 + fresnel * rim_strength, 0.0, 1.0);

	METALLIC = 0.0;
	SPECULAR = 1.0;
	ROUGHNESS = surface_roughness;

	EMISSION = rim_tint.rgb * fresnel * rim_strength;
}
