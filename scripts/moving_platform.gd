@tool
class_name MovingPlatform
extends AnimatableBody3D

## Anything in a level that moves: lifts, ferries, turntables, fan blades,
## revolving doors, spinners, patrolling platforms.
##
## To use one: put an [AnimatableBody3D] under the level body, give it this
## script, and pick a [member travel] and a [member spin]. Nothing else is
## required, and the inspector only shows the settings the modes you picked
## actually read. The two are independent -- a platform can ride a rail while
## spinning on the spot -- and either can be left at NONE.
##
## Everything is measured against the LEVEL, not the world. The level is what
## moves in this game: it swings about the ball and slides bodily through the
## world as it tilts, and a part that read its own motion in world space would
## think it was hurtling along while sitting perfectly still on a tilting floor.
##
## [b]The four traps this exists to keep anyone from stepping in again:[/b]
##
## 1. `sync_to_physics` has to be OFF. A nested AnimatableBody3D with it on stops
##    inheriting its parent and drifts out of the level the moment it tilts.
##    Forced off here rather than left to each scene to get right.
##
## 2. With it off, the body no longer drags riders along -- that was the job
##    `sync_to_physics` was doing. The surface velocity has to be handed to the
##    solver instead, which this works out from the motion itself. See
##    [member carries_riders].
##
## 3. The motion has to be CONTINUOUS. The level's placement is a rotation about
##    the ball, so a body that jumps by d lurches through roughly d * 2sin(θ/2)
##    of world space in one frame and bats the ball away. Nothing here ever
##    teleports: sweeps and shuttles turn round at their ends, a rail is joined
##    at the point nearest to wherever the platform was placed rather than at its
##    head, and the one thing left that could jump -- looping an open rail end to
##    end -- warns in the inspector before it ever runs.
##
## 4. Where two platforms meet, the SEAM bounces the ball. Jolt takes the edges
##    out of a surface built from several shapes of ONE body, and cannot do it
##    for one built from several BODIES -- the leading edge of the next platform
##    is a real edge of a real body, so the solver catches the ball on it and
##    throws it. Across seventeen platforms laid end to end that costs the ball
##    more than a third of its speed and hops it six centimetres into the air:
##    a row of speed bumps down what is meant to be a smooth run.
##
##    Nothing here can merge the bodies -- moving independently is the whole
##    point of them -- and Jolt's enhanced internal edge removal, which is on,
##    does not help: it takes out edges that are geometrically INTERNAL, and
##    two bodies moved on their own are never perfectly flush, so the next
##    platform's edge is a real step of a fraction of a millimetre and is
##    rightly left in.
##
##    What does tell a seam from a real bounce is the speed the ball comes in
##    with. The hop is restitution reflecting the ball off the edge's tilted
##    normal, and the ball's speed ALONG that normal is a few percent of its
##    rolling speed -- a metre or two a second flat out -- where a ball dropped
##    onto a platform or struck by a spinner arrives at five to fifteen. So the
##    project's `physics/jolt_physics_3d/simulation/bounce_velocity_threshold`
##    is raised from its default of 1.0: below it Jolt pays no restitution at
##    all. One engine setting, the same for every body in the game, and a
##    platform is left as bare as any other surface.
##
##    This used to be answered by dressing the platform in an `absorbent`
##    material that cancelled the ball's own bounce -- which cost every honest
##    bounce a platform should give, and made a lone spinner the one thing in a
##    level the ball could not bounce off. Nothing wears a material now.
##
## Nothing moves during the opening camera shot. A level has to open the same way
## every time, and a platform turning behind the fly-round means the level the
## player is handed depends on how long they watched it -- see [method _hold].
##
## This replaced three scripts -- a base, a spinner and a path follower -- that
## between them said all of the above once and then made you pick which of them
## a platform was allowed to be.

## How the platform gets about.
enum Travel {
	NONE, ## Stays where it was placed.
	SHUTTLE, ## Out to an offset and back, over and over. Lifts, ferries.
	PATH, ## Rides a [Path3D]. Longer routes, corners, anything drawn.
}

## How the platform turns.
enum Spin {
	NONE, ## Keeps the facing it was placed with.
	CONTINUOUS, ## Round and round without stopping.
	STEPPED, ## Holds still, turns a set amount, holds again.
	SWEEP, ## Runs between two angles and back, over and over.
	CURVE, ## Speed read off a drawn curve, looped over a set time.
}

