extends AudioStreamPlayer

## The ball's own noise: a rolling loop that follows how fast it is going, and a
## knock whenever it runs into something.
##
## Hangs off the ball and reads the body it is parented to, so a level does not
## have to wire anything up -- dropping the player scene in is enough.

## How fast the ball has to be going for the roll to be heard at all, in metres
## a second. Below this it is being nudged, not rolled.
@export var quiet_speed := 0.6

## The speed the roll is at its loudest, in metres a second.
@export var loud_speed := 14.0

## How much quieter than full the roll is when it is only just moving.
@export var roll_range_db := 24.0

## How quickly the roll follows a change in speed. Low enough that a bump does
## not click, high enough that stopping is heard as stopping.
@export var response := 12.0

## What the roll is pitched at when crawling and at full pelt, so speed is heard
## as well as measured.
@export var min_pitch := 0.7
@export var max_pitch := 1.25

## How hard the ball has to hit something to be worth a knock, in metres a
## second, and how long before another knock can be heard.
@export var bump_speed := 2.0
@export var bump_gap := 0.06

@onready var _ball: RigidBody3D = get_parent() as RigidBody3D

## The ball's speed as of the start of this physics step -- see `_on_hit()`.
var _speed := 0.0
var _since_bump := 0.0


func _ready() -> void:
	if _ball == null:
		push_warning("BallAudio: expected to hang off a RigidBody3D")
		set_physics_process(false)
		return

	# Started once and never stopped. The roll is a loop turned up and down
	# rather than started and stopped, which is what keeps it from clicking
	# every time the ball touches down.
	stream = Audio.ROLL
	bus = Audio.SFX_BUS
	volume_db = -80.0
	play()

	_ball.body_entered.connect(_on_hit)


func _physics_process(delta: float) -> void:
	_since_bump += delta

	# Read before the step, so anything the ball hits during it is measured by
	# the speed it hit at rather than by what is left afterwards.
	_speed = _ball.linear_velocity.length()

	var rolling := _ball.get_contact_count() > 0 and _speed > quiet_speed
	var target := -80.0

	if rolling:
		var pace := clampf(
			(_speed - quiet_speed) / maxf(loud_speed - quiet_speed, 0.001), 0.0, 1.0)
		target = -roll_range_db * (1.0 - pace)

	volume_db = lerpf(volume_db, target, clampf(response * delta, 0.0, 1.0))
	pitch_scale = lerpf(min_pitch, max_pitch, clampf(_speed / loud_speed, 0.0, 1.0))


## A knock, as loud as the ball was fast. Quiet taps and the flurry of contacts
## that one landing can throw off are both dropped.
func _on_hit(_body: Node3D) -> void:
	if _speed < bump_speed or _since_bump < bump_gap:
		return

	_since_bump = 0.0

	var force := clampf(
		(_speed - bump_speed) / maxf(loud_speed - bump_speed, 0.001), 0.0, 1.0)
	Audio.play(Audio.BUMP, linear_to_db(lerpf(0.25, 1.0, force)), randf_range(0.95, 1.08))
