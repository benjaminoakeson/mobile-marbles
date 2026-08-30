@tool
class_name CSGPathExtrude3D
extends CSGMesh3D
## A CSG road or tunnel swept along a [Path3D], wrapping [PathExtrudeMesh].
##
## Add it as a child of a [Path3D] and it picks the parent up automatically, so
## the shape follows the path you drag with the normal path gizmo. Point
## [member path_node] somewhere else to share one path between several sweeps,
## or leave both empty and fill in [member curve] to keep the points on this node.
##
## [member width_profile] and [member height_profile] are [Curve] resources that
## multiply the size along the way: a point at 0.5 with value 2.0 doubles the
## width halfway along, a point with value 0.4 pinches it. Raise the curve's Max
## Value before adding points above 1.0, which it otherwise clamps.
## [member path_start] and [member path_end] shorten the sweep without editing
## the path's points, and taken past 0 and 1 they lengthen it instead, running
## straight on from whichever end they overshoot.
##
## Points dropped with the path gizmo make hard corners, so the sweep shapes the
## path first: [member cornering] decides whether it is carried through the
## points on one smooth curve or run straight between them with the corners
## rounded, and [member corner_smoothing] how strongly, as a share of the segments
## meeting at each one, and 0 runs the path straight through every point. Slices
## are then placed where the shape needs them, so straight runs stay cheap and
## bends get whatever [member max_turn_angle] asks for. [member segment_count]
## reports what that came to.
##
## For a tunnel there are two ways round: switch [member profile] to CYLINDER and
## turn on [member hollow] to build the tunnel's walls as a solid you can drive
## through, or leave it solid and set [member operation] to Subtraction to bore
## the sweep out of a hill inside a [CSGCombiner3D].

var _extrude: PathExtrudeMesh = PathExtrudeMesh.new()
var _refresh_queued := false
# What the rebuild is currently listening to. Kept so it can still be
# disconnected after a reparent, when _path() no longer finds the old one.
var _bound_path: Path3D = null
var _bound_curve: Curve3D = null

## The path to sweep along. Falls back to this node's [Path3D] parent when empty.
@export var path_node: Path3D = null:
	set(value):
		if path_node == value:
			return
		_unbind()
		path_node = value
		_bind()
		_queue_refresh()

## Used only when there is no [member path_node] and no [Path3D] parent.
@export var curve: Curve3D = null:
	set(value):
		if curve == value:
			return
		_unbind()
		curve = value
		_bind()
		_queue_refresh()

@export var profile: PathExtrudeMesh.Profile = PathExtrudeMesh.Profile.RECTANGLE:
	set(value):
		profile = value
		_extrude.profile = value
		notify_property_list_changed()

## Full width of the cross-section, before [member width_profile] is applied.
@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var width: float = 4.0:
	set(value):
		width = maxf(value, PathExtrudeMesh.MIN_SIZE)
		_extrude.width = width

## Full height of the cross-section, before [member height_profile] is applied.
@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var height: float = 0.5:
	set(value):
		height = maxf(value, PathExtrudeMesh.MIN_SIZE)
		_extrude.height = height

## Sides around a CYLINDER profile.
@export_range(3, 128, 1)
var radial_segments: int = 24:
	set(value):
		radial_segments = maxi(value, 3)
		_extrude.radial_segments = radial_segments

## How the path gets from one point to the next.
##
## SPLINE carries it through every point on one smooth curve, leaning into each
## turn before it arrives and out of it after it leaves. FILLET runs it dead
## straight between the points and rounds off the corners, which keeps the
## straights straight but packs all the turning into the bends -- that is what
## makes a path read as turning on a dime.
@export var cornering := PathExtrudeMesh.Cornering.SPLINE:
	set(value):
		cornering = value
		_extrude.cornering = value

## How much of that shaping to apply, from none to all of it.
##
## Under SPLINE it is tension: 0 runs straight from point to point, 1 is the full
## curve. Under FILLET it is how far back into each segment the corner is cut, as
## a fraction of the shorter of the two meeting there.
##
## Either way it is proportional rather than a fixed radius, so it follows how
## you placed the points: two far apart bend gently, two close together bend
## hard. And either way 0 runs the path straight through every point. This is a
## different thing from [member max_turn_angle], which decides how finely a bend
## is sliced once its shape is settled, not what that shape is.
##
## A point whose handles you have pulled out in the path gizmo is already shaped
## by hand and is left exactly as it is, under both.
@export_range(0.0, 1.0, 0.01)
var corner_smoothing: float = 1.0:
	set(value):
		corner_smoothing = clampf(value, 0.0, 1.0)
		_extrude.corner_smoothing = corner_smoothing

