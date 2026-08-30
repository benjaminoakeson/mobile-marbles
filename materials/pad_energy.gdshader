shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The face of a speed or slow pad: chevrons of energy running along it, pointing
// the way the pad is going to shove the ball.
//
// The direction is the tell that survives being colour-blind, seen out of the
// corner of the eye, or lit by whatever the level's sky happens to be. A speed
// pad throws its energy forwards, the way you are about to be sped up; a slow
// pad throws it backwards, which is the way its force actually acts on you. The
// colour agrees -- blue forwards, red back -- but the motion reads first.
//
// Additive and unshaded, so the pad glows out of the track rather than being a
// sticker on it, and so the bright crest of each chevron runs over 1 and blooms
// in the levels' glow.

// Set per pad from `speed_pad.gd`, along with `flow` below.
uniform vec4 energy_colour : source_color = vec4(0.25, 0.62, 1.0, 1.0);

// Which way the chevrons run and point along the pad, +1 or -1. This is the
// whole difference between a pad that pushes and one that drags.
uniform float flow = 1.0;

// How many chevrons there are along the pad, and how fast they travel. The
// script works the count out from the pad's real length, so they stay the same
// size in metres however big a pad is dragged out.
uniform float bands : hint_range(0.5, 16.0) = 3.0;
uniform float pulse_speed : hint_range(0.0, 4.0) = 0.9;

// How far the tip of each chevron leads its trailing edges, as a fraction of the
// spacing. 0 is a plain bar across the pad, and the further from 0 the sharper
// the arrowhead.
//
// SIGNED, and that sign is the only thing that decides which way the head faces.
// It is deliberately its own knob rather than being folded into `flow`: which
// way the pattern travels and which way its arrowheads point come out of the
// same maths but are not the same question, and they have been wrong
// independently of each other. Negate this to turn the heads round without
// touching the direction they run in.
uniform float chevron : hint_range(-1.0, 1.0) = -1.0;

// How hard the crest of a chevron burns. Over 1 on purpose -- that is what the
// glow catches.
uniform float brightness : hint_range(0.0, 6.0) = 2.6;

// The always-on wash under them, so the pad's footprint is readable between two
// crests.
uniform float fill : hint_range(0.0, 1.0) = 0.16;

// How sharp a chevron is. Higher is a thin bright line, lower is a broad swell.
uniform float band_sharpness : hint_range(1.0, 12.0) = 3.0;

// How far in from the border the pad fades out, as a fraction of its half-width.
uniform float edge_softness : hint_range(0.0, 0.6) = 0.16;


void fragment() {
	// V runs along the pad, U across it. The plane is laid flat and sized from
	// the pad's own footprint, so these are the pad's own axes.
	float along = UV.y;
	float across = abs(UV.x - 0.5) * 2.0;

	// The chevron: the middle of the pad held off from its edges along the run,
	// which turns a plain bar into an arrowhead. The offset follows `flow` so the
	// head turns round when the pad does, and `chevron`'s own sign sets which way
	// round it sits.
	float phase = along - across * chevron / max(bands, 0.001) * flow;

	float wave = sin(phase * bands * TAU - TIME * pulse_speed * TAU * flow);

	// Only the crests, and sharpened, so what shows is a set of running arrows
	// rather than a sine wash.
	float band = pow(max(wave, 0.0), band_sharpness);

	// Off at all four borders, so the pad has no hard edge to catch the eye.
	float to_edge = min(1.0 - across, 2.0 * min(along, 1.0 - along));
	float edge = smoothstep(0.0, edge_softness, to_edge);

	ALBEDO = energy_colour.rgb * (fill + band) * edge * brightness;
}
