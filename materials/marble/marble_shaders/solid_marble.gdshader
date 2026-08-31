shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// A plain painted marble: one solid colour, lit like a ball.
//
// This is the cheap end of the marble shaders. There is no volume to walk and no
// noise to sample -- every pixel is the same colour, and everything that makes it
// read as a marble rather than a flat circle comes from three surface terms:
//
//   shade      darkens the parts turning away from the eye, so the ball still
//              looks round under flat or ambient-only lighting
//   rim        a thin bright edge, the same trick the glass marble uses
//   highlight  left to the engine's specular, steered by `surface_roughness`
//
// On top of that sits an optional pattern -- flecks, veins, swirls, cloud or
// brushed streaks -- worked out from the direction of the surface rather than
// from a texture, so it costs no memory, never seams and turns with the marble
// as it rolls. `pattern_mode` picks which one; `pattern_strength` of zero puts
// the shader back to the plain painted ball it was before.
//
// Meant to be the base for basic skins: duplicate the material, change
// `base_colour`, and leave the rest alone.
//
// Deliberately opaque. Never writing ALPHA is what keeps it in the opaque pass,
// where it writes depth and needs no sorting against the other marbles; a
// see-through skin wants glass_marble.gdshader instead.

group_uniforms Body;
uniform vec4 base_colour : source_color = vec4(0.85, 0.20, 0.22, 1.0);
// Solid does not have to mean matte. Push metallic to 1.0 with a low roughness
// for a painted-metal ball bearing; leave it at 0.0 for enamel or plastic.
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.18;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.6;

group_uniforms Shading;
// How much the colour deepens towards the silhouette. This is not real lighting,
// it is a fixed darkening based on how side-on the surface is -- which is what
// keeps a flat colour from going papery when the level lighting is soft.
uniform vec4 shade_colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0) = 0.35;
// Raise it to keep the shading squeezed into a narrow band at the very edge.
uniform float shade_power : hint_range(0.5, 6.0) = 1.6;

group_uniforms Rim;
uniform vec4 rim_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

group_uniforms Glow;
// For skins that should read as lit from inside. Tinted separately so a glow can
// be a different colour from the body -- a dark shell with a hot core, say.
uniform vec4 glow_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float glow_strength : hint_range(0.0, 4.0) = 0.0;

group_uniforms Pattern;
// Which formation the surface is broken up with:
//
//   0 none    a plain painted ball, as this shader was before
//   1 speck   flecks of grit, half of them lighter and half darker
//   2 vein    thin branching lines, the way stone marble is veined
//   3 swirl   wide bands, bent out of straight by the noise they are drawn with
//   4 cloud   soft mottling, no edges anywhere
//   5 streak  the noise pulled long in one direction, like brushed metal
uniform int pattern_mode : hint_range(0, 5) = 0;
// The two ends of the pattern. Where it reads strongest the body is carried
// towards `pattern_colour`, and where it reads weakest towards `pattern_shadow`
// -- which is what gives a formation a lit side and a shaded one rather than
// just a dirty tint. Modes that only have one side (vein) use the first alone.
uniform vec4 pattern_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 pattern_shadow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.0;
// How much of the marble one feature covers. Small numbers give a few broad
// formations, large ones a fine grain.
uniform float pattern_scale : hint_range(0.5, 60.0) = 8.0;
// How hard the formation's edges are. Low is a smudge, high is a sharp mark --
// on veins it is what decides whether they are hairlines or rivers.
uniform float pattern_sharpness : hint_range(0.5, 8.0) = 2.0;
// Roughens the surface where the pattern reads light and polishes it where it
// reads dark, so the formation catches the highlight differently from the body
// it sits in. This is most of what sells grit on a metal skin.
uniform float pattern_roughness : hint_range(-0.5, 0.5) = 0.0;
// Bends the surface normal along the pattern, so it is felt as relief rather
// than only seen as colour. Costs three more pattern samples, so it is left at
// zero on skins that do not need it.
uniform float pattern_relief : hint_range(0.0, 1.0) = 0.0;

// Where on the marble a fragment is, as a direction from the middle. Taken from
// the model's own vertices, so the pattern is painted onto the ball and rolls
// with it, and normalised so a big marble and a small one are grained the same.
varying vec3 surface_direction;


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}


// Ordinary value noise: a random number per lattice corner, smoothed between
// them. Cheaper than gradient noise and, once several octaves are piled up,
// close enough for stone.
float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));

	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}