## Whether it moves at all. Off leaves the platform exactly where it was placed,
## which is how a rail or a spinner is temporarily taken out of a level without
## unpicking its settings.
@export var motion_enabled := true

## Whether the surface drags the ball along with it.
##
## On for anything meant to carry the player -- lifts, ferries, turntables. Off
## for something meant to knock the ball about rather than take it anywhere: a
## fan blade or a spinning hazard that grips is a ball flung off at a speed
## nobody asked for.
@export var carries_riders := false

@export_group("Travel")

@export var travel := Travel.NONE:
	set(value):
		travel = value
		# The inspector only shows the settings the chosen modes read, and it has
		# to be told the list changed to notice.
		notify_property_list_changed()
		update_configuration_warnings()

## How fast it travels, in metres a second.
##
## Under PATH the sign still runs the rail backwards, but [member invert_path]
## says that better and is the one to reach for. Under SHUTTLE the sign does
## nothing -- the platform goes out and comes back either way -- and with
## [member travel_ease] on this is the AVERAGE, since an eased leg starts slow,
## runs about half as fast again through the middle, and slows to a stop.
@export var travel_speed := 2.0

@export_subgroup("Shuttle")

## How far out from where it was placed, and in which direction.
##
## Measured in the space the platform is placed in, so on a level lying flat
## `(0, 3, 0)` is a lift that rises three metres and `(0, 0, -8)` is a ferry that
## runs eight metres out and back. The placed spot is one END of the run, never
## the middle.
@export var travel_offset := Vector3(0.0, 3.0, 0.0)

## How long it rests at each end, in seconds. It starts on one of these, so a
## platform drops into a level already waiting rather than already moving.
@export var travel_pause := 0.0

## Whether it eases away from each end and back down into the next one, rather
## than setting off and stopping at full speed.
##
## On is what a lift looks like. Off is what a conveyor looks like.
@export var travel_ease := true

@export_subgroup("Path")

## The rail to ride: a [Path3D], ideally a sibling under the same level so the
## rail tilts with everything else. The platform is moved along the curve every
## frame, so it does not need to be a child of the path.
##
## Draw the rail through wherever the platform already is. It sets off from the
## point on the rail nearest to where you placed it -- not from the head of the
## curve -- so a platform put in the middle of its run stays there until it is
## time to move, and one drawn a little off the rail keeps that offset the whole
## way round. See [method _settle_onto_rail].
@export var path_node: NodePath:
	set(value):
		path_node = value
		update_configuration_warnings()

## Set off along the rail the other way.
##
## The same journey run backwards, and nothing else about it changes: the
## platform still settles onto the rail at the point nearest to where it was
## placed, still turns round at the far end, still loops if it is told to. Only
## which way it leaves is different.
##
## This is what a negative [member travel_speed] has always done, and the two
## COMPOSE -- a negative speed with this ticked sets off forwards again. Reach
## for this one. A speed is how fast, not which way, and a rail of platforms told
## apart by which of them carries a minus sign is a rail nobody can read at a
## glance.
##
## Read once, when the level loads. Turning it over mid-level would be arguing
## with the platform about which way it is already going; to send one back early,
## move the end of its rail.
@export var invert_path := false

## Run round and round instead of back and forth.
##
## Only for a CLOSED curve. Looping an open one teleports the platform from the
## end back to the start, which is trap 3 above, so it is off by default and the
## inspector says so if you turn it on over an open rail.
@export var path_loop := false:
	set(value):
		path_loop = value
		update_configuration_warnings()

## Turn to face along the rail as well as follow it.
@export var face_along_path := false

@export_group("Spin")

@export var spin := Spin.NONE:
	set(value):
		spin = value
		notify_property_list_changed()
		update_configuration_warnings()

## Degrees a second.
##
## Under CONTINUOUS this is the whole behaviour, and negative spins the other
## way. Under STEPPED and SWEEP it is only how fast the platform travels while it
## is actually turning -- where it goes is [member step_degrees] or the sweep
## angles, and the sign here is ignored. CURVE ignores it entirely; the curve
## carries its own speeds.
@export var spin_degrees := 45.0

## Axis to spin about, in the platform's own space. UP spins it flat, like a
## turntable; FORWARD or RIGHT stand it up like a wheel.
@export var spin_axis := Vector3.UP:
	set(value):
		spin_axis = value
		update_configuration_warnings()

