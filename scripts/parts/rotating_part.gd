class_name RotatingPart
extends MovingPart

## Spins in place. Turntables, fan blades, revolving doors -- and, stepped,
## the kind of thing that holds still, snaps round a quarter turn, and holds
## again while you decide whether to risk it.

## How the part turns.
enum Spin {
	CONTINUOUS, ## Round and round without stopping.
	STEPPED, ## Holds still, turns a set amount, holds again.
}

@export var spin := Spin.CONTINUOUS

## Degrees a second.
##
## Under CONTINUOUS this is the whole behaviour, and negative spins the other
## way. Under STEPPED it is only how fast the part travels while it is actually
## turning -- how far it goes and which way are [member step_degrees], and the
## sign here is ignored.
@export var spin_degrees := 45.0

## Axis to spin about, in the part's own space. UP spins it flat, like a
## turntable; FORWARD or RIGHT stand it up like a wheel.
@export var spin_axis := Vector3.UP

@export_group("Stepped")

## How far one step turns, in degrees. Negative steps the other way.
##
## Nothing here requires it to divide into a full turn -- 90 gives the usual
## four-position turntable, but 120 gives three and 45 gives eight, and an
## amount that does not divide evenly simply keeps walking round.
@export var step_degrees := 90.0

## How long the part sits still between steps, in seconds. It starts on one of
## these, so a part drops into a level already waiting rather than already
## moving.
@export var step_pause := 3.0

var _angle := 0.0
var _rest_basis := Basis()

## How much of the current step is left to turn, in radians. Zero means the part
## is sitting between steps.
var _remaining := 0.0

## Seconds left of sitting still.
var _waiting := 0.0


func _ready() -> void:
	super()
	_rest_basis = basis
	# Starts by waiting, not by turning: a part that lurches the instant the
	# level loads has already used up its warning.
	_waiting = step_pause


func _advance(delta: float) -> void:
	if spin_axis.is_zero_approx():
		return

	var turn := _stepped_turn(delta) if spin == Spin.STEPPED else deg_to_rad(spin_degrees) * delta

	# Rebuilt from an angle rather than nudged each frame: composing rotations
	# forever skews the basis, and a skewed collider is a bad time. Wrapping at a
	# full turn keeps the number small, and is not a jump -- a full turn and none
	# at all are the same orientation.
	_angle = wrapf(_angle + turn, 0.0, TAU)
	basis = _rest_basis * Basis(spin_axis.normalized(), _angle)


## How far to turn this frame while stepping, in radians, sign and all.
##
## The turn is tracked as an amount REMAINING rather than as an angle to arrive
## at, because `_angle` is wrapped at a full turn and a target on the far side of
## that wrap is a nasty thing to compare against. Remaining has no such seam, and
## it is what makes the last frame of a step land exactly on the step rather than
## a fraction past it.
func _stepped_turn(delta: float) -> float:
	var step := deg_to_rad(step_degrees)
	var rate := absf(deg_to_rad(spin_degrees))
	if is_zero_approx(step) or rate <= 0.0:
		return 0.0

	if _remaining <= 0.0:
		_waiting -= delta
		if _waiting > 0.0:
			return 0.0

		# The wait ran out part way through this frame, and what is left of the
		# frame belongs to the turn. Without this a step loses up to a frame of
		# travel every time, and a part set to turn exactly ninety degrees drifts
		# a little further behind true with every step it takes.
		delta = -_waiting
		_waiting = 0.0
		_remaining = absf(step)

	# Never past the end of the step, so the part comes to rest on the angle it
	# was told to and not wherever the frame happened to land.
	var turn := minf(rate * delta, _remaining)
	_remaining -= turn

	if _remaining <= 0.0:
		_waiting = step_pause

	return turn * signf(step)
