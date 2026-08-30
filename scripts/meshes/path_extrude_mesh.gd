@tool
class_name PathExtrudeMesh
extends PrimitiveMesh
## A cross-section swept along a [Curve3D], with width and height that can vary
## along the way.
##
## Two profiles are available: [code]RECTANGLE[/code] for roads, ramps and
## beams, and [code]CYLINDER[/code] for pipes and tunnels. Either one can
## be [member hollow], which keeps the outer surface and adds an inner one
## [member wall_thickness] inside it, so the result is a tube you can travel
## through rather than a solid.
##
## [member width_profile] and [member height_profile] are ordinary [Curve]
## resources multiplying the base size, sampled from the start of the path to
## its end. Add a point at 0.5 with value 2.0 and the path is twice as wide
## halfway along; drop it to 0.5 and it pinches there instead.
##
## A polyline dropped with the [Path3D] gizmo is a set of creases, so the sweep
## shapes it first: [member cornering] decides whether it is carried through the
## points on one smooth curve or run straight between them with the corners
## rounded, and [member corner_smoothing] how strongly. Slices are
## then placed where the shape needs them rather than evenly: a straight run
## costs a handful, while a bend gets as many as [member max_turn_angle] asks
## for. See [member segment_mode].
##
## The surface is closed and watertight, so [CSGMesh3D] booleans it cleanly.
## See [CSGPathExtrude3D] for the ready-made CSG node, which drives this from a
## [Path3D] you can edit with the normal path gizmo.

## Shape of the swept cross-section.
enum Profile {
	RECTANGLE, ## Four flat sides: a road, ramp or beam.
	CYLINDER, ## A round tube, sized by [member width] and [member height].
}

## How the path is shaped between the points.
enum Cornering {
	SPLINE, ## A smooth curve flowing through every point.
	FILLET, ## Straight runs between the points, with the corners rounded off.
}

## How slices are spread along the path.
enum SegmentMode {
	ADAPTIVE, ## As many as the shape needs: sparse on straights, dense in turns.
	UNIFORM, ## A fixed [member path_segments], evenly spaced.
}

## How the swept sides are lit.
enum Shading {
	AUTO, ## Faceted for [code]RECTANGLE[/code], smooth for [code]CYLINDER[/code].
	FLAT, ## Every side gets its own hard-edged normal.
	SMOOTH, ## Normals are averaged across the profile, hiding the facets.
}

const MIN_SIZE := 0.001

## Ceiling on what adaptive slicing may produce, so a pathological curve cannot
## quietly hand the CSG tree a six-figure vertex count.
const MAX_ADAPTIVE_SEGMENTS := 1024

## How close two points must be before the rounding treats them as one.
const MERGE_DISTANCE := 0.001

## How much longer a slice may be than the one beside it. A straight running into
## a turn otherwise ends in one long slice butted against a row of short ones,
## and the chord across that long slice visibly cuts the corner.
const SEGMENT_GRADING := 2.0

## How far past either end of the path the sweep may run, as a fraction of the
## path's length. See [member path_start].
const PATH_OVERSHOOT := 0.15

## How many places along the path the cross-section is measured when working out
## how much room a corner has to leave itself. See [method _profile_reach].
const REACH_SAMPLES := 16

## How much wider than the bare minimum a corner is opened out. Opening it to
## exactly the sweep's own reach leaves the inside edge with no width at all --
## a pinch line rather than a fold, which is better but still not a surface --
## and the arc is a cubic approximation baked to chords, both of which cut a
## shade inside the nominal radius. A little over gives the inside edge some
## actual geometry to be made of.
const CORNER_CLEARANCE_MARGIN := 1.2

## How steeply the path may climb before its cross-section stops being levelled,
## as the cosine of the angle off horizontal: level up to about seventy degrees,
## fully carried past about eighty-seven, and eased across in between. See
## [method _up_at].
const LEVEL_FULL := 0.94
const LEVEL_NONE := 0.999

## The path to sweep along. Needs at least two points to produce geometry.
@export var curve: Curve3D = null:
	set(value):
		if curve == value:
			return
		_unwatch(curve)
		curve = value
		_watch(curve)
		request_update()

@export var profile: Profile = Profile.RECTANGLE:
	set(value):
		profile = value
		notify_property_list_changed()
		request_update()

## Full width of the cross-section, before [member width_profile] is applied.
@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var width: float = 4.0:
	set(value):
		width = maxf(value, MIN_SIZE)
		request_update()

## Full height of the cross-section, before [member height_profile] is applied.
@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var height: float = 0.5:
	set(value):
		height = maxf(value, MIN_SIZE)
		request_update()

## Sides around a [code]CYLINDER[/code] profile.
@export_range(3, 128, 1)
var radial_segments: int = 24:
	set(value):
		radial_segments = maxi(value, 3)
		request_update()

## How the path gets from one point to the next.
##
## SPLINE bends the whole way. Every point's tangent is taken from the line
## joining its two neighbours, so the path is already leaning into a turn well
## before it arrives and is still leaning after it leaves, and there is no
## stretch of it that is not curving a little.
##
## FILLET is the older shape: dead-straight runs between the points with the
## corners rounded off. It keeps the straights straight, which is what a
## deliberately technical course wants -- long approach, defined corner, long
## exit -- but it is also why a path can read as turning on a dime, because all
## the turning is packed into the corners and everywhere else is a ruled line.
##
## The difference is WHERE the turning goes, not how much of it there is. Over
## the same five points both come out at about the same tightest radius; FILLET
## leaves a third of the path dead straight and SPLINE leaves almost none. SPLINE
## also passes through every point, where a fillet cuts the corner off and misses
## them.
##
## They part company on tight corners. FILLET will open a corner out until the
## shape being swept fits round the inside of it -- see [method _corner_arc] --
## and SPLINE has no equivalent lever, because its shape is fixed by where the
## points are. So a wide sweep round a corner made of three points and nothing
## else can still pinch on the inside under SPLINE. Give the corner more points
## and it comes right; or put that one node on FILLET, which will open the arc
## for you at the cost of straightening everything either side of it.
@export var cornering := Cornering.SPLINE:
	set(value):
		cornering = value
		request_update()