@export_subgroup("Stepped")

## How far one step turns, in degrees. Negative steps the other way.
##
## Nothing here requires it to divide into a full turn -- 90 gives the usual
## four-position turntable, but 120 gives three and 45 gives eight, and an
## amount that does not divide evenly simply keeps walking round.
@export var step_degrees := 90.0

## How long the platform sits still between steps, in seconds. It starts on one
## of these, so it drops into a level already waiting rather than already moving.
@export var step_pause := 3.0

@export_subgroup("Sweep")

## Angle the sweep starts from, in degrees, measured from however the platform
## was placed in the level. Zero is the orientation you authored.
@export var sweep_start_degrees := -45.0

## Angle the sweep runs to before turning back, in degrees.
##
## Which of the two angles is larger does not matter; the platform travels
## between them either way. What the order decides is where it sets off from, so
## a pair of doors given mirrored starts open away from each other.
@export var sweep_end_degrees := 45.0:
	set(value):
		sweep_end_degrees = value
		update_configuration_warnings()

@export_subgroup("Curve")

## Speed over time, in degrees a second, looped forever.
##
## The graph is set up from [member curve_duration] and [member curve_max_speed]
## so you can draw straight onto it: seconds left to right across the whole
## loop, speed bottom to top from full reverse through nothing to full forward.
## A curve sitting on the middle line is a platform standing still; one that
## crosses it is a platform reversing, and how smoothly it crosses is how
## smoothly it slows, stops and comes back.
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

## Set while the opening camera shot is still running, and cleared for good when
## the level is handed to the player. See [method _hold].
var _held := false

# --- Where it was placed ---
## The level this hangs off, and the placement everything is measured from.
var _level: Node3D
var _rest_position := Vector3.ZERO
var _rest_basis := Basis()

## The placement measured against the level last frame, which is what the rider
## velocity is worked out from.
var _last_in_level := Transform3D()

# --- Travel ---
## How far along the shuttle's run it is, from 0 at the placed end to 1 at the
## offset end, along with which way it is going and what is left of its rest.
var _shuttle_at := 0.0
var _shuttle_direction := 1.0
var _shuttle_wait := 0.0

## Metres along the rail, and which way round it is going.
var _path: Path3D
var _distance := 0.0
var _path_direction := 1.0

## How far the platform sits off the rail, in the rail's own space. Carried along
## the whole journey, so the curve says how the platform moves and the placement
## says where. See [method _settle_onto_rail].
var _rail_offset := Vector3.ZERO

# --- Spin ---
## How far round it has turned, in radians.
var _angle := 0.0

## The orientation the spin is measured from: how the platform was placed, or --
## on a rail it is facing along -- wherever that rail points this frame.
var _base_basis := Basis()

## How much of the current step is left to turn, in radians. Zero means the
## platform is sitting between steps.
var _remaining := 0.0

## Seconds left of sitting still between steps.
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

	# Trap 1.
	sync_to_physics = false

	# Trap 4 is answered by the project's restitution threshold, not here -- see
	# the note at the top. A platform is left as bare as any other surface, so it
	# bounces the ball exactly as the rest of the level does.

	_level = _find_level()
	if _level == null:
		push_warning("%s: no level body above it; motion will be measured in world space" % name)

	_rest_position = position
	_rest_basis = basis
	_base_basis = basis
	_last_in_level = _transform_in_level()

	# Which way it leaves. Kept as the direction rather than folded into the
	# speed, so a platform sent the other way still reads as running at the speed
	# it says it runs at -- and so the turn at the end of the rail, which is this
	# flipping, goes on meaning the one thing.
	_path_direction = -1.0 if invert_path else 1.0

	_path = get_node_or_null(path_node) as Path3D
	if travel == Travel.PATH:
		if _path == null or _path.curve == null:
			push_warning("%s: no Path3D with a curve at '%s'; it will sit still" % [name, path_node])
		else:
			_settle_onto_rail()

	# Both of the modes that rest at their ends start ON a rest, so a platform
	# that has only just loaded is never already lunging at the player.
	_shuttle_wait = travel_pause
	_waiting = step_pause
	_sweep_phase = 0.0 if sweep_start_degrees <= sweep_end_degrees else _sweep_span()

	_hold()


