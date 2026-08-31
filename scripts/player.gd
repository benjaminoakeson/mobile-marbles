class_name Player
extends RigidBody3D

## The ball: what holds it still before the level starts, and what lets the
## player stop it once it has.
##
## Every level authors the ball half a metre above its floor, so play opens with
## it dropping onto the stage. Where the ground under the spawn is not perfectly
## flat -- and on several levels it is not -- the landing turns into a bounce and
## then a slow creep downhill, all of it before a finger has touched the screen.
## That is free ground, and free gems, on a clock that has not started yet.
##
## So the ball is pinned the instant it first touches down, and let go again by
## the very input that starts the clock. The drop still happens; it is only the
## landing that is made dead.
##
## STEERING, meanwhile, is not done here at all -- [GravityTilt] leans the whole
## space's gravity and the ball simply falls the way it is pushed. What IS done
## here is the other half of driving: grip and the brake. Left to gravity alone
## the ball can only be pulled up as hard as it can be pushed along, because both
## are the same lean, so a ball that took two seconds to wind up took two seconds
## to put down; and a marble carries a third of its speed in SPIN, which friction
## feeds straight back into the floor the moment the rolling is broken, so the
## little braking there was came back. Both are answered below, and neither costs
## the ball any of its top end: nothing here slows a ball going the way it is
## being asked to go.

## Cleared once the ball has been released, so a later bounce cannot pin it all
## over again mid-level.
var _waiting := true

## How hard the ball can be dragged sideways out of a slide, in metres a second
## squared at full stick.
##
## This is the turning. A marble under gravity alone keeps every bit of the speed
## it built up in the direction it built it up in, and steering only adds to that
## sideways, so a fast ball answers the stick in a long curve. Cutting the part
## of its motion that is across the stick turns that curve into a corner, and the
## faster it is going the more there is to cut.
@export var grip := 26.0

## How hard the ball can be hauled up when the stick is pushed AGAINST the way it
## is going, in metres a second squared at full stick.
##
## Roughly twice what the lean can push with, which is the whole point: winding
## the ball up stays a commitment, putting it down stops being one. It is kept
## near what the floor could really hold a ball with -- friction on level ground
## is worth about `g` -- so hard braking reads as the tyre biting rather than as
## the ball hitting an invisible wall.
@export var brake := 34.0

## And what a stick let go of takes off it, in metres a second squared.
##
## Deliberately slight. Letting go is not a brake -- the brake is asking for the
## other way -- but a ball that coasts for ever is a ball the player has stopped
## steering and cannot park.
@export var coast_brake := 4.0

@onready var _mesh: MeshInstance3D = $PlayerCollider/PlayerMesh

## Needed to turn a change in speed into the change in SPIN that goes with it,
## below. Read off the shape rather than written down twice.
@onready var _radius: float = ($PlayerCollider.shape as SphereShape3D).radius

## What the stick is steering, found on first use rather than in [method _ready].
## The ball is authored above the level in every level scene, so it is readied
## first, and the level has not joined its group yet by the time we are.
var _level: GravityTilt

## Cleared once the ball stops being the player's to drive -- see
## [method stop_driving].
var _driving := true


func _ready() -> void:
	GameState.timing_started.connect(_release)
	_wear_chosen_skin()


## Puts the player's chosen marble on the ball.
##
## Done here rather than authored into the scene so every level picks the skin up
## without knowing anything about it. The material in `player.tscn` is the one
## that shows in the editor and stands in if the catalogue cannot supply one.
func _wear_chosen_skin() -> void:
	var skin_material := MarbleSkins.material_for(GameState.marble_skin)
	if skin_material != null:
		_mesh.material_override = skin_material


func _physics_process(_delta: float) -> void:
	if not _waiting or freeze:
		return

	# Pinned on first contact rather than at load: freezing it before the drop
	# would leave the ball hanging in mid-air over the stage until the player
	# moved, which reads as a bug rather than as a start.
	#
	# Needs `contact_monitor` with room for a contact, which player.tscn sets.
	if get_contact_count() > 0:
		_pin()


## Kills the landing outright. The velocities go first: freezing keeps whatever
## the body was carrying, and it would be handed straight back on release.
func _pin() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true


func _release() -> void:
	_waiting = false
	freeze = false
	_driving = true


