@tool
class_name RotatingPart
extends MovingPart

## Spins in place. Turntables, fan blades, revolving doors -- and, stepped,
## the kind of thing that holds still, snaps round a quarter turn, and holds
## again while you decide whether to risk it.

## How the part turns.
enum Spin {
	CONTINUOUS, ## Round and round without stopping.
	STEPPED, ## Holds still, turns a set amount, holds again.
	SWEEP, ## Runs between two angles and back, over and over.
	CURVE, ## Speed read off a drawn curve, looped over a set time.
}

@export var spin := Spin.CONTINUOUS:
	set(value):
		spin = value
		# The inspector only shows the settings the chosen mode actually reads,
		# and it has to be told the list changed to notice.
		notify_property_list_changed()
		update_configuration_warnings()

## Degrees a second.
##
## Under CONTINUOUS this is the whole behaviour, and negative spins the other
## way. Under STEPPED and SWEEP it is only how fast the part travels while it is
## actually turning -- where it goes is [member step_degrees] or the sweep
## angles, and the sign here is ignored. CURVE ignores it entirely; the curve
## carries its own speeds.
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

@export_group("Sweep")

## Angle the sweep starts from, in degrees, measured from however the part was
## placed in the level. Zero is the orientation you authored.
@export var sweep_start_degrees := -45.0

## Angle the sweep runs to before turning back, in degrees.
##
## Which of the two angles is larger does not matter; the part travels between
## them either way. What the order decides is where it sets off from, so a pair
## of doors given mirrored starts open away from each other.
@export var sweep_end_degrees := 45.0

@export_group("Curve")

## Speed over time, in degrees a second, looped forever.
##
## The graph is set up from [member curve_duration] and [member curve_max_speed]
## so you can draw straight onto it: seconds left to right across the whole
## loop, speed bottom to top from full reverse through nothing to full forward.
## A curve sitting on the middle line is a part standing still; one that crosses
## it is a part reversing, and how smoothly it crosses is how smoothly it slows,
## stops and comes back.
@export var speed_curve: Curve:
	set(value):
		speed_curve = value
		_apply_curve_ranges()
		update_configuration_warnings()

## How long one pass of the curve takes, in seconds -- the width of the graph.
## When it runs out the curve starts again from the left.
@export_range(0.1, 60.0, 0.1, "or_greater", "suffix:s") var curve_duration := 10.0:
	set(value):
		curve_duration = maxf(value, 0.01)
		_apply_curve_ranges()

## Fastest the curve can ask for, in degrees a second -- the height of the
## graph, running from this at the top down through zero to its negative at the
## bottom.
##
## Lowering it squashes a curve you have already drawn, since points that no
## longer fit are clamped rather than scaled. Set it before drawing.
@export_range(1.0, 720.0, 1.0, "or_greater", "suffix:deg/s") var curve_max_speed := 180.0:
	set(value):
		curve_max_speed = maxf(absf(value), 0.01)
		_apply_curve_ranges()

var _angle := 0.0
var _rest_basis := Basis()

## How much of the current step is left to turn, in radians. Zero means the part
## is sitting between steps.
var _remaining := 0.0

## Seconds left of sitting still.
var _waiting := 0.0

## How far round the there-and-back the sweep has travelled, in radians. Runs
## from zero to twice the span and then starts over.
var _sweep_phase := 0.0

## Seconds into the current pass of the curve.
var _curve_time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		# The editor only wants the graph kept in step with its settings. Nothing
		# here should move, and nothing should be written into the saved scene.
		set_physics_process(false)
		_apply_curve_ranges()
		return

	super()
	_rest_basis = basis
	# Starts by waiting, not by turning: a part that lurches the instant the
	# level loads has already used up its warning.
	_waiting = step_pause
	_sweep_phase = 0.0 if sweep_start_degrees <= sweep_end_degrees else _sweep_span()


