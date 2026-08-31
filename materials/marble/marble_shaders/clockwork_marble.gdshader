shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// A movement, packed solid: wheels over the whole ball, meshing edge to edge.
//
// An earlier version placed a handful of wheels by hand on a mostly empty plate,
// and it read as decoration rather than as machinery. The fix is to let the
// scatter do the placing. The surface is cut into cells, and EVERY cell gets a
// wheel sized to fill it -- so the wheels tile the marble, each one's teeth
// reaching the gap where its neighbour's teeth are, and there is no bare plate
// left to look at.
//
// Each wheel is drawn in its own polar terms: a distance out from the cell's own
// middle and an angle round it, which give the rim, the teeth cut into it, the
// spokes and the hub.
//
// The train is geared. A wheel's tooth count comes from its own number, its
// speed is INVERSE to that count -- more teeth, slower wheel, as in any gear
// train -- and half of them are cut to run backwards, so a wheel and the one it
// meshes with turn against each other.

group_uniforms Plate;
uniform vec4 plate_colour : source_color = vec4(0.07, 0.06, 0.05, 1.0);
uniform vec4 shadow_colour : source_color = vec4(0.02, 0.018, 0.015, 1.0);

group_uniforms Wheels;
uniform vec4 brass_colour : source_color = vec4(0.85, 0.62, 0.24, 1.0);
uniform vec4 steel_colour : source_color = vec4(0.66, 0.7, 0.76, 1.0);
uniform vec4 edge_colour : source_color = vec4(1.0, 0.88, 0.6, 1.0);
// Bigger packs in more, smaller wheels.
uniform float gear_scale : hint_range(1.0, 12.0) = 2.2;
// How much of its cell a wheel fills. Near one and the teeth of neighbours meet.
uniform float gear_fill : hint_range(0.3, 1.6) = 1.35;
// How deep the teeth are cut into the rim.
uniform float tooth_depth : hint_range(0.02, 0.4) = 0.2;
uniform float fewest_teeth : hint_range(5.0, 20.0) = 7.0;
uniform float most_teeth : hint_range(6.0, 30.0) = 12.0;
uniform int spoke_count : hint_range(2, 8) = 4;

group_uniforms Drive;
// Turns a second for a ten-tooth wheel. Everything else is geared off it.
uniform float drive_speed : hint_range(0.0, 1.0) = 0.12;

group_uniforms Finish;
uniform float gear_metallic : hint_range(0.0, 1.0) = 0.9;
uniform float gear_roughness : hint_range(0.0, 1.0) = 0.28;
uniform float relief : hint_range(0.0, 1.0) = 0.6;

varying vec3 surface_direction;


// How much metal is at a point: one where a wheel is, zero over the plate.
// `edge` comes back carrying how near the point is to a cut edge, for lighting.
float wheels_at(vec3 d, out float edge, out float which) {
	vec4 near = worley_near(d * gear_scale);
	float from_middle = length(near.xyz);
	which = near.w;

	// The angle round this wheel's own centre, measured in the surface so the
	// wheel lies flat on the marble.
	vec3 first;
	vec3 second;
	frame_for(d, first, second);
	float around = atan(dot(near.xyz, second), dot(near.xyz, first));

	// Its gearing. More teeth, slower; and half the train runs backwards.
	float teeth = floor(mix(fewest_teeth, most_teeth, which));
	float sense = fract(which * 7.31) > 0.5 ? 1.0 : -1.0;
	float turned = TIME * drive_speed * TAU * (10.0 / teeth) * sense + which * TAU;

	// The rim, stepping in and out with the teeth.
	float tooth = smoothstep(-0.35, 0.35, cos(around * teeth + turned));
	float rim = gear_fill * 0.5 * (1.0 - tooth_depth + tooth_depth * tooth);

	float body = 1.0 - smoothstep(rim - 0.012, rim, from_middle);

	// Cut out between the spokes, so the plate shows through the wheel. All of
	// it is measured against the wheel's own rim, so a big wheel and a small one
	// are the same wheel at different sizes.
	float hub = 1.0 - smoothstep(rim * 0.3, rim * 0.36, from_middle);
	float ring = smoothstep(rim * 0.52, rim * 0.6, from_middle);
	float spokes = smoothstep(0.15, 0.5, abs(cos(around * float(spoke_count) - turned)));
	float metal = body * clamp(hub + ring + spokes, 0.0, 1.0);

	// How near a cut edge -- the rim, and the sides of the spokes.
	edge = body * max(
			1.0 - smoothstep(0.0, 0.025, abs(from_middle - rim)),
			smoothstep(0.75, 0.95, spokes) * (1.0 - ring) * (1.0 - hub));

	return metal;
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	vec3 d = normalize(surface_direction);

	float edge;
	float which;
	float metal = wheels_at(d, edge, which);

	if (relief > 0.0) {
		// The wheels stand off the plate, so their edges catch the light.
		float step_size = 0.008;
		float ignore;
		float other;
		vec3 slope = vec3(
			wheels_at(d + vec3(step_size, 0.0, 0.0), ignore, other) - metal,
			wheels_at(d + vec3(0.0, step_size, 0.0), ignore, other) - metal,
			wheels_at(d + vec3(0.0, 0.0, step_size), ignore, other) - metal) / step_size;

		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL - view_slope * relief * 0.0025);
	}

	// Brass and steel, alternating through the train.
	vec3 metal_colour = fract(which * 3.7) > 0.45 ? brass_colour.rgb : steel_colour.rgb;

	// The plate is darkest right under a wheel, where its shadow falls.
	vec3 plate = mix(plate_colour.rgb, shadow_colour.rgb, metal * 0.0 + 0.35);

	ALBEDO = mix(plate, metal_colour, metal);

	METALLIC = mix(0.15, gear_metallic, metal);
	SPECULAR = 0.65;
	ROUGHNESS = mix(0.8, gear_roughness, metal);

	EMISSION = edge_colour.rgb * edge * 0.35;
}