## How much of that shaping to apply, from none to all of it.
##
## Under SPLINE it is tension: 0 runs straight from point to point, 1 is the full
## curve. Under FILLET it is how far back into each segment the corner is cut, as
## a fraction of the shorter of the two meeting there -- 1 rounds as far as it
## can without eating into its neighbour.
##
## Either way it is proportional rather than a fixed radius, so it follows how
## you placed the points: two far apart bend gently, two close together bend
## hard. And either way 0 means the path runs straight through every point,
## corners and all. It is a different thing from [member max_turn_angle], which
## only decides how finely a bend is sliced once its shape is settled.
##
## Full is the default because it is the best of both, and under SPLINE the
## middle of the range is the worst of them: at half tension the path runs nearly
## straight between the points and then whips through a tight kink at each one,
## which is tighter than the fillet it replaced. Wind it down towards the
## polyline only if that is what you actually want.
##
## A point whose [Path3D] handles you have pulled out is already shaped by hand
## and is left exactly as it is, under both.
@export_range(0.0, 1.0, 0.01)
var corner_smoothing: float = 1.0:
	set(value):
		corner_smoothing = clampf(value, 0.0, 1.0)
		request_update()

## How slices are spread along the path. [code]ADAPTIVE[/code] spends them where
## the shape actually bends and leaves straight runs cheap; [code]UNIFORM[/code]
## ignores the shape and lays down [member path_segments] of them.
@export var segment_mode: SegmentMode = SegmentMode.ADAPTIVE:
	set(value):
		segment_mode = value
		notify_property_list_changed()
		request_update()

## Slices along the whole path, in [code]UNIFORM[/code] mode only.
@export_range(1, 1024, 1, "or_greater")
var path_segments: int = 32:
	set(value):
		path_segments = maxi(value, 1)
		request_update()

## How far apart slices may get where nothing is happening. This is the straight
## runs' budget: a truly straight stretch needs no more detail than this, so
## raise it to stop long straights costing geometry.
@export_range(0.05, 50.0, 0.01, "or_greater", "suffix:m")
var max_segment_length: float = 8.0:
	set(value):
		max_segment_length = maxf(value, 0.05)
		request_update()

## How far the path may turn between one slice and the next. This is the knob for
## how smooth the turns are, and the only one most corners need: at 5 degrees a
## right-angle bend gets 18 slices and a full loop 72, however long or short the
## bend happens to be. Lower it for smoother turns, raise it for cheaper ones.
## Banking from a [Path3D]'s point tilt counts as turning too. Below about 3
## degrees the curve's own [member Curve3D.bake_interval] — 0.2 m by default —
## becomes the limit on how precisely a tight bend can be measured; lower it on
## the [Curve3D] if you need to go finer than that.
@export_range(0.5, 90.0, 0.1, "suffix:°")
var max_turn_angle: float = 5.0:
	set(value):
		max_turn_angle = clampf(value, 0.5, 90.0)
		request_update()

## How much the cross-section may resize between one slice and the next, so a
## [member width_profile] that flares halfway down a straight still gets the
## slices to show it. Measured on the half-width and half-height.
@export_range(0.005, 10.0, 0.005, "or_greater", "suffix:m")
var max_shape_change: float = 0.25:
	set(value):
		max_shape_change = maxf(value, 0.005)
		request_update()

## Slices the last rebuild produced, for weighing detail against cost. It
## reports a finished build, so a sweep that has not been drawn or asked for its
## surface yet still reads zero.
@export var segment_count: int = 0

## Multiplies [member width] along the path. The curve's X axis runs from the
## start of the path (0) to its end (1); set the curve's own domain to the path's
## length in metres if you would rather place points in metres. A [Curve] only
## allows values from 0 to 1 until you raise its Max Value, so widen that first
## or anything above 1.0 is clamped away.
@export var width_profile: Curve = null:
	set(value):
		if width_profile == value:
			return
		_unwatch(width_profile)
		width_profile = value
		_watch(width_profile)
		request_update()

## Multiplies [member height] along the path, like [member width_profile].
@export var height_profile: Curve = null:
	set(value):
		if height_profile == value:
			return
		_unwatch(height_profile)
		height_profile = value
		_watch(height_profile)
		request_update()

## Shifts the cross-section sideways and vertically off the path. Set Y to
## [code]-height / 2[/code] to hang a road's surface on the path line instead of
## running the path through the middle of the slab.
@export var profile_offset: Vector2 = Vector2.ZERO:
	set(value):
		profile_offset = value
		request_update()

## Where along the path the sweep starts, as a fraction of its length. Together
## with [member path_end] this shortens the path without touching its points.
##
## Either may also run [constant PATH_OVERSHOOT] past its end -- below 0 for the
## start, above 1 for the end -- which lengthens the sweep instead of shortening
## it. Past the end there is no path left to follow, so it carries straight on
## in the direction the path was already heading, keeping the banking and the
## width and height it finished at. That is for trimming a piece to meet its
## neighbour without having to go back and move the points.
@export_range(-0.15, 1.15, 0.0001)
var path_start: float = 0.0:
	set(value):
		path_start = clampf(value, -PATH_OVERSHOOT, 1.0 + PATH_OVERSHOOT)
		request_update()