## Holds the platform still until the level is the player's, which is the end of
## the camera's opening shot -- or the next frame, on a level with no opening
## shot to wait for.
##
## A level has to open the same way every time. The fly-round takes as long as it
## takes and the player skips it whenever they like, so a platform left running
## behind it hands out a different level to everyone: a turntable a third of the
## way round, a lift halfway up, a gap that was open a moment ago. The ball is
## frozen through the shot for the same reason -- see `player.gd` -- and this is
## the same handshake, asked rather than assumed so a platform added to a level
## already under way moves at once instead of being frozen for good.
##
## Nothing is counting down in the meantime. The rests between steps, the pause
## at the end of a shuttle's run and the clock the curve is read against all only
## tick inside [method _advance], so a long fly-round does not eat into the first
## move a player sees.
func _hold() -> void:
	if GameState.is_timing_started():
		return

	_held = true
	GameState.timing_started.connect(_release, CONNECT_ONE_SHOT)


## The level is the player's now, and so is everything moving in it.
func _release() -> void:
	_held = false


## Lets the platform move with no level under way -- for the menu's preview,
## which shows a level frozen but wants the parts of it that move to be seen
## moving. Undoes [method _hold]: the wait for the level to start is dropped,
## because on the menu that start never comes.
func preview() -> void:
	if GameState.timing_started.is_connected(_release):
		GameState.timing_started.disconnect(_release)
	_held = false


func _physics_process(delta: float) -> void:
	if motion_enabled and not _held:
		_advance(delta)

	var now := _transform_in_level()
	if carries_riders:
		_publish_surface_velocity(now, delta)
	else:
		constant_linear_velocity = Vector3.ZERO
		constant_angular_velocity = Vector3.ZERO

	_last_in_level = now


## One frame of movement: where it has got to, and which way it is now facing.
##
## Travel first, because a rail the platform is facing along decides the facing
## that the spin is then measured from -- the two stack rather than fight, so a
## platform can ride a route and turn on the spot at the same time.
func _advance(delta: float) -> void:
	match travel:
		Travel.SHUTTLE:
			position = _rest_position + travel_offset * _shuttle_along(delta)
		Travel.PATH:
			_follow_path(delta)

	if spin != Spin.NONE:
		basis = _base_basis * Basis(_axis(), _spin_angle(delta))
	elif travel == Travel.PATH and face_along_path:
		basis = _base_basis


# --- Travel ---

## How far along its run the shuttle is, from 0 at the placed end to 1 at the
## far end.
##
## Turning round is what makes this continuous: the platform is at the end of its
## run whichever way it is about to go, so reversing moves it nowhere. It is also
## why the run is not wrapped -- coming back is the whole point of a shuttle, and
## a wrap would fling it back to the near end through everything in between.
func _shuttle_along(delta: float) -> float:
	var span := travel_offset.length()
	if span <= 0.0 or is_zero_approx(travel_speed):
		return _eased(_shuttle_at)

	if _shuttle_wait > 0.0:
		_shuttle_wait -= delta
		if _shuttle_wait > 0.0:
			return _eased(_shuttle_at)

		# The rest ran out part way through this frame, and what is left of the
		# frame belongs to the journey.
		delta = -_shuttle_wait
		_shuttle_wait = 0.0

	_shuttle_at += absf(travel_speed) / span * delta * _shuttle_direction

	# Stopped exactly on the end it was going to, rather than wherever the frame
	# happened to land. The sliver of travel that costs is a fraction of one
	# frame, and it is paid back the moment it sets off again.
	if _shuttle_at >= 1.0 or _shuttle_at <= 0.0:
		_shuttle_at = clampf(_shuttle_at, 0.0, 1.0)
		_shuttle_direction = -_shuttle_direction
		_shuttle_wait = travel_pause

	return _eased(_shuttle_at)


## The ease applied to a shuttle's position -- slow away from an end, slow back
## into the next one. Straight through when it is turned off.
func _eased(along: float) -> float:
	return smoothstep(0.0, 1.0, along) if travel_ease else along