func _advance(delta: float) -> void:
	if spin_axis.is_zero_approx():
		return

	# SWEEP works out an angle rather than a turn, because it is pinned between
	# two ends and an accumulated angle would creep off them. The rest add a turn
	# to where they already are, and wrap at a full turn to keep the number
	# small -- not a jump, since a full turn and none at all are the same
	# orientation.
	match spin:
		Spin.SWEEP:
			_angle = _sweep_angle(delta)
		Spin.STEPPED:
			_angle = wrapf(_angle + _stepped_turn(delta), 0.0, TAU)
		Spin.CURVE:
			_angle = wrapf(_angle + _curve_turn(delta), 0.0, TAU)
		_:
			_angle = wrapf(_angle + deg_to_rad(spin_degrees) * delta, 0.0, TAU)

	# Rebuilt from an angle rather than nudged each frame: composing rotations
	# forever skews the basis, and a skewed collider is a bad time.
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


## Where the sweep has got to this frame, in radians.
##
## Distance travelled is carried instead of a direction that gets flipped at the
## ends, and the angle is folded out of it: run far enough and you are on the way
## back, run twice the span and you are where you started. Turning round costs
## nothing and lands exactly on the end angle, however long the frame was, and a
## span so short the part would cross it several times in one frame still comes
## out somewhere sensible rather than rattling.
func _sweep_angle(delta: float) -> float:
	var span := _sweep_span()
	var rate := absf(deg_to_rad(spin_degrees))
	if span <= 0.0 or rate <= 0.0:
		return deg_to_rad(sweep_start_degrees)

	_sweep_phase = fposmod(_sweep_phase + rate * delta, span * 2.0)
	return deg_to_rad(minf(sweep_start_degrees, sweep_end_degrees)) \
			+ span - absf(span - _sweep_phase)


## The angle between the two sweep ends, in radians.
func _sweep_span() -> float:
	return absf(deg_to_rad(sweep_end_degrees - sweep_start_degrees))


## How far to turn this frame at the speed the curve asks for, in radians.
##
## The clock is wrapped, not the sample point, so the curve genuinely repeats
## every `curve_duration` seconds no matter how long it is left running.
func _curve_turn(delta: float) -> float:
	if speed_curve == null or curve_duration <= 0.0:
		return 0.0

	_curve_time = fposmod(_curve_time + delta, curve_duration)
	return deg_to_rad(speed_curve.sample_baked(_curve_time)) * delta


## Points the curve's graph at the time and speed this part actually uses, so
## what you draw in the inspector is read in the units it is drawn in: seconds
## across, degrees a second up, no rescaling in between.
func _apply_curve_ranges() -> void:
	if speed_curve == null:
		return

	speed_curve.min_domain = 0.0
	speed_curve.max_domain = maxf(curve_duration, 0.01)
	speed_curve.min_value = -curve_max_speed
	speed_curve.max_value = curve_max_speed


## Only the settings the chosen mode reads are worth showing; the rest are kept
## -- so switching modes back does not lose them -- but hidden.
func _validate_property(property: Dictionary) -> void:
	var owner_mode: Variant = {
		"step_degrees": Spin.STEPPED,
		"step_pause": Spin.STEPPED,
		"sweep_start_degrees": Spin.SWEEP,
		"sweep_end_degrees": Spin.SWEEP,
		"speed_curve": Spin.CURVE,
		"curve_duration": Spin.CURVE,
		"curve_max_speed": Spin.CURVE,
	}.get(property.name)

	var hidden: bool = (owner_mode != null and owner_mode != spin) \
			or (property.name == "spin_degrees" and spin == Spin.CURVE)

	if hidden:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	if spin == Spin.CURVE and speed_curve == null:
		warnings.append("Curve spin needs a Speed Curve; without one the part stands still.")
	if spin == Spin.SWEEP and is_zero_approx(_sweep_span()):
		warnings.append("Sweep start and end are the same angle, so the part will not move.")

	return warnings