## Where along the path the sweep stops. Runs past the end the same way
## [member path_start] does.
@export_range(-0.15, 1.15, 0.0001)
var path_end: float = 1.0:
	set(value):
		path_end = clampf(value, -PATH_OVERSHOOT, 1.0 + PATH_OVERSHOOT)
		request_update()

## Carves the inside out, leaving walls [member wall_thickness] thick. A hollow
## [code]CYLINDER[/code] is a tunnel; a hollow [code]RECTANGLE[/code] is a covered
## corridor.
@export var hollow: bool = false:
	set(value):
		hollow = value
		notify_property_list_changed()
		request_update()

@export_range(0.001, 10.0, 0.001, "or_greater", "suffix:m")
var wall_thickness: float = 0.25:
	set(value):
		wall_thickness = maxf(value, MIN_SIZE)
		request_update()

## Closes both ends of the sweep. Turning it off leaves an open shell, which
## looks fine on its own but is no longer watertight for CSG booleans.
##
## A closed path is swept all the way round and capped where it meets itself, so
## the loop closes but carries a wall at the seam. That is inside the solid and
## out of sight on a road; it is the one place the sweep is not simply a tube.
@export var end_caps: bool = true:
	set(value):
		end_caps = value
		request_update()

@export var shading: Shading = Shading.AUTO:
	set(value):
		shading = value
		request_update()


## [member curve] with its corners rounded off: what the sweep actually follows.
## Rebuilt with the mesh, never saved.
var _swept: Curve3D = null


## One sample along the path: where it is and how the cross-section is oriented.
class Frame:
	var origin: Vector3
	var right: Vector3
	var up: Vector3
	var forward: Vector3
	var ratio: float ## Position along the whole curve, 0 to 1.
	var distance: float ## Metres travelled since the start of the sweep.


func _validate_property(property: Dictionary) -> void:
	if property.name == "radial_segments" and profile != Profile.CYLINDER:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "wall_thickness" and not hollow:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "path_segments" and segment_mode != SegmentMode.UNIFORM:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name in ["max_segment_length", "max_turn_angle", "max_shape_change"] \
			and segment_mode != SegmentMode.ADAPTIVE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "segment_count":
		# Reported, not set: shown in the inspector but never written to disk.
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _create_mesh_array() -> Array:
	var frames := _build_frames()
	if frames.size() < 2:
		return _placeholder_arrays()

	var outer: Array[PackedVector2Array] = []
	var inner: Array[PackedVector2Array] = []
	for frame in frames:
		var half := _half_size(frame.ratio)
		outer.append(_profile_ring(half.x, half.y))
		if hollow:
			inner.append(_profile_ring(
					maxf(half.x - wall_thickness, MIN_SIZE),
					maxf(half.y - wall_thickness, MIN_SIZE)))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	_add_sides(verts, normals, tangents, uvs, indices, frames, outer, false)
	if hollow:
		_add_sides(verts, normals, tangents, uvs, indices, frames, inner, true)

	if end_caps:
		var last := frames.size() - 1
		if hollow:
			_add_ring_cap(verts, normals, tangents, uvs, indices, frames[0], outer[0], inner[0], false)
			_add_ring_cap(verts, normals, tangents, uvs, indices,
					frames[last], outer[last], inner[last], true)
		else:
			_add_solid_cap(verts, normals, tangents, uvs, indices, frames[0], outer[0], false)
			_add_solid_cap(verts, normals, tangents, uvs, indices, frames[last], outer[last], true)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Places the slices and builds an orientation at each one.
func _build_frames() -> Array[Frame]:
	var frames: Array[Frame] = []
	if curve == null or curve.point_count < 2:
		return frames
	_swept = _rounded_curve()
	var length := _swept.get_baked_length()
	if length <= 0.0:
		return frames

	var from := minf(path_start, path_end) * length
	var to := maxf(path_start, path_end) * length
	if to - from <= MIN_SIZE:
		return frames

	var previous: Frame = null
	for offset in _segment_offsets(from, to, length):
		previous = _frame_at(offset, length, offset - from, previous)
		frames.append(previous)
	segment_count = maxi(frames.size() - 1, 0)
	return frames


## [member curve] with its shape made, which is what the sweep actually follows.
## Rebuilt with the mesh and never written back, so the path you author stays the
## plain polyline you dropped with the gizmo.
func _rounded_curve() -> Curve3D:
	if corner_smoothing <= 0.0 or curve.point_count < 3:
		return curve
	if cornering == Cornering.SPLINE:
		return _splined_curve()
	return _filleted_curve()


## [member curve] carried through every point on one smooth curve.
##
## The points are left exactly where they were put -- only the handles are
## filled in, taken from the line joining each point's two neighbours, a sixth of
## that span each way. That is Catmull-Rom written as cubics, and it is why the
## path has no straight stretches to turn off: it is always already bending
## towards the next point.
##
## [member corner_smoothing] scales those handles, so it reads as tension: at 0
## they vanish and the path is the bare polyline again.
func _splined_curve() -> Curve3D:
	var count := curve.point_count
	var closed: bool = curve.closed if "closed" in curve else false

	var splined := Curve3D.new()
	splined.up_vector_enabled = curve.up_vector_enabled
	if "closed" in splined:
		splined.closed = closed
	splined.bake_interval = curve.bake_interval

	for i in count:
		var in_handle := curve.get_point_in(i)
		var out_handle := curve.get_point_out(i)

		# A point somebody has already shaped by hand keeps the shape they gave
		# it -- the same rule the fillet follows.
		if in_handle.is_zero_approx() and out_handle.is_zero_approx():
			var before := curve.get_point_position(_neighbour(i - 1, count, closed))
			var after := curve.get_point_position(_neighbour(i + 1, count, closed))
			var tangent := (after - before) * (corner_smoothing / 6.0)
			in_handle = -tangent
			out_handle = tangent

		var at := splined.point_count
		splined.add_point(curve.get_point_position(i), in_handle, out_handle)
		splined.set_point_tilt(at, curve.get_point_tilt(i))

	return splined


