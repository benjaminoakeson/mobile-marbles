extends AnimatableBody3D

## Fires once the ball has been caught and thrown. The level is over by then.
signal level_completed

@export var throw_force := 15.0
@export var snap_duration := 0.25 # How fast the ball vacuums to the center

# --- Level Finished Settings ---
## Drag on the airborne ball. Gravity is off during the celebration, so this is
## the only thing that stops it -- it coasts up about (throw impulse / mass) /
## this many metres before settling.
@export var float_damping := 4.0

## Seconds between the throw and the menu appearing, so the throw is seen first.
@export var menu_delay := 1.5

@export var level_complete_scene: PackedScene = preload("res://scenes/UI/level_complete.tscn")
# -------------------------------

# --- Scoring ---
# Set per level: override these on the GoalRing inside each level scene.

## Points for reaching the ring at all, whatever the time.
@export var clear_score := 2000

## Points on offer for being quick. Worth its full value the instant the clock
## starts and ticking evenly down from there, so every second costs something --
## two runs a second apart never score the same.
@export var time_score := 2000

## When the time score runs out. Finish at or after this and it is worth nothing;
## the clear score and gems still stand.
@export var slow_time := 60.0

## Finish inside this share of `slow_time` and the whole level is multiplied by
## `fast_time_multiplier`. At the default 0.5 that is anything under thirty
## seconds, so the bonus rides on the same per-level tuning as the time score
## rather than needing a second number set on every level.
@export var fast_time_share := 0.5

## What the whole level is multiplied by for a fast finish.
@export var fast_time_multiplier := 2.0

## What the whole level is multiplied by when every gem in it was collected.
## 1.0 turns the bonus off.
##
## This multiplies the WHOLE tally, not just the points the gems were worth, so
## it is a far bigger prize than the number alone suggests.
@export var all_gems_multiplier := 3.0
# ---------------

# --- Breathing Animation Settings ---
## How fast the ring breathes in and out.
@export var breath_speed := 2.0
## How much the ring grows and shrinks (0.05 = 5% bigger and smaller).
@export var breath_amount := 0.1

var _time_passed := 0.0
# ------------------------------------

var _is_triggered := false

@onready var trigger_area: Area3D = $TriggerArea
@onready var ring: MeshInstance3D = $Ring
@onready var _confetti: GPUParticles3D = get_node_or_null("Confetti") as GPUParticles3D


func _process(delta: float) -> void:
	# The clock runs on frames, so the frame is where it has to be stopped. The
	# `body_entered` signal this used to listen on fires inside the physics
	# flush, part way through a frame that has not added its own delta yet, and
	# the time the ring reads is a frame behind the one the player is watching.
	# Now that a time is kept to the millisecond that gap is visible.
	#
	# The overlap itself still only changes on a physics tick -- that is where
	# bodies move -- so this does not catch the ball any sooner. What it fixes is
	# WHICH reading of the clock gets banked.
	_check_for_ball()

	# Keep track of time passing
	_time_passed += delta
	
	# Math.sin() goes back and forth between -1.0 and 1.0 smoothly over time.
	# We multiply it by our amount (e.g., 0.05) to get a small scale offset.
	var scale_offset := sin(_time_passed * breath_speed) * breath_amount
	
	# Apply the new scale ONLY to the visual mesh (1.0 is the base size)
	ring.scale = Vector3.ONE * (1.0 + scale_offset)


## Looks for the ball sitting in the ring, once a frame.
func _check_for_ball() -> void:
	if _is_triggered:
		return

	for body in trigger_area.get_overlapping_bodies():
		if body is RigidBody3D and body.is_in_group("player"):
			_catch(body)
			return


func _catch(body: RigidBody3D) -> void:
	_is_triggered = true

	# Stop the clock HERE, on contact. Banking the level happens after the ball
	# has been vacuumed in and thrown, and charging the player for that quarter
	# of a second of cutscene would be daylight robbery.
	GameState.stop_timing()

	Audio.play(Audio.FANFARE)
	_spray_confetti()

	# Stop the level dead. Everything from here -- the vacuum, the throw, the
	# confetti -- is aimed at where things stand right now, so the ground must
	# not move again. Taking the stick away only stops NEW input; the tilt would
	# still ease back towards flat and the pivot would still chase the ball.
	var tilt := get_tree().get_first_node_in_group("level_tilt")
	if tilt != null and tilt.has_method("freeze"):
		tilt.freeze()

	# The stick goes too, so it neither steers a frozen level nor draws over the
	# menu later.
	var stick := get_tree().get_first_node_in_group("thumbstick") as Thumbstick
	if stick != null:
		stick.disable()

	_grab_and_throw(body)