## How slices are spread along the path. [code]ADAPTIVE[/code] spends them where
## the shape actually bends and leaves straight runs cheap; [code]UNIFORM[/code]
## ignores the shape and lays down [member path_segments] of them.
@export var segment_mode: PathExtrudeMesh.SegmentMode = PathExtrudeMesh.SegmentMode.ADAPTIVE:
	set(value):
		segment_mode = value
		_extrude.segment_mode = value
		notify_property_list_changed()

## Slices along the whole path, in [code]UNIFORM[/code] mode only.
@export_range(1, 1024, 1, "or_greater")
var path_segments: int = 32:
	set(value):
		path_segments = maxi(value, 1)
		_extrude.path_segments = path_segments

## How far apart slices may get where nothing is happening — the straight runs'
## budget. Raise it to stop long straights costing geometry.
@export_range(0.05, 50.0, 0.01, "or_greater", "suffix:m")
var max_segment_length: float = 8.0:
	set(value):
		max_segment_length = maxf(value, 0.05)
		_extrude.max_segment_length = max_segment_length

## How far the path may turn between one slice and the next: the knob for how
## smooth the turns are. At 5 degrees a right-angle bend gets 18 slices and a
## full loop 72, however long the bend is.
## Banking from a [Path3D]'s point tilt counts as turning too. Below about 3
## degrees the curve's own [member Curve3D.bake_interval] — 0.2 m by default —
## becomes the limit on how precisely a tight bend can be measured; lower it on
## the [Curve3D] if you need to go finer than that.
@export_range(0.5, 90.0, 0.1, "suffix:°")
var max_turn_angle: float = 5.0:
	set(value):
		max_turn_angle = clampf(value, 0.5, 90.0)
		_extrude.max_turn_angle = max_turn_angle

## How much the cross-section may resize between slices, so a
## [member width_profile] that flares halfway down a straight still gets the
## slices to show it.
@export_range(0.005, 10.0, 0.005, "or_greater", "suffix:m")
var max_shape_change: float = 0.25:
	set(value):
		max_shape_change = maxf(value, 0.005)
		_extrude.max_shape_change = max_shape_change

## Slices the last rebuild produced, for weighing detail against cost. It
## reports a finished build, so it reads zero until the sweep has been built
## once.
@export var segment_count: int = 0:
	get:
		return _extrude.segment_count

## Multiplies [member width] along the path, from its start (0) to its end (1).
## A [Curve] only allows values from 0 to 1 until you raise its Max Value, so
## widen that first or anything above 1.0 is clamped away.
@export var width_profile: Curve = null:
	set(value):
		width_profile = value
		_extrude.width_profile = value

## Multiplies [member height] along the path, like [member width_profile].
@export var height_profile: Curve = null:
	set(value):
		height_profile = value
		_extrude.height_profile = value

## Shifts the cross-section sideways and vertically off the path. Set Y to
## [code]-height / 2[/code] to hang a road's surface on the path line.
@export var profile_offset: Vector2 = Vector2.ZERO:
	set(value):
		profile_offset = value
		_extrude.profile_offset = value

## Where along the path the sweep starts, as a fraction of its length. Below 0
## it runs on past the start instead, up to [constant PathExtrudeMesh.PATH_OVERSHOOT]
## of the path's length, carrying straight on in the direction the path set off in.
@export_range(-0.15, 1.15, 0.0001)
var path_start: float = 0.0:
	set(value):
		path_start = clampf(value, -PathExtrudeMesh.PATH_OVERSHOOT,
				1.0 + PathExtrudeMesh.PATH_OVERSHOOT)
		_extrude.path_start = path_start

## Where along the path the sweep stops. Above 1 it runs on past the end the same
## way [member path_start] does below 0.
@export_range(-0.15, 1.15, 0.0001)
var path_end: float = 1.0:
	set(value):
		path_end = clampf(value, -PathExtrudeMesh.PATH_OVERSHOOT,
				1.0 + PathExtrudeMesh.PATH_OVERSHOOT)
		_extrude.path_end = path_end