## The point next door. At the end of an open path there is none, so the point
## itself stands in, which leaves the end tangent running along the last segment
## rather than swinging off it.
func _neighbour(index: int, count: int, closed: bool) -> int:
	if closed:
		return (index + count) % count
	return clampi(index, 0, count - 1)


## [member curve] with every plain corner replaced by an arc.
##
## A corner is cut back by [member corner_smoothing] of the shorter segment
## meeting it, and the two cuts are joined by a cubic that approximates a
## circular arc. Because the cut is a fraction of the segment rather than a fixed
## radius, corners between distant points come out as long gentle bends and
## corners between close ones as tight turns, which is how the spacing of the
## points reads as intent.
func _filleted_curve() -> Curve3D:
	var count := curve.point_count
	var closed: bool = curve.closed if "closed" in curve else false

	# Measured once and handed down: it is the same for every corner, and
	# sampling the profile curves per point adds up on a long path.
	var clearance := _profile_reach()

	var rounded := Curve3D.new()
	rounded.up_vector_enabled = curve.up_vector_enabled
	if "closed" in rounded:
		rounded.closed = closed
	# Arcs are usually far shorter than the straights around them, so the curve
	# is baked fine enough to resolve the smallest one rather than at whatever
	# interval suited the original polyline.
	var finest := curve.bake_interval

	for i in count:
		var tilt := curve.get_point_tilt(i)
		var arc := _corner_arc(i, count, closed, clearance)
		if arc.is_empty():
			var at := rounded.point_count
			rounded.add_point(curve.get_point_position(i),
					curve.get_point_in(i), curve.get_point_out(i))
			rounded.set_point_tilt(at, tilt)
			continue
		# At full smoothing neighbouring corners cut all the way to the middle of
		# the segment between them and their ends land on the same spot. That is
		# one point carrying two handles, not two points a zero-length segment
		# apart — which would leave the curve with a stretch it cannot bake.
		var previous := rounded.point_count - 1
		if previous >= 0 and rounded.get_point_position(previous).distance_to(
				arc["enter"]) < MERGE_DISTANCE:
			rounded.set_point_out(previous, arc["enter_handle"])
		else:
			var enter := rounded.point_count
			rounded.add_point(arc["enter"], Vector3.ZERO, arc["enter_handle"])
			rounded.set_point_tilt(enter, tilt)
		var leave := rounded.point_count
		rounded.add_point(arc["leave"], arc["leave_handle"], Vector3.ZERO)
		rounded.set_point_tilt(leave, tilt)
		finest = minf(finest, maxf(arc["length"] / 16.0, 0.01))

	# The seam of a closed path can meet in the same way, first point to last.
	var last := rounded.point_count - 1
	if closed and last > 0 and rounded.get_point_position(last).distance_to(
			rounded.get_point_position(0)) < MERGE_DISTANCE:
		rounded.set_point_in(0, rounded.get_point_in(last))
		rounded.remove_point(last)

	rounded.bake_interval = finest
	return rounded


## The arc replacing the corner at [param index], or an empty dictionary when
## that point is not a corner this should touch: an end of an open path, a point
## someone has already shaped by hand, or a joint that is already straight.
func _corner_arc(index: int, count: int, closed: bool, clearance: float) -> Dictionary:
	if not closed and (index == 0 or index == count - 1):
		return {}
	var before := (index - 1 + count) % count
	var after := (index + 1) % count
	# Pulling any of the four handles that meet here means the shape of this
	# joint was chosen deliberately, so it is left alone.
	if not (curve.get_point_in(index).is_zero_approx()
			and curve.get_point_out(index).is_zero_approx()
			and curve.get_point_out(before).is_zero_approx()
			and curve.get_point_in(after).is_zero_approx()):
		return {}

	var corner := curve.get_point_position(index)
	var arriving := corner - curve.get_point_position(before)
	var leaving := curve.get_point_position(after) - corner
	if arriving.length() < 1e-4 or leaving.length() < 1e-4:
		return {}
	var into := arriving.normalized()
	var out_of := leaving.normalized()
	var turn := into.angle_to(out_of)
	# Nothing to round on a joint that already runs straight through, and a full
	# reversal has no arc to give.
	if turn < deg_to_rad(0.5) or turn > PI - 1e-3:
		return {}

	# Half the shorter segment is as far as the cut can go before it would run
	# into the cut belonging to the next corner along.
	var room := 0.5 * minf(arriving.length(), leaving.length())
	var cut := corner_smoothing * room

	# A corner cannot be turned tighter than the shape going through it is wide.
	# Inside a bend of radius r the inner edge of a sweep reaching `clearance`
	# off the path has only `r - clearance` of arc to lie along, so once the
	# radius drops below that reach the inner edge has NEGATIVE length: it runs
	# backwards, and every slice the corner earned piles up in the same place and
	# folds through itself. That is the crumple on the inside of a tight bend
	# while the outside, which has `r + clearance` to spread over, stays smooth.
	#
	# So the cut is opened out until the arc is at least as wide as the sweep
	# reaches -- but no further than `room`, because running into the next
	# corner's cut is its own kind of broken. A turn between points closer
	# together than the sweep is wide therefore still pinches; there is no arc
	# that fits, and the honest fix for one of those is to move the points apart
	# or narrow the shape.
	var half_turn := tan(turn * 0.5)
	cut = clampf(maxf(cut, clearance * CORNER_CLEARANCE_MARGIN * half_turn), 0.0, room)

	# A cubic matches a circular arc of sweep `turn` when its handles are
	# 4/3 * tan(turn / 4) of the radius, and the radius follows from the cut.
	var radius := cut / half_turn
	var handle := (4.0 / 3.0) * radius * tan(turn * 0.25)
	return {
		"enter": corner - into * cut,
		"enter_handle": into * handle,
		"leave": corner + out_of * cut,
		"leave_handle": -out_of * handle,
		"length": radius * turn,
	}


