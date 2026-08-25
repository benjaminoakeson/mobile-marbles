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


void fragment() {
	// 0 facing straight at us, 1 at the silhouette. Both the shading and the rim
	// are built from this, so they always agree about where the edge is.
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);

	float shade = pow(facing, shade_power) * shade_strength;
	float rim = pow(facing, rim_power) * rim_strength;

	ALBEDO = mix(base_colour.rgb, shade_colour.rgb, shade);

	METALLIC = metallic_amount;
	SPECULAR = specular_amount;
	ROUGHNESS = surface_roughness;

	// The rim sits in emission rather than albedo so it stays bright on the dark
	// side of the marble, where an albedo edge would simply be unlit.
	EMISSION = rim_tint.rgb * rim + glow_colour.rgb * base_colour.rgb * glow_strength;
}
