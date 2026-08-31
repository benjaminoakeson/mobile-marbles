shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// The dent the ball presses into the ground: the groove it leaves rolling, and
// the crater a heavy landing digs.
//
// Both are the same cross-section -- a bowl with the ground heaped up in a lip
// around it -- so both are drawn here. A track measures that bowl ACROSS the
// ribbon it is laid along; a crater measures it out from its own middle. That is
// the only difference between them, and `radial` is what picks.
//
// The blending is what makes it read as a dent rather than as a decal stuck on
// the floor. In premultiplied alpha the alpha is what is taken away from what is
// already there and the colour is what is put back, so ONE pass can both darken
// and brighten: the hollow keeps light out of it, and the lip standing proud
// around it catches a little more than it loses. A plain transparent quad can
// only ever darken, and a groove with no lit rim reads as a stain.
//
// Unshaded on purpose. The mark has no light of its own to answer to -- it is a
// change to how much of the level's light comes back off the floor it is pressed
// into, which is the same on every level and costs nothing to work out.

// A crater measures from its middle; a track measures across its width.
uniform bool radial = false;

// What the marble leaves in the mark, over and above the dent it presses. A
// glow of zero is a plain dent in the ground, which is what a marble with
// nothing to leave behind presses; the animated ones leave their own stuff
// smeared along the floor. Handed in by [RollMarks] off the skin being worn.
uniform float trail_glow : hint_range(0.0, 1.0) = 0.0;

// The marble itself, drawn small and live by [RollMarks], so what is left on the
// ground is the SKIN rather than a colour picked to stand in for it: lava leaves
// crust with the melt showing through its cracks, frost leaves crystals, and all
// of it goes on moving after the marble has rolled away, because the picture
// being sampled is still being drawn.
uniform sampler2D skin_texture : source_color, filter_linear, repeat_enable;
uniform bool use_skin = false;

// The colour left behind when there is no skin to sample -- what a mark falls
// back to before the first frame of the marble has been drawn.
uniform vec4 trail_colour : source_color = vec4(1.0);

// How much light the hollow keeps out.
uniform float hollow_shade : hint_range(0.0, 1.0) = 0.45;

// How much the lip throws back. Small: it is a ridge of the same ground, not a
// highlight on something wet.
uniform float lip_light : hint_range(0.0, 1.0) = 0.025;

// Where the lip sits, as a fraction of the way out from the middle.
uniform float lip_at : hint_range(0.2, 1.0) = 0.85;

// How sharply the lip is heaped.
uniform float lip_width : hint_range(0.02, 0.5) = 0.07;


void fragment() {
	vec2 from_middle = UV * 2.0 - 1.0;
	float out_from = radial ? length(from_middle) : abs(from_middle.y);

	// Square quads, round marks.
	if (out_from > 1.0) {
		discard;
	}

	// The bowl, deepest in the middle and up to nothing by the rim.
	float hollow = 1.0 - smoothstep(0.0, lip_at, out_from);

	// The ground pushed out of the bowl, heaped just outside it.
	float lip = exp(-pow((out_from - lip_at) / lip_width, 2.0));

	// Faded out before the very edge, so the mark has no outline of its own.
	float mark = COLOR.a * (1.0 - smoothstep(0.86, 1.0, out_from));

	// What the marble left in the mark. It pools in the hollow, with a little
	// caught on the lip, and it goes SQUARED with what is left of the mark -- so
	// the heat is out of it well before the ground has closed over it, which is
	// how a hot thing dragged across a floor looks a moment later.
	float pooled = mark * mark * (hollow * 0.85 + lip * 0.3);

	// Read out of the middle of the marble, well inside its silhouette: the edge
	// of it is rim light and glass, which is a fact about looking at a ball and
	// not about what the ball is made of.
	//
	// A track reads it running along its own length, so the stuff is laid down
	// the trail rather than stretched along it; a crater reads it straight, so
	// it is a round patch of the marble sitting where the marble hit.
	vec2 patch = radial ? UV : vec2(fract(UV.x), UV.y);
	vec2 middle = mix(vec2(0.28), vec2(0.72), patch);

	vec3 stuff = use_skin ? texture(skin_texture, middle).rgb : trail_colour.rgb;
	vec3 left_behind = stuff * trail_glow * pooled * 1.3;

	// A dent with something glowing in it is not also a shadow. The more the
	// trail lights it, the less the hollow is allowed to keep out.
	float shading = hollow * hollow_shade * (1.0 - trail_glow * 0.75);

	// Taken off the ground, and put back on the lip and in whatever was left.
	ALPHA = mark * clamp(shading + lip * lip_light, 0.0, 1.0);
	ALBEDO = vec3(mark * lip * lip_light * 0.9) + left_behind;
}
