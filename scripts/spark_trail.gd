class_name SparkTrail
extends LevelParticles

## Sparks struck off the floor where the ball is rolling, thrown out behind it.
##
## It is meant to say speed, and only speed. Below [member quiet_speed] there is
## nothing at all -- a ball creeping about is not grinding on anything -- and
## from there it comes up to full at [member full_speed], which is where the
## spray is widest, fastest and thickest.
##
## Sits under the ball and is aimed by hand every tick rather than simply hanging
## off it, for two reasons: sparks come off the floor rather than the middle of
## the ball, and the ball spins hard enough that anything parented to it would
## sling its own sparks around.
##
## The floor is found with a short ray straight down. That is deliberate rather
## than a shortcut past the contacts the ball already reports: a ball pressed
## against a wall is touching something, but the sparks want the ground.
##
## The sparks themselves are stored in the level's frame -- see [LevelParticles].

## The ball has to be moving this fast before any sparks show at all.
@export var quiet_speed := 5.0

## And this fast for the full effect. Between the two it comes up smoothly, so
## there is no line the player can cross and see the sparks switch on.
@export var full_speed := 12.0

## How far below the ball's underside the floor may be and still count. Small: a
## ball this far off the ground is airborne, and airborne balls strike nothing.
@export var floor_reach := 0.12

## Which layers count as ground. The stage, by default.
@export_flags_3d_physics var floor_layers := 1

@export_group("Throw")

## How far the spray is tipped off straight-back towards straight-up. All the way
## back and it hugs the floor and is hidden by the ball; all the way up and it is
## a fountain rather than a wake. Kept low, because a spark thrown flat and then
## pulled down by the burst's own gravity is the arc the effect is built on.
@export_range(0.0, 1.0) var lean := 0.28

## What the sparks are thrown at, slowest to fastest. Scaled between the two by
## how fast the ball is going.
@export var slow_throw := 2.2
@export var fast_throw := 6.5

## And how long they are drawn over the same range.
@export var slow_spark := 0.45
@export var fast_spark := 1.0

var _ball: RigidBody3D
var _radius := 0.5


func _ready() -> void:
	_ball = get_parent() as RigidBody3D
	if _ball == null:
		push_warning("%s: expected to hang off the ball; no sparks will be struck" % name)
		set_physics_process(false)
		return

	_radius = _measure_ball()
	_bind_to_level()


func _physics_process(_delta: float) -> void:
	if _ball == null:
		return

	var speed := _ball.linear_velocity.length()
	var effort := clampf((speed - quiet_speed) / maxf(full_speed - quiet_speed, 0.01), 0.0, 1.0)
	if effort <= 0.0 or _ball.freeze:
		emitting = false
		return

	var ground := _ground_under()
	if ground.is_empty():
		emitting = false
		return

	_aim(ground["position"], _throw_direction(ground["normal"]))

	# `amount_ratio` thins the spray without rebuilding it. Setting `amount`
	# itself would reallocate the whole system, every tick, forever.
	amount_ratio = effort
	_burst.initial_velocity_min = lerpf(slow_throw, fast_throw, effort)
	_burst.initial_velocity_max = _burst.initial_velocity_min * 1.9
	_burst.scale_min = lerpf(slow_spark, fast_spark, effort) * 0.55
	_burst.scale_max = lerpf(slow_spark, fast_spark, effort) * 1.15
	emitting = true


## Where the floor is under the ball, or nothing if it is off the ground.
func _ground_under() -> Dictionary:
	var from := _ball.global_position
	var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * (_radius + floor_reach))
	query.collision_mask = floor_layers
	query.exclude = [_ball.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Which way a spark leaves the ball: back along the ball's own travel, leaned
## off the floor so the spray clears the ball instead of hiding behind it. Off
## the ground normal rather than off world up, so a spark struck on a slope still
## comes away from the slope.
func _throw_direction(ground_normal: Vector3) -> Vector3:
	var travel := _ball.linear_velocity
	var back := -travel.normalized() if travel.length_squared() > 0.0001 else ground_normal
	var away := ground_normal.normalized()
	var thrown := back.lerp(away, lean)
	if thrown.length_squared() < 0.0001:
		thrown = away
	return thrown.normalized()


## How far the ball reaches, read off its own collider so a marble built at
## another size still strikes its sparks off the floor rather than the air.
func _measure_ball() -> float:
	for child in _ball.get_children():
		var collider := child as CollisionShape3D
		if collider == null:
			continue
		var sphere := collider.shape as SphereShape3D
		if sphere != null:
			return sphere.radius * collider.global_transform.basis.get_scale().y
	return 0.5