## Chooses where along the path to put a slice.
##
## Uniform mode spreads [member path_segments] evenly and is the predictable
## option. Adaptive mode walks the path instead and only drops a slice once
## something has moved on far enough to need one: the direction or the banking
## turned by [member max_turn_angle], the cross-section resized by
## [member max_shape_change], or [member max_segment_length] of nothing in
## particular went by. Straight runs come out cheap that way and the slices go
## into the turns, where the shape of the sweep actually depends on them.
func _segment_offsets(from: float, to: float, length: float) -> PackedFloat32Array:
	var offsets := PackedFloat32Array()
	var span := to - from
	if segment_mode == SegmentMode.UNIFORM:
		for i in path_segments + 1:
			offsets.push_back(from + span * float(i) / float(path_segments))
		return offsets

	# How finely the path is inspected. This is also the shortest slice it can
	# produce, and so the real limit on how tight a corner can be measured: a
	# turn of radius r is read to about walk_step / r radians. The total is
	# capped either way, both here and by MAX_ADAPTIVE_SEGMENTS below.
	var walk_step := clampf(span / 2048.0, 0.01, 0.1)
	var turn_limit := deg_to_rad(max_turn_angle)
	# Sampling the profile curves is only worth it when there are any.
	var track_shape := width_profile != null or height_profile != null

	# Everything is measured against the last slice laid down, not against the
	# step before, so a long gentle bend accumulates its way to a slice instead of
	# never quite triggering one.
	# Corners the rounding left alone are a break in direction, not a bend, and
	# no amount of walking either side of one reproduces its tip. Each gets a
	# slice pinned exactly to it.
	var pinned := _sharp_offsets(from, to, walk_step)
	var next_pin := 0

	offsets.push_back(from)
	var anchor := from
	var anchor_forward := _tangent_at(from, length)
	var anchor_up := _slice_up_at(from, anchor_forward)
	var anchor_size := _half_size(from / length) if track_shape else Vector2.ZERO

	var walk := from
	while true:
		walk = minf(walk + walk_step, to)
		if walk >= to:
			break
		# A pinned corner always wins the slice, wherever the walk had got to.
		if next_pin < pinned.size() and walk >= pinned[next_pin]:
			var pin := pinned[next_pin]
			next_pin += 1
			if pin - anchor >= walk_step:
				offsets.push_back(pin)
				anchor = pin
				anchor_forward = _tangent_at(pin, length)
				anchor_up = _slice_up_at(pin, anchor_forward)
				anchor_size = _half_size(pin / length) if track_shape else Vector2.ZERO
				continue
		var travelled := walk - anchor
		if travelled < walk_step:
			continue
		var forward := _tangent_at(walk, length)
		var up := _slice_up_at(walk, forward)
		var size := _half_size(walk / length) if track_shape else Vector2.ZERO
		var turned := 0.0
		if not anchor_forward.is_zero_approx() and not forward.is_zero_approx():
			turned = anchor_forward.angle_to(forward)
		if not anchor_up.is_zero_approx() and not up.is_zero_approx():
			turned = maxf(turned, anchor_up.angle_to(up))
		var resized := maxf(absf(size.x - anchor_size.x), absf(size.y - anchor_size.y))
		if travelled >= max_segment_length or turned >= turn_limit or resized >= max_shape_change:
			offsets.push_back(walk)
			anchor = walk
			anchor_forward = forward
			anchor_up = up
			anchor_size = size

	# Absorb a final sliver into the slice before it rather than leaving a seam a
	# fraction of a millimetre wide.
	var last := offsets.size() - 1
	if last > 0 and to - offsets[last] < walk_step:
		offsets[last] = to
	else:
		offsets.push_back(to)
	offsets = _even_out_tail(offsets)
	offsets = _grade(offsets)
	if offsets.size() - 1 > MAX_ADAPTIVE_SEGMENTS:
		offsets = _thin(offsets, MAX_ADAPTIVE_SEGMENTS)
	return offsets


## Offsets of the corners in the swept path that are still sharp — a break in
## direction rather than a bend. Rounded corners are not among them: they are
## arcs, and the walk resolves an arc perfectly well on its own.
func _sharp_offsets(from: float, to: float, margin: float) -> PackedFloat32Array:
	var found := PackedFloat32Array()
	var count := _swept.point_count
	var closed: bool = _swept.closed if "closed" in _swept else false
	for i in count:
		if not closed and (i == 0 or i == count - 1):
			continue
		var before := (i - 1 + count) % count
		var after := (i + 1) % count
		var position := _swept.get_point_position(i)
		# The in handle points back the way the path arrived, so the arrival
		# direction is its opposite; either handle falls back to the neighbour
		# when it has not been pulled.
		var arriving := -_swept.get_point_in(i)
		if arriving.is_zero_approx():
			arriving = position - _swept.get_point_position(before)
		var leaving := _swept.get_point_out(i)
		if leaving.is_zero_approx():
			leaving = _swept.get_point_position(after) - position
		if arriving.is_zero_approx() or leaving.is_zero_approx():
			continue
		if arriving.angle_to(leaving) < deg_to_rad(0.5):
			continue
		var offset := _swept.get_closest_offset(position)
		if offset > from + margin and offset < to - margin:
			found.push_back(offset)
	found.sort()
	return found


