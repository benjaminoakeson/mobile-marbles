shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// One wisp of moving air: a crescent, thin at both tips and full in the middle,
// bowed across the quad it is drawn on.
//
// The bow is the whole point. A wind made of straight streaks reads as rain; it
// is the curve that says air moving around something. Drawn here rather than
// traced from where the particle has been, because Godot's particle trails do
// not survive the mobile renderer -- with turbulence off and no spread at all
// they still come out as a starburst of scattered ribbons rather than as the
// path each wisp took. So the quad is turned to face the camera and pointed
// along its own travel by the emitter's `transform_align`, and the shape it
// carries supplies the curve that the trail was supposed to.
//
// The quad is tall in Y because that is the axis `transform_align` lays along
// the direction of travel: V runs from the tail of the wisp to its head.

// How far the crescent bows across the quad, as a fraction of its width. At 0 it
// is a straight streak.
uniform float bow : hint_range(0.0, 0.5) = 0.33;

// Half the width of the fattest part, in the same fraction.
uniform float thickness : hint_range(0.02, 0.5) = 0.1;

// How sharply it narrows towards the tips. Below 1 it stays full most of the way
// and ends abruptly; above 1 it is a long needle.
uniform float taper : hint_range(0.2, 3.0) = 0.6;

// How soft the long edges are, against the width. Kept low: a wisp with a wide
// gradient down each side reads as a smudge.
uniform float edge_softness : hint_range(0.01, 1.0) = 0.55;

// Which way this particular wisp bows, and how far, from -1 to 1. Read in the
// vertex stage and handed across, because INSTANCE_CUSTOM does not exist in the
// fragment stage -- reading it there is a compile error, and a sky full of
// untextured grey rectangles is what that looks like on screen.
varying float sway;


void vertex() {
	// INSTANCE_CUSTOM.y is the per-particle animation offset, which nothing here
	// is using as an animation offset. The process material hands out a random
	// one per wisp, and a free random per particle is exactly what a field of
	// otherwise identical crescents needs.
	sway = INSTANCE_CUSTOM.y * 2.0 - 1.0;
}


void fragment() {
	float along = UV.y;
	float across = UV.x - 0.5;

	// Zero at both tips and widest in the middle, which is what makes the ends
	// come to a point and the belly of the crescent full.
	float span = sin(along * PI);

	float centre = bow * sway * span;
	float half_width = max(thickness * pow(span, taper), 0.0001);

	float d = abs(across - centre) / half_width;
	float shape = 1.0 - smoothstep(1.0 - edge_softness, 1.0, d);

	// Take the very tips off, so a wisp fades in and out along its length
	// instead of ending on a hard cap.
	shape *= smoothstep(0.0, 0.14, along) * (1.0 - smoothstep(0.82, 1.0, along));

	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * shape;
}