## One burst of confetti out of the ring, with its own pop on top of the
## fanfare.
##
## Fired the instant the ball touches, so the celebration is already going while
## the ball is vacuumed in and thrown, rather than starting after it.
func _spray_confetti() -> void:
	if _confetti == null:
		return

	Audio.play(Audio.CONFETTI)
	_confetti.restart()


func _grab_and_throw(player: RigidBody3D) -> void:
	player.set_deferred("freeze", true)

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(player, "global_position", global_position, snap_duration)
	tween.tween_callback(_throw_player.bind(player))


func _throw_player(player: RigidBody3D) -> void:
	player.freeze = false
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO

	# Cut gravity and pile on drag so the ball coasts upward and hangs there,
	# rather than arcing back down through the level behind the menu.
	player.gravity_scale = 0.0
	player.linear_damp = float_damping

	player.apply_central_impulse(Vector3.UP * throw_force)

	var camera := get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	if camera != null:
		camera.start_victory_orbit()

	var awards := _award_breakdown()
	GameState.last_award = awards

	# The gems already scored as they were picked up, so only the difference is
	# handed over -- that lands the running score exactly on the tally's total.
	GameState.finish_level(_award_total(awards) - GameState.gem_score)
	level_completed.emit()
	_show_menu()


## Whatever is left of the time score at the moment the ball reached the ring.
##
## Reads the clock frozen on contact, so the vacuum-and-throw costs nothing, and
## the clock itself only started when the player first steered.
func _time_award() -> int:
	if slow_time <= 0.0:
		return 0

	var left := 1.0 - GameState.level_time / slow_time
	return int(round(time_score * clampf(left, 0.0, 1.0)))


## What the level was worth, itemised in the order the victory panel counts it
## up: the flat clear, what was left of the clock, what the gems came to, and
## then whatever multiplies the lot.
##
## Each entry is either a lump of points, `{"label", "points"}`, or a multiplier
## on everything counted so far, `{"label", "factor"}`. Order matters -- the
## multipliers only mean anything once there is a total to multiply.
func _award_breakdown() -> Array[Dictionary]:
	var awards: Array[Dictionary] = []

	awards.append({"label": "LEVEL CLEAR", "points": clear_score})

	var time_points := _time_award()
	if time_points > 0:
		awards.append({"label": "TIME", "points": time_points})

	if GameState.gem_score > 0:
		awards.append({"label": "GEMS", "points": GameState.gem_score})

	if _was_fast() and fast_time_multiplier > 1.0:
		awards.append({"label": "FAST TIME", "factor": fast_time_multiplier})

	if GameState.all_gems_collected() and all_gems_multiplier > 1.0:
		awards.append({"label": "ALL GEMS", "factor": all_gems_multiplier})

	return awards


## The breakdown added up the same way the panel counts it, so the number the
## tally lands on and the score that is banked can never drift apart.
func _award_total(awards: Array[Dictionary]) -> int:
	var total := 0.0

	for award in awards:
		if award.has("factor"):
			total *= float(award["factor"])
		else:
			total += float(award["points"])

	return int(round(total))


## When the fast-time bonus closes, in seconds from the start of the clock.
## Zero for a level that is not offering one.
##
## Worked out rather than set, so a level only ever tunes `slow_time` and the
## fast window follows it. Public because the HUD draws this deadline -- see
## `time_ring.gd`.
func fast_time() -> float:
	if slow_time <= 0.0 or fast_time_share <= 0.0:
		return 0.0

	return slow_time * fast_time_share


## Whether the level was finished quickly enough to earn the fast-time bonus.
func _was_fast() -> bool:
	var deadline := fast_time()
	if deadline <= 0.0:
		return false

	return GameState.level_time < deadline


func _show_menu() -> void:
	if level_complete_scene == null:
		return

	await get_tree().create_timer(menu_delay).timeout

	# A button press during the delay can swap the scene out from under us.
	if not is_inside_tree():
		return

	get_tree().current_scene.add_child(level_complete_scene.instantiate())