// Three octaves of it. Enough for a formation to have both a shape and a grain;
// a fourth costs another eight hashes a sample and is not visible on a ball this
// size on a phone.
float fbm(vec3 p) {
	float sum = value_noise(p) * 0.5;
	sum += value_noise(p * 2.03) * 0.25;
	sum += value_noise(p * 4.07) * 0.125;
	return sum / 0.875;
}


// How strongly the pattern reads at a point, from -1 (fully the shadow colour)
// through 0 (untouched body) to 1 (fully the pattern colour).
float pattern_at(vec3 p) {
	if (pattern_mode == 1) {
		// Speck. Only the extremes of the noise are kept, so what is left is
		// scattered grit rather than a wash -- the bright tail of the noise
		// becomes the light flecks and the dark tail the dark ones.
		float n = value_noise(p);
		return smoothstep(0.62, 0.88, n) - smoothstep(0.62, 0.88, 1.0 - n);
	}

	if (pattern_mode == 2) {
		// Vein. The noise is folded about its middle, which turns the level
		// where it crosses a half into a crease, and the crease into a line.
		// Veins are a mark on the stone, not a shading of it, so this side of
		// the range is the only one used.
		float folded = 1.0 - abs(fbm(p) * 2.0 - 1.0);
		return pow(folded, pattern_sharpness * 2.0);
	}

	if (pattern_mode == 3) {
		// Swirl. Straight bands, with the noise added to the position they are
		// measured from -- so the bands wander and double back instead of
		// ringing the marble like a barber's pole.
		float warp = fbm(p * 0.5) * pattern_sharpness;
		return sin(p.y * 0.9 + p.x * 0.3 + warp * 1.5);
	}

	if (pattern_mode == 4) {
		// Cloud. The noise as it comes, only pushed towards its ends so the
		// mottling has some contrast to it.
		float n = fbm(p) * 2.0 - 1.0;
		return sign(n) * pow(abs(n), 1.0 / pattern_sharpness);
	}

	if (pattern_mode == 5) {
		// Streak. The same noise sampled through a squashed space: a feature
		// that would be a blob is stretched into a stroke along one axis.
		float n = fbm(p * vec3(1.0, 0.09, 1.0)) * 2.0 - 1.0;
		return sign(n) * pow(abs(n), 1.0 / pattern_sharpness);
	}

	return 0.0;
}


void vertex() {
	surface_direction = normalize(VERTEX);
}


void fragment() {
	// 0 facing straight at us, 1 at the silhouette. Both the shading and the rim
	// are built from this, so they always agree about where the edge is.
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);

	float shade = pow(facing, shade_power) * shade_strength;
	float rim = pow(facing, rim_power) * rim_strength;

	vec3 grained = normalize(surface_direction) * pattern_scale;
	float pattern = pattern_at(grained) * pattern_strength;

	// Worked out before the shading, so the formation darkens towards the
	// silhouette along with everything else rather than floating over it.
	vec3 body = mix(base_colour.rgb, pattern_colour.rgb, max(pattern, 0.0));
	body = mix(body, pattern_shadow.rgb, max(-pattern, 0.0));

	ALBEDO = mix(body, shade_colour.rgb, shade);

	METALLIC = metallic_amount;
	SPECULAR = specular_amount;
	ROUGHNESS = clamp(surface_roughness + pattern * pattern_roughness, 0.0, 1.0);

	if (pattern_relief > 0.0) {
		// Which way the pattern is climbing, from three more samples a short
		// step away. Tilting the normal along that slope is what makes a fleck
		// sit proud of the surface instead of being a sticker on it.
		float step_size = 0.35;
		float here = pattern_at(grained);
		vec3 slope = vec3(
			pattern_at(grained + vec3(step_size, 0.0, 0.0)) - here,
			pattern_at(grained + vec3(0.0, step_size, 0.0)) - here,
			pattern_at(grained + vec3(0.0, 0.0, step_size)) - here) / step_size;

		// The slope is in the model's space and the normal is in the camera's,
		// so it has to be carried across before the two can be added. Only the
		// part of it lying along the surface counts -- the part pointing out of
		// the surface would push the normal away from the marble rather than
		// tilt it.
		vec3 view_slope = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope, 0.0)).xyz;
		view_slope -= dot(view_slope, NORMAL) * NORMAL;

		NORMAL = normalize(NORMAL - view_slope * pattern_relief * 0.25);
	}

	// The rim sits in emission rather than albedo so it stays bright on the dark
	// side of the marble, where an albedo edge would simply be unlit.
	EMISSION = rim_tint.rgb * rim + glow_colour.rgb * base_colour.rgb * glow_strength;
}