## Takes the player's hands off the ball for good, leaving it to whatever is
## finishing the level with it.
##
## The goal sends the ball out the far side to coast down under its own drag, and
## grip and the brake would both be pulling on it the whole way -- an assist with
## nobody behind it, parking a run that is meant to be seen out.
func stop_driving() -> void:
	_driving = false


## Grip and the brake, applied where the ball is actually touching the level.
##
## Both are worked as changes to the velocity rather than as forces, because both
## have a hard end: the most either may take is the part of the motion it is
## aimed at, and a force cannot promise that at a low frame rate -- it overshoots
## and drives the ball backwards. Capped this way the brake can be set as fiercely
## as it likes and the worst it can ever do is stop the ball dead.
##
## Nothing here is applied in the air. A ball off a jump has nothing to push
## against, and letting the player brake against thin air would cost the levels
## every arc they are built around.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _waiting or freeze or not _driving:
		return

	if _level == null:
		_level = get_tree().get_first_node_in_group("level_body") as GravityTilt
		if _level == null:
			return

	var normal := _ground_normal(state)
	if normal == Vector3.ZERO:
		return

	# Scaled by what the surface would give a real tyre, so ice stays ice. The
	# whole of this is the floor gripping the ball, and a floor that cannot grip
	# it should not be able to.
	var traction := _traction(state)
	if traction < 0.01:
		return

	# Only the part of the motion that is along the floor is anyone's to take:
	# the rest is the ball dropping onto it or lifting off it.
	var velocity := state.linear_velocity
	var rolling := velocity - normal * velocity.dot(normal)

	var steer := _level.steer_direction()
	var amount := steer.length()
	var change := Vector3.ZERO

	if amount > 0.001:
		# Along the floor, so the stick means the same on a bank as on the flat.
		var heading := steer - normal * steer.dot(normal)
		if heading.length() > 0.001:
			heading = heading.normalized()

			var along := rolling.dot(heading)
			change -= (rolling - heading * along).limit_length(
					grip * amount * traction * state.step)

			# Held against the way the ball is going. Note the lean is ALREADY
			# pulling it back the other way -- this is on top of that, and it is
			# what makes stopping quicker than starting.
			if along < 0.0:
				change += heading * minf(
						-along, brake * amount * traction * state.step)
	else:
		change -= rolling.limit_length(coast_brake * traction * state.step)

	if change.is_zero_approx():
		return

	state.linear_velocity = velocity + change

	# The spin has to come off with the speed. A rolling marble keeps two
	# sevenths of its energy turning, and if the speed alone is taken the contact
	# starts slipping and friction spends that spin putting the speed back --
	# about a third of what was just braked off, handed straight back. Turning
	# the ball down by exactly the amount that keeps it rolling is what makes the
	# brake bite instead of squirm.
	state.angular_velocity += normal.cross(change) / _radius


## Which way the floor is pushing back, averaged over everything the ball is
## touching, or nothing at all if it is touching nothing.
##
## Taken from where the contacts are rather than from the normals reported with
## them: the ball is a sphere, so the way out of any point on it is simply the
## way back to its middle, and that is true whichever way round the solver
## chooses to report a normal.
func _ground_normal(state: PhysicsDirectBodyState3D) -> Vector3:
	var normal := Vector3.ZERO
	for i in state.get_contact_count():
		normal += (state.transform.origin
				- state.get_contact_local_position(i)).normalized()

	return normal.normalized() if normal.length() > 0.001 else Vector3.ZERO


## How much of the assist the surfaces underfoot are willing to give, from none
## to all of it. The slipperiest thing the ball is touching decides, so half an
## inch onto the ice is enough to lose the corner.
func _traction(state: PhysicsDirectBodyState3D) -> float:
	var lowest := 1.0
	for i in state.get_contact_count():
		var floor_body := state.get_contact_collider_object(i) as PhysicsBody3D
		if floor_body == null:
			continue

		# Asked for rather than read off, because the property belongs to the
		# bodies that can carry one and not to what they have in common. No
		# material at all is the default surface, which is worth a friction of
		# one -- the same number the assist is written in terms of.
		var material := floor_body.get("physics_material_override") as PhysicsMaterial
		lowest = minf(lowest, material.friction if material != null else 1.0)

	return clampf(lowest, 0.0, 1.0)
