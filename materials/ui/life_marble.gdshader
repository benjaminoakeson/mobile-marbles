shader_type canvas_item;

// One life, drawn as a small glass marble.
//
// Drawn rather than textured: the HUD wants a crisp ball at whatever size the
// screen happens to be, and a sphere shaded from its own normal costs less than
// an image and never goes soft when it is scaled up.

uniform vec4 body_colour : source_color = vec4(0.38, 0.68, 1.0, 1.0);
uniform vec4 sheen_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Where the light sits. Y counts DOWN in UV space, so a negative y is above.
uniform vec3 light_direction = vec3(-0.45, -0.6, 0.65);

// How far the edge is feathered, as a fraction of the radius. This is the only
// antialiasing the ball gets, so it wants to stay a pixel or two wide.
uniform float edge_softness : hint_range(0.005, 0.2) = 0.035;


void fragment() {
	// Straight from the middle of the rect out to its edge.
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);

	// The surface normal of a ball filling that rect: x and y are where we are
	// across it, and z is however much is left over.
	float z = sqrt(max(1.0 - d * d, 0.0));
	vec3 n = vec3(p, z);

	float lambert = clamp(dot(n, normalize(light_direction)), 0.0, 1.0);

	// A tight hot spot where the light hits square on, and a thin bright edge
	// where the surface turns away -- the two things that read as glass.
	float hot_spot = pow(lambert, 26.0);
	float rim = pow(clamp(d, 0.0, 1.0), 4.0);

	vec3 col = body_colour.rgb * (0.32 + 0.78 * lambert);
	col += sheen_colour.rgb * hot_spot * 0.95;
	col += sheen_colour.rgb * rim * 0.3;

	COLOR = vec4(col, (1.0 - smoothstep(1.0 - edge_softness, 1.0, d)) * body_colour.a);
}
