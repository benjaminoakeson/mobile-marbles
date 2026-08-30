class_name ImpactBurst
extends LevelParticles

## Glass shards thrown off the ball when it takes a heavy blow.
##
## Hangs off the ball and reads it, so a level does not have to wire anything up
## -- dropping the player scene in is enough.
##
## What counts as heavy is the impulse the solver actually put through the
## contact, in newton-seconds, not how fast the ball happens to be going. That is
## the difference between a hit and a journey: a ball tearing along a wall at
## full pelt is asking nothing of it and gets nothing back, while the same ball
## dropped onto a floor from a height is stopped hard and shatters. The same
## measure, and roughly the same numbers, as [member DestructibleSurface.break_impulse].
##
## The shards are stored in the level's frame -- see [LevelParticles].

## The blow the ball has to take before any shards fly, in newton-seconds.
##
## Measured off the real ball at the gravity and bounce the game actually plays
## at -- five kilos and half a bounce, which works out at about 7.5 times the
## speed a square hit closes at:
##
##     sitting on the floor, or rolling along it ..   2
##     hopping over the bumps in an ordinary run ..  40
##     running into a wall at 6 m/s ...............  45
##     dropped onto the floor from one metre ......  57
##     dropped onto the floor from four metres .... 115
##
## The first three of those are metered off a real run down a level; the drops
## agree with the arithmetic to within a newton-second. The default sits above
## the bumps an ordinary run is full of, so shards mean a hit the player watched
## coming rather than a track being bumpy.
@export var heavy_impulse := 55.0

## The blow that earns the full burst. Between the two it comes up smoothly, so
## a hit a shade over the threshold throws a few shards rather than the lot.
@export var full_impulse := 130.0

## How long before another burst can be thrown. One landing reports a flurry of
## contacts over several ticks, and without this each one gets its own burst.
@export var quiet_gap := 0.15

@export_group("Throw")

## What the shards are thrown at, for the lightest blow that counts and for the
## hardest.
@export var soft_throw := 2.4
@export var hard_throw := 6.0

## How wide the spray opens out, in degrees, over the same range. A light knock
## coughs a tight puff off the surface; a hard one throws shards everywhere.
@export var soft_spread := 42.0
@export var hard_spread := 78.0

var _ball: RigidBody3D
var _since_burst := 0.0


func _ready() -> void:
	_ball = get_parent() as RigidBody3D
	if _ball == null:
		push_warning("%s: expected to hang off the ball; no shards will fly" % name)
		set_physics_process(false)
		return

	_bind_to_level()


func _physics_process(delta: float) -> void:
	_since_burst += delta
	if _ball == null or _ball.freeze or _since_burst < quiet_gap:
		return

	var blow := _hardest_contact()
	if blow.is_empty() or blow["impulse"] < heavy_impulse:
		return

	_throw(blow)


## The hardest of the contacts the ball is currently in, or nothing when it is
## touching nothing.
##
## Read off the physics server rather than through a `body_entered` signal,
## because a signal says only that something was touched -- this needs to know
## how hard, and where. Needs `contact_monitor` on the ball with room for a
## contact, which `player.tscn` sets.
##
## Only the hardest contact counts. A ball landing in a corner reports two or
## three at once and they are all the same landing; bursting once for each would
## triple the shards for no reason the player can see.
func _hardest_contact() -> Dictionary:
	var state := PhysicsServer3D.body_get_direct_state(_ball.get_rid())
	if state == null:
		return {}

	var hardest := {}
	var worst := 0.0
	for i in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length()
		if impulse <= worst:
			continue
		worst = impulse
		hardest = {
			"impulse": impulse,
			"point": state.get_contact_local_position(i),
			"normal": state.get_contact_local_normal(i),
		}
	return hardest


## One burst, off the surface that was struck, as big as the blow was hard.
func _throw(blow: Dictionary) -> void:
	_since_burst = 0.0

	var force := clampf(
			(blow["impulse"] - heavy_impulse) / maxf(full_impulse - heavy_impulse, 0.01),
			0.0, 1.0)

	_aim(blow["point"], _away_from_surface(blow["point"], blow["normal"]))

	amount_ratio = lerpf(0.45, 1.0, force)
	_burst.spread = lerpf(soft_spread, hard_spread, force)
	_burst.initial_velocity_min = lerpf(soft_throw, hard_throw, force)
	_burst.initial_velocity_max = _burst.initial_velocity_min * 2.1

	# One shot, so this is what fires it. A restart cuts short any shards still
	# in the air, which is the right answer to a second heavy hit -- the newer
	# one is the one the player is watching -- but it is also why `quiet_gap`
	# exists: without it the flurry of contacts from a single landing would each
	# cut the one before, and the burst would never get off the ground.
	restart()


## The contact normal, turned to point out of the surface towards the ball.
##
## Taken off the ball's own position rather than trusted to come that way round.
## Which side of a contact the reported normal faces depends on which body the
## state belongs to and which way the shapes met, and a burst fired into the
## floor is a burst nobody sees.
func _away_from_surface(point: Vector3, normal: Vector3) -> Vector3:
	var out := normal.normalized()
	if out.length_squared() < 0.0001:
		return Vector3.UP
	return out if out.dot(_ball.global_position - point) >= 0.0 else -out