## Evens out the last two slices. The walk lays down full-length ones until the
## path runs out, which leaves a short remainder at the end; grading would then
## split the slice before it to taper into that remainder, spending several
## slices on the end of a straight where nothing is happening. Sharing the two
## evenly costs none and keeps both under [member max_segment_length]. Only the
## run-up matters: a slice placed by a turn is left exactly where the turn put it.
func _even_out_tail(offsets: PackedFloat32Array) -> PackedFloat32Array:
	if offsets.size() < 3:
		return offsets
	var last := offsets.size() - 1
	var tail := offsets[last] - offsets[last - 1]
	var run_up := offsets[last - 1] - offsets[last - 2]
	if tail >= run_up or run_up < max_segment_length * 0.95:
		return offsets
	offsets[last - 1] = offsets[last - 2] + (tail + run_up) * 0.5
	return offsets


## Tapers the step between a long slice and a short one, by halving the long one
## until no slice is more than [constant SEGMENT_GRADING] times its neighbours.
## The turn itself is already sliced finely enough; this is about the run-in to
## it, where the last slice of the straight would otherwise reach well past the
## point the path started bending.
func _grade(offsets: PackedFloat32Array) -> PackedFloat32Array:
	# Each pass halves, so this covers a 256:1 spread between neighbours.
	for pass_index in 8:
		var graded := PackedFloat32Array()
		var split_any := false
		for i in offsets.size() - 1:
			graded.push_back(offsets[i])
			var slice := offsets[i + 1] - offsets[i]
			var shortest_neighbour := slice
			if i > 0:
				shortest_neighbour = minf(shortest_neighbour, offsets[i] - offsets[i - 1])
			if i + 2 < offsets.size():
				shortest_neighbour = minf(shortest_neighbour, offsets[i + 2] - offsets[i + 1])
			if slice > shortest_neighbour * SEGMENT_GRADING:
				graded.push_back(offsets[i] + slice * 0.5)
				split_any = true
		graded.push_back(offsets[offsets.size() - 1])
		offsets = graded
		if not split_any:
			break
	return offsets


