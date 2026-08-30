shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled,
		diffuse_burley, specular_schlick_ggx;

// Glass with a checkerboard in it, for the middle of the goal ring.
//
// The pattern is drawn from the UVs, which on this pane are not a 0-to-1 wrap
// but plain metres across its face. Every shard it breaks into is handed the
// coordinates it was cut at, in those same metres, so the board carries through
// the smash: each piece flies off wearing the squares it had while it was still
// part of the pane, at the size it had them.
//
// It is deliberately faint. The point of a pane in a goal ring is seeing the
// level through it; the checker is there to catch the light and say "glass with
// something to it", not to be read as a floor tile.

group_uniforms pattern;

// The glass itself, under the checker. Very nearly neutral: the squares are
// meant to read as black and white, and any real tint in here turns the whole
// board that colour long before it tints the glass.
uniform vec4 tint : source_color = vec4(0.84, 0.86, 0.88, 1.0);
uniform vec4 light_square : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform vec4 dark_square : source_color = vec4(0.04, 0.045, 0.055, 1.0);

// Metres across one square. The goal's pane is 2.1 m wide, so the default puts
// about nine of them across it -- the same busy-ness as the checker on the ring.
uniform float square_size : hint_range(0.02, 1.0, 0.01) = 0.23;

// How far the squares are allowed to pull the glass away from `tint`. This is
// the faintness knob: 0 is plain glass, 1 is a hard black-and-white board.
uniform float pattern_strength : hint_range(0.0, 1.0, 0.01) = 0.42;

group_uniforms shine;

uniform float polish : hint_range(0.0, 1.0, 0.01) = 0.06;
uniform float sheen : hint_range(0.0, 1.0, 0.01) = 0.92;

// How much the glass firms up as it turns away from the viewer. Real glass goes
// from nearly invisible face-on to a hard reflection at a glancing angle, and
// that one curve does more for reading as glass than anything else here.
uniform float base_alpha : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float edge_alpha : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float edge_sharpness : hint_range(1.0, 8.0, 0.1) = 3.0;

// How solid the glass goes under its own highlights. See the note in fragment().
uniform float shine_opacity : hint_range(0.0, 1.0, 0.01) = 0.55;

// The brightest the reflection is allowed to get. See the note in fragment().
uniform float shine_ceiling : hint_range(0.1, 4.0, 0.05) = 1.1;

// The dark squares are given a little more body than the light ones, so the
// board reads even where nothing is lighting it.
uniform float square_alpha : hint_range(0.0, 0.5, 0.01) = 0.14;

group_uniforms reflection;

// The pane reflects a sky and a ground rather than the real world around it.
//
// This is what makes it look polished, and it has to be faked: the levels are
// lit from almost straight overhead, so a pane stood on its edge catches nothing
// off the sun and comes out flat and milky however low its roughness goes.
//
// The made-up sky is anchored to the SCREEN, not to the world -- up in the
// reflection means up in the frame. Anchored to the world it is dourly correct
// and looks it: a ring on the ground, seen by a camera above it, reflects the
// floor, so the goal spends the whole level showing the player a dark grey disc.
// Screen-anchored, the light always sits toward the top of the pane and the
// horizon always crosses it, wherever the camera has got to.
uniform vec4 sky_colour : source_color = vec4(0.90, 0.95, 1.0, 1.0);
uniform vec4 ground_colour : source_color = vec4(0.03, 0.035, 0.05, 1.0);
uniform float reflectivity : hint_range(0.0, 2.0, 0.01) = 0.9;

// The bright line where that sky meets that ground. Worth its own control: a
// reflected horizon sweeping across the pane as the camera moves is most of what
// sells a flat surface as polished, and it costs one smoothstep.
uniform vec4 horizon_colour : source_color = vec4(1.0, 0.99, 0.95, 1.0);
uniform float horizon_strength : hint_range(0.0, 2.0, 0.01) = 0.45;
uniform float horizon_width : hint_range(0.01, 0.5, 0.01) = 0.08;

// Where the band sits, as a share of the way up the reflection. Deliberately off
// centre: at 0.5 it lands exactly where a pane looked at face-on reflects, and
// the swell then carves it into ribbons across the whole disc -- which reads as
// oil on water rather than as glass, and buries the checker underneath it.
uniform float horizon_height : hint_range(0.0, 1.0, 0.01) = 0.42;

// A sun for the pane to catch, given as the direction TOWARDS it. Not the
// level's own sun: that one is almost overhead, which a pane stood on its edge
// can never show the player. This one hangs off the viewer's shoulder, so the
// goal always has a highlight on it whichever way the level has been turned.
// Given in screen terms, to match: x right, y up, z out of the frame. Kept well
// round towards the viewer, so the highlight is on the pane at the angle the
// chase camera actually watches the goal from rather than only in profile.
uniform vec3 sun_towards = vec3(-0.3, 0.42, 0.86);
uniform float sun_strength : hint_range(0.0, 4.0, 0.01) = 1.5;
uniform float sun_tightness : hint_range(2.0, 128.0, 1.0) = 5.0;

// How much of that reflection survives face-on. Glass at a glancing angle is a
// mirror and face-on is nearly a window, so most of it belongs at the edges.
uniform float face_on_reflection : hint_range(0.0, 1.0, 0.01) = 0.12;

group_uniforms ripple;

// A slow swell across the pane, tilting the normal by a hair.
//
// Not decoration: a dead flat mirror reflects the same direction everywhere on
// it, so a reflected sun is either on the whole pane or off it, and the horizon
// cannot travel across it at all. Real glass is never quite flat, and the
// slightest waviness is what lets the highlight move and pool. Keep it small --
// this should read as glass, not as water. One long swell across the pane is
// what is wanted; wind the scale up and the highlight breaks into ribbons and
// starts reading as oil.
uniform float ripple_strength : hint_range(0.0, 1.0, 0.005) = 0.13;
uniform float ripple_scale : hint_range(0.5, 20.0, 0.1) = 1.4;