## Where on the rail the platform was placed, and how far off it -- read once, on
## the frame the level loads.
##
## A rail is drawn around a platform that is already in the level, and where it
## was put is where it is wanted: in front of the player, in the middle of its
## run rather than at one end of it. So the curve is read as the SHAPE of the
## journey rather than as the place. The platform sets off from the point on the
## rail nearest to where it was placed, and carries whatever offset it had from
## the rail along the whole route.
##
## The upshot is that a platform never moves on the frame the level loads. That
## matters beyond tidiness: the ball can be sitting on this platform at the
## spawn, and a platform that jumps to the head of the curve is trap 3 happening
## before the player has touched anything.
##
## Which way it sets off is [member invert_path], so a platform placed mid-rail
## runs forward first and a ticked box sends it the other way. A negative
## [member travel_speed] does the same thing and composes with it.
func _settle_onto_rail() -> void:
	var placed := _path.to_local(global_position)

	_distance = _path.curve.get_closest_offset(placed)
	_rail_offset = placed - _path.curve.sample_baked(_distance)


## Puts the platform where the rail says, and -- if it is facing along the rail
## -- works out the orientation the spin will be measured from.
##
## The rail is read in GLOBAL space, because it is very often a sibling rather
## than a parent; the facing is converted back into the platform's own parent's
## space, so a platform nested under another moving part still lands right.
func _follow_path(delta: float) -> void:
	if _path == null or _path.curve == null:
		return

	var length := _path.curve.get_baked_length()
	if length <= 0.0:
		return

	_distance += travel_speed * _path_direction * delta

	if path_loop:
		_distance = fposmod(_distance, length)
	else:
		# Turn around at the ends. Reversing is continuous -- the platform is at
		# the end of the rail either way -- where wrapping round would not be.
		if _distance > length:
			_distance = length - (_distance - length)
			_path_direction = -_path_direction
		elif _distance < 0.0:
			_distance = -_distance
			_path_direction = -_path_direction

	var on_rail := _path.curve.sample_baked(_distance)
	global_position = _path.global_transform * (on_rail + _rail_offset)

	if not face_along_path:
		return

	var ahead_at := fposmod(_distance + 0.25 * signf(travel_speed * _path_direction), length)
	var forward := _path.global_transform.basis * (_path.curve.sample_baked(ahead_at) - on_rail)
	if forward.length_squared() > 0.0001:
		_base_basis = _parent_basis().inverse() * Basis.looking_at(forward, _up())


# --- Spin ---

## How far round the platform has turned by now, in radians.
##
## SWEEP works out an angle rather than a turn, because it is pinned between two
## ends and an accumulated angle would creep off them. The rest add a turn to
## where they already are, and wrap at a full turn to keep the number small --
## not a jump, since a full turn and none at all are the same orientation.
func _spin_angle(delta: float) -> float:
	match spin:
		Spin.SWEEP:
			_angle = _sweep_angle(delta)
		Spin.STEPPED:
			_angle = wrapf(_angle + _stepped_turn(delta), 0.0, TAU)
		Spin.CURVE:
			_angle = wrapf(_angle + _curve_turn(delta), 0.0, TAU)
		_:
			_angle = wrapf(_angle + deg_to_rad(spin_degrees) * delta, 0.0, TAU)

	return _angle


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
		# travel every time, and a platform set to turn exactly ninety degrees
		# drifts a little further behind true with every step it takes.
		delta = -_waiting
		_waiting = 0.0
		_remaining = absf(step)

	# Never past the end of the step, so the platform comes to rest on the angle
	# it was told to and not wherever the frame happened to land.
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
## span so short the platform would cross it several times in one frame still
## comes out somewhere sensible rather than rattling.
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


## The axis to turn about, never zero -- a zero axis is not a rotation, and
## building a basis out of one is an error a level should not be able to cause.
func _axis() -> Vector3:
	return spin_axis.normalized() if not spin_axis.is_zero_approx() else Vector3.UP


# --- Riders, and the level everything is measured against ---

## Tells the solver how fast this surface is travelling, so friction can drag a
## ball along with it.
##
## Measured against the level and then turned into world directions, so what a
## rider is told is the platform's own travel and not the level's.
func _publish_surface_velocity(now: Transform3D, delta: float) -> void:
	if delta <= 0.0:
		return

	var to_world := _level.global_transform.basis if _level != null else Basis()

	constant_linear_velocity = to_world * ((now.origin - _last_in_level.origin) / delta)

	var turn := Quaternion(now.basis.orthonormalized()) \
			* Quaternion(_last_in_level.basis.orthonormalized()).inverse()
	if turn.w < 0.0:
		turn = -turn  # same rotation, shortest way round

	var angle := turn.get_angle()
	if angle < 0.000001:
		constant_angular_velocity = Vector3.ZERO
	else:
		constant_angular_velocity = to_world * (turn.get_axis() * (angle / delta))


