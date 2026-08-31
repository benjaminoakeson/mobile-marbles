shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://materials/marble/marble_shaders/marble_common.gdshaderinc"

// Tiger's eye, and the slit of light that opens down the middle of it.
//
// The stone is packed fibres all lying the same way. A fibre is a cylinder, and
// a cylinder does not have one direction it reflects from -- it reflects from a
// whole RING of them, all the way round its length. Stack a lot of parallel ones
// and what comes back is a single bright line lying across the fibres, which
// slides as the stone is turned. Jewellers call it a cat's eye; this is the
// same thing on a ball.
//
// So the highlight is not worked out from the surface normal like an ordinary
// one. It is worked out from how far the eye is off the plane at right angles to
// the fibres -- near that plane the fibres are all pointing back and the line
// lights up.
//
// The silk is the same fibre direction again, used to stretch the noise out
// along the grain so the bands run with it.

group_uniforms Stone;
uniform vec4 dark_band : source_color = vec4(0.16, 0.075, 0.02, 1.0);
uniform vec4 mid_band : source_color = vec4(0.55, 0.31, 0.06, 1.0);
uniform vec4 gold_band : source_color = vec4(0.95, 0.68, 0.18, 1.0);
uniform float surface_roughness : hint_range(0.0, 0.5) = 0.22;

group_uniforms Fibres;
uniform vec3 fibre_axis = vec3(0.1, 1.0, 0.15);
// How far the noise is stretched along the grain.
uniform float silk_stretch : hint_range(1.0, 20.0) = 9.0;
uniform float silk_scale : hint_range(1.0, 20.0) = 6.0;
// How much the grain wanders, so the bands are not ruled lines.
uniform float silk_wander : hint_range(0.0, 1.0) = 0.35;

group_uniforms Chatoyancy;
uniform vec4 eye_colour : source_color = vec4(1.0, 0.92, 0.62, 1.0);
// How narrow the slit of light is.
uniform float eye_sharpness : hint_range(1.0, 60.0) = 16.0;
uniform float eye_strength : hint_range(0.0, 4.0) = 1.6;

varying vec3 surface_direction;
varying vec3 fibre_direction;


void vertex() {
	surface_direction = normalize(VERTEX);

	// The grain, carried into the camera's space so the highlight can be worked
	// out against the eye.
	fibre_direction = (MODELVIEW_MATRIX * vec4(normalize(fibre_axis), 0.0)).xyz;
}


void fragment() {
	vec3 d = normalize(surface_direction);
	vec3 fibre = normalize(fibre_direction);

	// The fibre laid along the surface at this point: the part of it that does
	// not point out of the stone.
	vec3 along = normalize(fibre - NORMAL * dot(fibre, NORMAL));

	// How far the eye is off the plane at right angles to the fibres. Near zero
	// is where every fibre is reflecting back at once.
	float off_plane = abs(dot(normalize(VIEW), along));
	float slit = pow(1.0 - off_plane, eye_sharpness);

	// The silk: noise stretched hard along the grain, so the bands run with it.
	vec3 stretched = d - normalize(fibre_axis) * dot(d, normalize(fibre_axis)) * (1.0 - 1.0 / silk_stretch);
	float wander = fbm3(d * silk_scale * 0.4) * 2.0 - 1.0;
	float silk = fbm3(stretched * silk_scale + wander * silk_wander);

	vec3 body = mix(dark_band.rgb, mid_band.rgb, smoothstep(0.3, 0.55, silk));
	body = mix(body, gold_band.rgb, smoothstep(0.55, 0.8, silk));

	ALBEDO = body;

	METALLIC = 0.25;
	SPECULAR = 0.9;
	// The stone is glassier along the silk, duller across it.
	ROUGHNESS = mix(surface_roughness, 0.4, 1.0 - silk);

	// The slit rides on the brighter bands, because those are the fibres that
	// are polished enough to send the light back.
	EMISSION = eye_colour.rgb * slit * eye_strength * mix(0.35, 1.0, silk);
}
