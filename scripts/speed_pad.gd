@tool
class_name SpeedPad
extends Area3D

## What a pad does to a ball crossing it.
enum Kind {
	BOOST, ## Drives it along the pad's own forward.
	BRAKE, ## Slows it down, whichever way it is going, but never to a stop.
}

## A patch of track that drives the ball on, or takes its speed away.
##
## One scene covers both, and [member kind] picks. A BOOST shoves the ball along
## the pad's own forward -- its local -Z, the way the rotation gizmo points it --
## so aiming the pad aims the boost. A BRAKE takes speed off whatever crosses it,
## whichever way that is, because a brake has nothing to aim -- down to
## [member minimum_speed] and no further, so it slows the ball rather than
## catching it.
##
## The pad colours itself from that: blue for a boost, red for a brake. There is
## no way to build a red pad that speeds you up, which is the point of deriving
## the colour rather than setting it.
##
## Drop it under the Level body, lay it flat on the track and set [member size].

## How big the pad is. Set the shape with this rather than with the node's scale:
## the collider, the face you can see and the spacing of the rings on it are all
## built from these numbers.
##
## X and Z are the footprint. Y is how far up off the face the pad still catches
## the ball, so it wants to be at least a ball's diameter or a fast one will skip
## over it between two ticks.
@export var size := Vector3(4.0, 1.4, 4.0):
	set(value):
		size = Vector3(maxf(value.x, 0.1), maxf(value.y, 0.1), maxf(value.z, 0.1))
		_rebuild()

## Which of the two this is. The colour and the way the energy runs both follow
## it, so a pad cannot end up saying one thing and doing another.
@export var kind := Kind.BOOST:
	set(value):
		kind = value
		_rebuild()

## How hard, in metres per second per second. A BOOST pushes this hard along the
## pad's forward; a BRAKE pulls this hard against whatever the ball is doing,
## until the ball is down to [member minimum_speed].
##
## Worth measuring against the game's own gravity, which is 29.4 -- so 30 is a
## pad that pushes about as hard as falling, and a ball crossing a four-metre pad
## at 10 m/s is on it for under half a second.
@export var strength := 30.0:
	set(value):
		strength = maxf(value, 0.0)
		_rebuild()

## The speed a BRAKE will not take the ball below, in metres a second. Ignored
## by a BOOST.
##
## A brake takes speed OFF; it is not a wall. Left at 0 a long enough pad parks
## the ball on itself, which is a dead stop in the middle of a run and reads as
## being caught rather than slowed. Braking down to a floor instead means a pad
## always hands the ball back still rolling, and how fast is the level
## designer's to choose: come off this one at walking pace, that one at a crawl.
@export var minimum_speed := 4.0:
	set(value):
		minimum_speed = maxf(value, 0.0)

@export_group("Look")

## The two colours, picked between by [member kind].
@export var push_colour := Color(0.25, 0.62, 1.0):
	set(value):
		push_colour = value
		_rebuild()
@export var drag_colour := Color(1.0, 0.24, 0.26):
	set(value):
		drag_colour = value
		_rebuild()

## How far apart the chevrons are along the pad, in metres. Held in metres rather
## than as a count so every pad in a level pulses at the same scale whatever size
## it is dragged out to.
@export var pulse_spacing := 1.4:
	set(value):
		pulse_spacing = maxf(value, 0.05)
		_rebuild()

## How fast they travel, in chevrons a second.
@export var pulse_speed := 0.9:
	set(value):
		pulse_speed = maxf(value, 0.0)
		_rebuild()

## How pointed the arrowheads are, and WHICH WAY ROUND THEY FACE. Negate it to
## turn them round; the direction they travel in is not affected.
##
## Its own knob rather than something derived, because which way a pattern runs
## and which way its arrowheads point come out of the same maths but are not the
## same question, and getting one right is no guarantee about the other.
@export_range(-1.0, 1.0, 0.01) var chevron := -1.0:
	set(value):
		chevron = clampf(value, -1.0, 1.0)
		_rebuild()

## The bodies currently on the pad. Tracked from the area's own signals rather
## than by asking for the overlaps every tick.
var _riders: Array[RigidBody3D] = []

@onready var _shape: CollisionShape3D = $Shape
@onready var _face: MeshInstance3D = $Face
var _energy: ShaderMaterial = null


func _ready() -> void:
	# The colours are per pad, so this instance needs its own copy: the material
	# on disk is shared with every other pad in the level.
	_energy = (_face.material_override as ShaderMaterial).duplicate()
	_face.material_override = _energy
	_rebuild()

	# The rest is gameplay, and the editor has no business running it.
	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _riders.is_empty():
		return

	# Read fresh every tick, so a pad on a level that is moved or animated aims
	# with it. This node is a child of the level, so the level has already been
	# placed for this tick by the time we are called.
	var forward := -global_transform.basis.z.normalized()

	for ball in _riders:
		# A ball pinned on the level's opening drop, or coasting through the
		# goal, is not in play and is not the pad's to move.
		if not is_instance_valid(ball) or ball.freeze:
			continue

		if kind == Kind.BOOST:
			# Along the PAD, not along the ball. Aiming the pad is the whole
			# point of a boost: cross one sideways and it turns you.
			ball.apply_central_force(forward * strength * ball.mass)
			continue

		var speed := ball.linear_velocity.length()
		# Already down to what this pad brakes to, or going too slowly to take a
		# direction from. Either way there is nothing to take off it.
		if speed <= minimum_speed or speed < 0.001:
			continue

		# Capped at exactly what brings the ball to `minimum_speed` this tick, so
		# it lands on that speed rather than a frame's worth past it -- and so a
		# brake can never push the ball backwards, whatever it is set to.
		var pull := ball.linear_velocity / speed * -strength * ball.mass
		ball.apply_central_force(pull.limit_length(
				(speed - minimum_speed) * ball.mass / maxf(delta, 0.0001)))


## Sizes the collider and the face from [member size], and tells the shader which
## way round the pad is.
func _rebuild() -> void:
	if not is_node_ready():
		return

	var box := _shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		_shape.shape = box
	box.size = size
	# Sat on the face rather than centred on it, so the node's own origin is the
	# surface you lay on the track and the catching height goes upwards from it.
	_shape.position = Vector3(0.0, size.y * 0.5, 0.0)

	var plane := _face.mesh as PlaneMesh
	if plane == null:
		plane = PlaneMesh.new()
		_face.mesh = plane
	plane.size = Vector2(size.x, size.z)

	if _energy == null:
		return
	var pushing := kind == Kind.BOOST
	_energy.set_shader_parameter("energy_colour", push_colour if pushing else drag_colour)
	_energy.set_shader_parameter("pulse_speed", pulse_speed)
	_energy.set_shader_parameter("chevron", chevron)

	# The face's V runs along the pad's +Z, and the pad faces -Z, so travelling
	# forwards is travelling DOWN V. A boost therefore flows negative; a brake,
	# whose force acts backwards along the pad, flows positive.
	_energy.set_shader_parameter("flow", -1.0 if pushing else 1.0)

	# Chevrons measured along the pad's length, which is what the shader's V runs
	# from end to end over.
	_energy.set_shader_parameter("bands", maxf(size.z / pulse_spacing, 0.5))


func _on_body_entered(body: Node3D) -> void:
	var ball := body as RigidBody3D
	if ball != null and ball.is_in_group("player") and not _riders.has(ball):
		_riders.append(ball)


func _on_body_exited(body: Node3D) -> void:
	_riders.erase(body as RigidBody3D)