## This platform's placement measured against the level, so a level that is moved
## or animated does not read as the platform moving.
func _transform_in_level() -> Transform3D:
	if _level == null:
		return global_transform
	return _level.global_transform.affine_inverse() * global_transform


func _find_level() -> Node3D:
	var node := get_parent()
	while node != null:
		if node.has_method("rest_transform"):
			return node as Node3D
		node = node.get_parent()
	return null


## The level's up, so a platform facing along a rail stays upright relative to
## the track rather than to the world.
func _up() -> Vector3:
	return _level.global_transform.basis.y if _level != null else Vector3.UP


## Whatever this platform is hung off, so a facing worked out in world space can
## be handed back as the local orientation that produces it.
func _parent_basis() -> Basis:
	var parent := get_parent() as Node3D
	return parent.global_transform.basis.orthonormalized() if parent != null else Basis()


# --- The inspector ---

## Points the curve's graph at the time and speed this platform actually uses, so
## what you draw in the inspector is read in the units it is drawn in: seconds
## across, degrees a second up, no rescaling in between.
func _apply_curve_ranges() -> void:
	if speed_curve == null:
		return

	speed_curve.min_domain = 0.0
	speed_curve.max_domain = maxf(curve_duration, 0.01)
	speed_curve.min_value = -curve_max_speed
	speed_curve.max_value = curve_max_speed


## Only the settings the chosen modes read are worth showing; the rest are kept
## -- so switching modes back does not lose them -- but hidden.
##
## This is most of what makes the script easy to use. One script covering every
## kind of moving platform has a lot of settings on it, and a level designer
## should never have to work out which twelve of them the mode they picked
## quietly ignores.
func _validate_property(property: Dictionary) -> void:
	var travel_owner: Variant = {
		"travel_offset": Travel.SHUTTLE,
		"travel_pause": Travel.SHUTTLE,
		"travel_ease": Travel.SHUTTLE,
		"path_node": Travel.PATH,
		"invert_path": Travel.PATH,
		"path_loop": Travel.PATH,
		"face_along_path": Travel.PATH,
	}.get(property.name)

	var spin_owner: Variant = {
		"step_degrees": Spin.STEPPED,
		"step_pause": Spin.STEPPED,
		"sweep_start_degrees": Spin.SWEEP,
		"sweep_end_degrees": Spin.SWEEP,
		"speed_curve": Spin.CURVE,
		"curve_duration": Spin.CURVE,
		"curve_max_speed": Spin.CURVE,
	}.get(property.name)

	var hidden: bool = (travel_owner != null and travel_owner != travel) \
			or (spin_owner != null and spin_owner != spin) \
			or (property.name == "travel_speed" and travel == Travel.NONE) \
			or (property.name == "spin_axis" and spin == Spin.NONE) \
			or (property.name == "spin_degrees" and spin in [Spin.NONE, Spin.CURVE])

	if hidden:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()

	if travel == Travel.PATH:
		var path := get_node_or_null(path_node) as Path3D
		if path == null or path.curve == null:
			warnings.append("Path travel needs a Path3D with a curve; without one it will sit still.")
		elif path_loop and not _is_curve_closed(path.curve):
			warnings.append("Looping an open curve teleports the platform end to end, which swats the ball. Close the curve, or turn Path Loop off to run back and forth.")

	if travel == Travel.SHUTTLE and travel_offset.is_zero_approx():
		warnings.append("Travel Offset is zero, so the shuttle has nowhere to go.")

	if spin != Spin.NONE and spin_axis.is_zero_approx():
		warnings.append("Spin Axis is zero. Pick an axis -- UP for a turntable, FORWARD or RIGHT for a wheel.")
	if spin == Spin.CURVE and speed_curve == null:
		warnings.append("Curve spin needs a Speed Curve; without one the platform stands still.")
	if spin == Spin.SWEEP and is_zero_approx(_sweep_span()):
		warnings.append("Sweep start and end are the same angle, so the platform will not move.")

	return warnings


func _is_curve_closed(curve: Curve3D) -> bool:
	if curve.point_count < 2:
		return true

	var gap := curve.get_point_position(0) \
			.distance_to(curve.get_point_position(curve.point_count - 1))
	return gap < 0.1
