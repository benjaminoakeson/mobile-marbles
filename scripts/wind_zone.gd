@tool
class_name WindZone
extends Area3D

## A stretch of moving air: it shows as wisps blowing through, and it pushes the
## ball the way they are going.
##
## Blows along the node's own forward, so it is aimed with the ordinary rotation
## gizmo and the wisps show which way that is -- there is nothing else to read.
## Drop it under the Level body, turn it to face where the wind should go, and
## set [member size].
##
## The wisps are emitted in LOCAL coordinates, so they ride the zone. A wind zone
## never moves relative to the level it is bolted to, so carrying its particles
## along with it is exactly right, and it stays right if that level is ever
## animated.
##
## [b]The push does not fall off[/b], anywhere inside. A ball that sits in the
## wind keeps accelerating for as long as it is in there, which is the point --
## the zone's own size is what limits it. A long zone is a strong one.

## How big the zone is. Set the shape with this rather than with the node's
## scale: the collider and the volume the wisps are born in are both built from
## these numbers, and a scaled node would stretch the wisps along with it.
##
## Measured along the node's own axes, so Z is the length the wind blows down.
@export var size := Vector3(6.0, 4.0, 12.0):
	set(value):
		size = Vector3(maxf(value.x, 0.1), maxf(value.y, 0.1), maxf(value.z, 0.1))
		_rebuild()

## The push on the ball while it is inside, in newtons.
##
## Measured against the real ball, which is five kilos at the gravity the game
## plays at -- so it weighs about 150 N, and that is the number to think in:
##
##     30 ....  a lean the player can push straight through
##     90 ....  a shove that has to be steered against
##    150 ....  as strong as gravity; holds the ball on a vertical wall
##    250 ....  the ball goes where the wind says
@export var force := 90.0

@export_group("Wisps")

## How fast the wisps travel, in metres a second. Only a look -- the push is
## [member force] and the two are set separately on purpose, so a gale can be
## made to look fast without being made to shove harder.
@export var wisp_speed := 9.0:
	set(value):
		wisp_speed = maxf(value, 0.1)
		_rebuild()

## Roughly how many wisps there are in each cubic metre of the zone. Scaled by
## volume rather than fixed, so a zone made bigger does not thin out.
@export var wisp_density := 0.5:
	set(value):
		wisp_density = maxf(value, 0.0)
		_rebuild()

## Ceiling on that, so a large zone cannot quietly hand the renderer tens of
## thousands of ribbons.
@export var wisp_limit := 320

## The bodies currently in the wind. Tracked from the area's own signals rather
## than by asking for the overlaps every tick, which is the same list arrived at
## the long way round.
var _blown: Array[RigidBody3D] = []

@onready var _shape: CollisionShape3D = $Shape
@onready var _wisps: GPUParticles3D = $Wisps
@onready var _gust: ParticleProcessMaterial = null


func _ready() -> void:
	# The material is sized to this zone, so this instance needs its own copy:
	# the resource on disk is shared with every other wind zone in the level.
	_gust = (_wisps.process_material as ParticleProcessMaterial).duplicate()
	_wisps.process_material = _gust
	_rebuild()

	# The rest is gameplay, and the editor has no business running it.
	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _blown.is_empty():
		return

	# Read fresh every tick rather than cached, so a level that is moved or
	# animated carries its wind round with it.
	var push := -global_transform.basis.z.normalized() * force

	for body in _blown:
		# A ball pinned on the level's opening drop, or coasting through the goal,
		# is not in play and is not the wind's to move.
		if is_instance_valid(body) and not body.freeze:
			body.apply_central_force(push)


## Sizes the collider and the volume the wisps are born in from [member size],
## and works out how many of them there should be and how long they live.
func _rebuild() -> void:
	if not is_node_ready():
		return

	var box := _shape.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		_shape.shape = box
	box.size = size

	if _gust == null:
		return
	_gust.emission_box_extents = size * 0.5

	# Wisps are born anywhere in the box and blow along -Z, so the longest any of
	# them has to live is one full length of the zone. A little over, so the ones
	# that start at the upwind face are still going when they leave the far one
	# rather than winking out inside it.
	_wisps.lifetime = size.z / wisp_speed * 1.15
	_gust.initial_velocity_min = wisp_speed * 0.8
	_gust.initial_velocity_max = wisp_speed * 1.25

	var volume := size.x * size.y * size.z
	_wisps.amount = clampi(roundi(volume * wisp_density), 4, maxi(wisp_limit, 4))

	# Culling is measured against a box on the emitter, and the default one is a
	# few metres across -- so on any zone bigger than that the wisps simply stop
	# being drawn. Sized from the zone instead, and padded, because a wisp is
	# still alive for a moment after it has blown out of the far face.
	var reach := size * 0.5 + Vector3.ONE * (size.z * 0.25 + 1.0)
	_wisps.visibility_aabb = AABB(-reach, reach * 2.0)


func _on_body_entered(body: Node3D) -> void:
	var ball := body as RigidBody3D
	if ball != null and ball.is_in_group("player") and not _blown.has(ball):
		_blown.append(ball)


func _on_body_exited(body: Node3D) -> void:
	_blown.erase(body as RigidBody3D)