## Drops slices evenly across [param offsets] until only [param limit] segments
## remain, keeping both ends. Thinning by position rather than by distance keeps
## the shape of the distribution, so the turns still hold most of the slices.
func _thin(offsets: PackedFloat32Array, limit: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var stride := float(offsets.size() - 1) / float(limit)
	for i in limit:
		out.push_back(offsets[int(float(i) * stride)])
	out.push_back(offsets[offsets.size() - 1])
	return out


## One slice: where the cross-section sits and how it is oriented. Levelled, with
## the curve's own per-point tilt rolled in on top -- which is what makes a
## [Path3D]'s tilt bank the road. See [method _up_at].
func _frame_at(offset: float, length: float, travelled: float, previous: Frame) -> Frame:
	var frame := Frame.new()
	frame.origin = _sample_at(offset, length)
	frame.ratio = offset / length
	frame.distance = travelled

	var forward := _tangent_at(offset, length)
	if forward.is_zero_approx():
		forward = previous.forward if previous else Vector3.FORWARD
	frame.forward = forward

	var up := _up_at(frame.forward, previous)
	up = up.rotated(frame.forward.normalized(), _tilt_at(offset, frame.forward))

	# Project onto the plane of the cross-section; a levelled or carried up
	# vector is only approximately perpendicular to the tangent.
	up -= frame.forward * frame.forward.dot(up)
	if up.length_squared() < 1e-12:
		up = frame.forward.cross(Vector3.RIGHT)
		if up.length_squared() < 1e-12:
			up = frame.forward.cross(Vector3.UP)
	frame.up = up.normalized()
	# Right-handed with X right, Y up, Z back: right = forward x up.
	frame.right = frame.forward.cross(frame.up).normalized()
	return frame


## Which way is up for a slice pointing along [param forward].
##
## LEVELLED, not carried. Taking each slice's up from the one before it is the
## usual way to do this, and it is wrong for a road. A path that turns and climbs
## at the same time accumulates real roll that way -- a few degrees per corner,
## forty over a climbing turn -- so a track nobody tilted arrives at its far end
## visibly banked, with the material's normals rolled off true along with it.
## That roll is honest geometry rather than a mistake: it is the same reason a
## frame walked around a closed loop on a sphere does not come back the way it
## set off. It is simply not what a road does. A road stays level.
##
## So up is world up with the direction of travel taken out of it. Two things are
## still carried from the slice before:
##
##   * Which way up. Level cannot tell the top of a loop from the bottom -- it
##     answers "up" at both -- so a levelled vector that disagrees with the slice
##     before it is flipped, and an inverted stretch stays inverted all the way
##     round rather than snapping back over halfway down.
##   * The frame itself, once the climb is too steep for level to mean anything.
##     Straight up has no level, so near the vertical this hands back to carrying
##     -- easing across rather than switching, so a ramp steepening into a wall
##     does not kink where the two meet.
func _up_at(forward: Vector3, previous: Frame) -> Vector3:
	var carried := previous.up if previous else Vector3.ZERO
	var level := Vector3.UP - forward * forward.dot(Vector3.UP)

	# Straight up or straight down: there is no levelled answer to give.
	if level.length_squared() < 1e-8:
		return carried if carried.length_squared() > 1e-8 else Vector3.BACK

	level = level.normalized()
	if carried.length_squared() < 1e-8:
		return level

	if level.dot(carried) < 0.0:
		level = -level

	return level.lerp(carried, smoothstep(LEVEL_FULL, LEVEL_NONE,
			absf(forward.dot(Vector3.UP))))


## The curve's own tilt at [param offset], as a roll in radians about the
## direction of travel.
##
## Read as the angle BETWEEN the curve's up vector with the tilt applied and the
## same vector without it, rather than off the tilted vector directly. That
## vector carries the curve's own walked frame along with the tilt, and the
## walked frame is exactly the roll [method _up_at] exists to get rid of. The
## difference between the two samples is the tilt on its own, which is the part
## worth keeping.
func _tilt_at(offset: float, forward: Vector3) -> float:
	if not _swept.up_vector_enabled:
		return 0.0

	var plain := _flatten(_swept.sample_baked_up_vector(offset, false), forward)
	var tilted := _flatten(_swept.sample_baked_up_vector(offset, true), forward)
	if plain.is_zero_approx() or tilted.is_zero_approx():
		return 0.0

	var angle := plain.angle_to(tilted)
	return angle if plain.cross(tilted).dot(forward) >= 0.0 else -angle


## [param vector] with everything along [param forward] taken out of it and what
## is left normalised, or zero when nothing was left.
func _flatten(vector: Vector3, forward: Vector3) -> Vector3:
	var flat := vector - forward * forward.dot(vector)
	return flat.normalized() if flat.length_squared() > 1e-10 else Vector3.ZERO


## Where the path is at [param offset], which may lie off either end of it.
##
## Off the end there is nothing left to sample, so the path is continued as a
## straight line along the direction it was travelling when it ran out: the
## sweep grows out of the last point rather than piling up on top of it, which
## is what [member path_start] and [member path_end] mean by overshooting.
##
## The two things a frame needs besides its position take care of themselves.
## [method _tangent_at] holds the end tangent, which is the direction being
## followed here; and the curve's own up vector and the width and height profiles
## are all read through samplers that clamp, so the banking and the cross-section
## carry on unchanged rather than running off the ends of their own curves.
func _sample_at(offset: float, length: float) -> Vector3:
	var on_path := clampf(offset, 0.0, length)
	var point := _swept.sample_baked(on_path, true)
	if is_equal_approx(offset, on_path):
		return point
	return point + _tangent_at(on_path, length) * (offset - on_path)


## Direction of travel at [param offset], measured across a short span either
## side so that a baked point sitting exactly on a corner does not tip the slice
## one way or the other. Past either end of the path it holds the direction that
## end was heading in, which is the line the sweep is extended along.
func _tangent_at(offset: float, length: float) -> Vector3:
	offset = clampf(offset, 0.0, length)
	var probe := clampf(_swept.bake_interval * 0.5, 0.005, 0.25)
	var ahead := _swept.sample_baked(minf(offset + probe, length), true)
	var behind := _swept.sample_baked(maxf(offset - probe, 0.0), true)
	var direction := ahead - behind
	return direction.normalized() if direction.length_squared() > 1e-12 else Vector3.ZERO


## The cross-section's up as the WALK sees it: levelled and tilted, but with no
## slice before it to carry anything from.
##
## The walk has no chain of frames to hand along -- it is deciding where the
## frames go. What it is looking for is a stretch where the shape turns over
## enough to be worth a slice, and levelled-and-tilted answers that: it moves
## when the path turns, and it moves when the tilt does.
func _slice_up_at(offset: float, forward: Vector3) -> Vector3:
	if forward.is_zero_approx():
		return Vector3.ZERO
	return _up_at(forward, null).rotated(forward.normalized(), _tilt_at(offset, forward))


## The furthest any part of the cross-section sits from the path it is swept
## along, over the whole sweep.
##
## This is the radius a corner has to keep clear of -- see [method _corner_arc].
## Sampled rather than solved because the width and height are free curves; the
## corners of the profile box are what is measured, which is exact for a
## RECTANGLE and a shade generous for a CYLINDER, and generous is the safe way
## to be wrong here.
func _profile_reach() -> float:
	var reach := 0.0
	for i in REACH_SAMPLES + 1:
		var half := _half_size(float(i) / float(REACH_SAMPLES))
		reach = maxf(reach, Vector2(
				half.x + absf(profile_offset.x),
				half.y + absf(profile_offset.y)).length())
	return reach


## Half the cross-section's width and height at [param ratio] along the path.
func _half_size(ratio: float) -> Vector2:
	return Vector2(
			maxf(width * _multiplier(width_profile, ratio), MIN_SIZE) * 0.5,
			maxf(height * _multiplier(height_profile, ratio), MIN_SIZE) * 0.5)


## The cross-section as a closed polygon, wound counter-clockwise in the
## (right, up) plane. Every ring has the same point count, so ring N of one frame
## always pairs with ring N of the next.
func _profile_ring(half_w: float, half_h: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if profile == Profile.RECTANGLE:
		points.push_back(Vector2(half_w, -half_h))
		points.push_back(Vector2(half_w, half_h))
		points.push_back(Vector2(-half_w, half_h))
		points.push_back(Vector2(-half_w, -half_h))
	else:
		for i in radial_segments:
			var angle := TAU * float(i) / float(radial_segments)
			points.push_back(Vector2(cos(angle) * half_w, sin(angle) * half_h))
	for i in points.size():
		points[i] += profile_offset
	return points


## Sweeps one ring along the frames. [param flip] turns the surface inside out
## for the inner wall of a hollow shape.
func _add_sides(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		frames: Array[Frame], rings: Array[PackedVector2Array], flip: bool) -> void:
	var count: int = rings[0].size()
	var smooth := shading == Shading.SMOOTH \
			or (shading == Shading.AUTO and profile == Profile.CYLINDER)

	# Per-ring normals and the running perimeter distance used for the U axis.
	var edge_normals: Array[PackedVector2Array] = []
	var point_normals: Array[PackedVector2Array] = []
	var perimeters: Array[PackedFloat32Array] = []
	for ring in rings:
		var edges := _edge_normals(ring)
		edge_normals.append(edges)
		point_normals.append(_point_normals(edges))
		perimeters.append(_perimeter(ring))

	# V runs along the path, which is against the normal-cross-tangent bitangent
	# on the outside of the shape and with it on a flipped inner wall.
	var binormal_sign := 1.0 if flip else -1.0
	for i in frames.size() - 1:
		for k in count:
			var k2 := (k + 1) % count
			var base := verts.size()
			for corner in 4:
				# Corners run (frame i, k), (i, k2), (i + 1, k2), (i + 1, k).
				var fi: int = i if corner < 2 else i + 1
				var leading := corner == 1 or corner == 2
				var pk: int = k2 if leading else k
				var frame := frames[fi]
				var ring := rings[fi]
				var point := ring[pk]
				var flat: Vector2 = point_normals[fi][pk] if smooth else edge_normals[fi][k]
				var normal := frame.right * flat.x + frame.up * flat.y
				var edge := ring[k2] - ring[k]
				var tangent := (frame.right * edge.x + frame.up * edge.y).normalized()
				# The closing edge ends where the profile began, so its far corner
				# takes the appended full perimeter rather than wrapping U to zero.
				var u_index := count if leading and k2 == 0 else pk
				_push_vertex(verts, normals, tangents, uvs,
						frame.origin + frame.right * point.x + frame.up * point.y,
						-normal if flip else normal,
						-tangent if flip else tangent, binormal_sign,
						Vector2(perimeters[fi][u_index], frame.distance))
			if flip:
				indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			else:
				indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Fills one end of a solid sweep with a triangle fan from the profile's centre.
func _add_solid_cap(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		frame: Frame, ring: PackedVector2Array, at_end: bool) -> void:
	var count := ring.size()
	var normal := frame.forward if at_end else -frame.forward
	var centre := Vector2.ZERO
	for point in ring:
		centre += point
	centre /= float(count)

	var base := verts.size()
	# V runs down the profile's up axis, which puts the binormal along the
	# surface normal's cross product on one end and against it on the other.
	var binormal_sign := 1.0 if at_end else -1.0
	_push_vertex(verts, normals, tangents, uvs,
			frame.origin + frame.right * centre.x + frame.up * centre.y,
			normal, frame.right, binormal_sign, Vector2(centre.x, -centre.y))
	for point in ring:
		_push_vertex(verts, normals, tangents, uvs,
				frame.origin + frame.right * point.x + frame.up * point.y,
				normal, frame.right, binormal_sign, Vector2(point.x, -point.y))
	for k in count:
		var k2 := (k + 1) % count
		if at_end:
			indices.append_array([base, base + 1 + k, base + 1 + k2])
		else:
			indices.append_array([base, base + 1 + k2, base + 1 + k])


## Fills one end of a hollow sweep with the ring between the outer and inner
## profiles, leaving the bore open.
func _add_ring_cap(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		frame: Frame, outer: PackedVector2Array, inner: PackedVector2Array, at_end: bool) -> void:
	var count := outer.size()
	var normal := frame.forward if at_end else -frame.forward
	var binormal_sign := 1.0 if at_end else -1.0
	for k in count:
		var k2 := (k + 1) % count
		var base := verts.size()
		var quad: Array[Vector2] = [outer[k], inner[k], inner[k2], outer[k2]]
		if at_end:
			quad = [outer[k], outer[k2], inner[k2], inner[k]]
		for point in quad:
			_push_vertex(verts, normals, tangents, uvs,
					frame.origin + frame.right * point.x + frame.up * point.y,
					normal, frame.right, binormal_sign, Vector2(point.x, -point.y))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Outward normal of each edge of a counter-clockwise profile.
func _edge_normals(ring: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := ring.size()
	for k in count:
		var edge := ring[(k + 1) % count] - ring[k]
		var normal := Vector2(edge.y, -edge.x)
		out.push_back(normal.normalized() if normal.length_squared() > 1e-12 else Vector2.RIGHT)
	return out


## Averages the two edges meeting at each point, for smooth shading.
func _point_normals(edges: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := edges.size()
	for k in count:
		var normal := edges[(k - 1 + count) % count] + edges[k]
		out.push_back(normal.normalized() if normal.length_squared() > 1e-12 else edges[k])
	return out


## Distance around the profile to each point, with the closing edge appended so
## the seam gets a full-width U instead of wrapping back to zero.
func _perimeter(ring: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := ring.size()
	var travelled := 0.0
	for k in count:
		out.push_back(travelled)
		travelled += ring[(k + 1) % count].distance_to(ring[k])
	out.push_back(travelled)
	return out


func _push_vertex(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array,
		position: Vector3, normal: Vector3, tangent: Vector3, binormal_sign: float,
		uv: Vector2) -> void:
	verts.push_back(position)
	normals.push_back(normal)
	uvs.push_back(uv)
	tangents.push_back(tangent.x)
	tangents.push_back(tangent.y)
	tangents.push_back(tangent.z)
	tangents.push_back(binormal_sign)


## Reads a shaping curve at [param ratio] along the path. The curve's own domain
## is mapped onto the path, so leaving it at 0..1 means fractions and setting it
## to 0..length means metres.
func _multiplier(shape: Curve, ratio: float) -> float:
	if shape == null:
		return 1.0
	var low := 0.0
	var high := 1.0
	if "min_domain" in shape:
		low = shape.min_domain
		high = shape.max_domain
	return maxf(shape.sample_baked(lerpf(low, high, ratio)), 0.0)


func _watch(resource: Resource) -> void:
	if resource and not resource.changed.is_connected(_on_shape_changed):
		resource.changed.connect(_on_shape_changed)


func _unwatch(resource: Resource) -> void:
	if resource and resource.changed.is_connected(_on_shape_changed):
		resource.changed.disconnect(_on_shape_changed)


func _on_shape_changed() -> void:
	request_update()


## A [PrimitiveMesh] has to hand back at least one vertex, so an unusable curve
## produces a single collapsed triangle: no surface to draw, nothing for CSG to
## intersect, and no error spam while the path is still being drawn.
func _placeholder_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	return arrays