group_uniforms glint;

// A slow bar of light travelling across the pane. The goal used to breathe to
// draw the eye; this does that job without moving any geometry, which is what
// let the breathing go.
uniform vec4 glint_colour : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float glint_strength : hint_range(0.0, 2.0, 0.01) = 0.7;
uniform float glint_speed : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float glint_span : hint_range(0.2, 8.0, 0.1) = 3.0;
uniform float glint_width : hint_range(0.01, 0.5, 0.01) = 0.13;




// A checkerboard that fades to flat grey as the squares get smaller than the
// pixels drawing them, instead of tearing into noise.
//
// The trick is to integrate the pattern across the pixel rather than sample it
// at a point: a checker is the product of two square waves, and a square wave's
// integral is a triangle wave, so the average over a pixel comes out in closed
// form. Far away the two triangles cancel to a half and the pane goes evenly
// grey -- which is exactly what a checkerboard looks like from a distance.
float checkerboard(vec2 at) {
	vec2 width = fwidth(at) + 0.001;
	vec2 swept = 2.0 * (abs(fract((at - 0.5 * width) * 0.5) - 0.5)
			- abs(fract((at + 0.5 * width) * 0.5) - 0.5)) / width;
	return 0.5 - 0.5 * swept.x * swept.y;
}


void fragment() {
	// Metres across the pane, whether this is the pane or a piece of it.
	vec2 across = UV;
	float squares = checkerboard(across / square_size);

	vec3 board = mix(light_square.rgb, dark_square.rgb, squares);
	ALBEDO = mix(tint.rgb, board, pattern_strength);

	// Absolute, because the pane is drawn from both sides: the goal is open
	// either way, and a back face must not come out inside-out.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(1.0 - facing, edge_sharpness);

	// One bar, travelling. It wraps at the halfway point, where the bar is not,
	// so the loop never shows a seam.
	float travel = fract(dot(across, normalize(vec2(1.0, 0.55))) / glint_span
			- TIME * glint_speed);
	float bar = 1.0 - smoothstep(0.0, glint_width, abs(travel - 0.5));

	// Tilt the normal along the swell before anything reflects off it. The offset
	// is built in the pane's own space -- where the face is always +/- Y and the
	// surface is XZ -- then carried into view space, so it needs no tangents.
	// The shards have no tangents to offer, and they are cut on these same axes.
	vec2 swell = across * ripple_scale;
	float slope_u = cos(swell.x + swell.y * 0.8) + 1.26 * cos(swell.x * 2.1 - swell.y * 1.4);
	float slope_v = 0.8 * cos(swell.x + swell.y * 0.8) - 0.84 * cos(swell.x * 2.1 - swell.y * 1.4);
	// UV x runs along the pane's Z and UV y along its X, matching the cuts.
	vec3 tilt = (VIEW_MATRIX * MODEL_MATRIX * vec4(slope_v, 0.0, slope_u, 0.0)).xyz;
	vec3 surface = normalize(normalize(NORMAL) + tilt * ripple_strength * 0.3);

	// Left in view space on purpose -- see the note on the sky above.
	vec3 aimed = reflect(-normalize(VIEW), surface);
	float skyward = clamp(aimed.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 mirrored = mix(ground_colour.rgb, sky_colour.rgb,
			smoothstep(0.3, 0.72, skyward));

	// The horizon: a band around the level of the reflected eye, brightest right
	// at it. Narrow, or it stops being a horizon and becomes a wash.
	float horizon = 1.0 - smoothstep(0.0, horizon_width, abs(skyward - horizon_height));

	// And a sun in it. Two lobes: a tight core for the highlight itself and a
	// wide one for the haze around it, which is what stops it reading as a dot.
	float towards_sun = clamp(dot(aimed, normalize(sun_towards)), 0.0, 1.0);
	float core = pow(towards_sun, sun_tightness);
	float halo = pow(towards_sun, 3.0) * 0.3;

	// The two are kept apart on purpose. The broad sky-to-ground wash is what a
	// pane shows when it is turned away from you, so it is held almost entirely
	// at the edges -- let it face-on and it lies over the whole disc as milk and
	// the checkerboard disappears under it. The horizon and the sun are narrow
	// enough to be highlights wherever they land, so they are let through.
	vec3 wash = mirrored * reflectivity * mix(face_on_reflection, 1.0, edge);
	vec3 highlights = (horizon_colour.rgb * horizon * horizon_strength
			+ sky_colour.rgb * (core + halo) * sun_strength) * reflectivity;

	vec3 shine = wash + highlights + glint_colour.rgb * bar * bar * glint_strength;

	// Capped, or a shard tumbling through the angle that catches everything at
	// once blows out to flat white and stops looking like glass at all.
	shine = min(shine, vec3(shine_ceiling));

	ROUGHNESS = polish;
	METALLIC = 0.0;
	SPECULAR = sheen;
	NORMAL = surface;
	RIM = 0.7;
	RIM_TINT = 0.25;

	EMISSION = shine;

	// Blending scales everything above by ALPHA, so a highlight that lands on
	// see-through glass is a highlight nobody sees. The glass is therefore made
	// to firm up under its own shine, by however bright that shine came out --
	// which is also what real glass does where it catches the light.
	float lit = clamp(dot(shine, vec3(0.33, 0.5, 0.17)), 0.0, 1.0);
	ALPHA = clamp(base_alpha + squares * square_alpha + edge * edge_alpha
			+ lit * shine_opacity, 0.0, 1.0);
}