## Carves the inside out, leaving walls [member wall_thickness] thick: a tunnel
## from a CYLINDER, a covered corridor from a RECTANGLE.
@export var hollow: bool = false:
	set(value):
		hollow = value
		_extrude.hollow = value
		notify_property_list_changed()

@export_range(0.001, 10.0, 0.001, "or_greater", "suffix:m")
var wall_thickness: float = 0.25:
	set(value):
		wall_thickness = maxf(value, PathExtrudeMesh.MIN_SIZE)
		_extrude.wall_thickness = wall_thickness

## Closes both ends of the sweep. Turning it off leaves an open shell, which is
## no longer watertight for CSG booleans.
@export var end_caps: bool = true:
	set(value):
		end_caps = value
		_extrude.end_caps = value

@export var shading: PathExtrudeMesh.Shading = PathExtrudeMesh.Shading.AUTO:
	set(value):
		shading = value
		_extrude.shading = value


func _init() -> void:
	mesh = _extrude
	# Moving either node changes where the path sits relative to this one, and
	# the sweep is built in local space. Only worth tracking while editing.
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE, NOTIFICATION_PARENTED:
			_bind()
			_queue_refresh()
		NOTIFICATION_UNPARENTED:
			_bind()
			_queue_refresh()
		NOTIFICATION_TRANSFORM_CHANGED:
			_queue_refresh()


func _validate_property(property: Dictionary) -> void:
	# The mesh is owned by this node; showing or saving it would just let it
	# drift out of sync with the exported shape.
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_NONE
	elif property.name == "curve" and _path() != null:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "radial_segments" and profile != PathExtrudeMesh.Profile.CYLINDER:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "wall_thickness" and not hollow:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "path_segments" \
			and segment_mode != PathExtrudeMesh.SegmentMode.UNIFORM:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name in ["max_segment_length", "max_turn_angle", "max_shape_change"] \
			and segment_mode != PathExtrudeMesh.SegmentMode.ADAPTIVE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "segment_count":
		# Reported, not set: shown in the inspector but never written to disk.
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


## The path actually in use: an explicit one first, then a [Path3D] parent.
func _path() -> Path3D:
	if is_instance_valid(path_node):
		return path_node
	return get_parent() as Path3D


## Editing a path fires several notifications in a row — a point moved, the node
## transformed, the tree entered — so rebuilds are collapsed into one per frame.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	var path := _path()
	var source: Curve3D = path.curve if path else curve
	if source == null:
		_extrude.curve = null
		return
	# Curve points are in the path's space; the mesh is built in this node's.
	var to_local := Transform3D.IDENTITY
	if path and is_inside_tree() and path.is_inside_tree():
		to_local = global_transform.affine_inverse() * path.global_transform
	if to_local.is_equal_approx(Transform3D.IDENTITY):
		_extrude.curve = source
	else:
		_extrude.curve = _transformed(source, to_local)


## A copy of [param source] moved into this node's space. Needed when the path
## is not this node's parent, or sits at an offset from it.
func _transformed(source: Curve3D, xform: Transform3D) -> Curve3D:
	var out := Curve3D.new()
	out.bake_interval = source.bake_interval
	out.up_vector_enabled = source.up_vector_enabled
	if "closed" in source:
		out.closed = source.closed
	for i in source.point_count:
		out.add_point(
				xform * source.get_point_position(i),
				xform.basis * source.get_point_in(i),
				xform.basis * source.get_point_out(i))
		out.set_point_tilt(i, source.get_point_tilt(i))
	return out


## Listens to whichever source the sweep is reading, so dragging a path point
## or swapping a curve rebuilds the mesh.
func _bind() -> void:
	var path := _path()
	var source: Curve3D = null if path else curve
	if path == _bound_path and source == _bound_curve:
		return
	_unbind()
	if path:
		path.curve_changed.connect(_queue_refresh)
		_bound_path = path
	elif source:
		source.changed.connect(_queue_refresh)
		_bound_curve = source


func _unbind() -> void:
	if is_instance_valid(_bound_path) and _bound_path.curve_changed.is_connected(_queue_refresh):
		_bound_path.curve_changed.disconnect(_queue_refresh)
	if is_instance_valid(_bound_curve) and _bound_curve.changed.is_connected(_queue_refresh):
		_bound_curve.changed.disconnect(_queue_refresh)
	_bound_path = null
	_bound_curve = null
