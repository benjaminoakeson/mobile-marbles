class_name PathPart
extends MovingPart

## Rides a Path3D. Lifts, ferries, patrolling platforms.
##
## Put the Path3D under the level as well, so the rail tilts with everything
## else. The part is placed on the curve every frame, so it does not need to be
## a child of the path -- keep it a sibling and aim `path_node` at the rail.

## The rail to ride. A Path3D, ideally a sibling under the level.
@export var path_node: NodePath

## Metres a second along the curve. Negative runs it backwards.
@export var speed := 2.0

## Run back and forth instead of round and round. Required for an open curve --
## looping one teleports the part from the end back to the start, which breaks
## rule 3 and swats the ball. Closed curves can loop freely.
@export var ping_pong := true

## Turn to face along the rail as well as follow it.
@export var face_along_path := false

var _path: Path3D
var _distance := 0.0
var _direction := 1.0


func _ready() -> void:
	super()

	_path = get_node_or_null(path_node) as Path3D
	if _path == null or _path.curve == null:
		push_warning("%s: no Path3D with a curve at '%s'; it will sit still" % [name, path_node])
		return

	if not ping_pong and not _is_curve_closed():
		push_warning("%s: looping an open curve teleports it end to end. Close the curve, or turn on ping_pong." % name)


func _advance(delta: float) -> void:
	if _path == null or _path.curve == null:
		return

	var length := _path.curve.get_baked_length()
	if length <= 0.0:
		return

	_distance += speed * _direction * delta

	if ping_pong:
		# Turn around at the ends. Reversing is continuous -- the part is at the
		# end of the rail either way -- where wrapping round would not be.
		if _distance > length:
			_distance = length - (_distance - length)
			_direction = -_direction
		elif _distance < 0.0:
			_distance = -_distance
			_direction = -_direction
	else:
		_distance = fposmod(_distance, length)

	var here := _path.global_transform * _path.curve.sample_baked(_distance)

	if face_along_path:
		var ahead_at := fposmod(_distance + 0.25 * signf(speed * _direction), length)
		var forward := (_path.global_transform * _path.curve.sample_baked(ahead_at)) - here
		if forward.length_squared() > 0.0001:
			global_transform = Transform3D(Basis.looking_at(forward, _up()), here)
			return

	global_position = here


## The level's up, so a facing part stays upright relative to the track rather
## than to the world.
func _up() -> Vector3:
	return _level.global_transform.basis.y if _level != null else Vector3.UP


func _is_curve_closed() -> bool:
	var curve := _path.curve
	if curve.point_count < 2:
		return true
	var gap := curve.get_point_position(0).distance_to(curve.get_point_position(curve.point_count - 1))
	return gap < 0.1
