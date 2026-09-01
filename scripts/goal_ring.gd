class_name GoalRing
extends StaticBody3D
## The goal: a ring stood on its edge, planted in the ground, with a pane of
## glass across the middle that the player has to smash through to win.
##
## The rim is solid, so the ball has to go through the hole rather than at the
## ring; the glass is a [DestructibleSurface] cut round, which already breaks
## from whichever side it is struck, so the goal is open both ways with nothing
## here to say so.
##
## StaticBody3D rather than AnimatableBody3D: a nested animatable body under the
## level body brings the `sync_to_physics` trap with it if that level is ever
## moved. Same reason the destructible surfaces are static.

## Fires once the ball is through and on its way out. The level is over by then.
signal level_completed

# --- Level Finished Settings ---
## The least the ball may leave the ring at, in metres a second.
##
## A FLOOR, not a speed. Whatever the ball arrived carrying is what it leaves
## with; this only catches the goal that was barely broken into, so a ball that
## trickled through still gets clear of the ring instead of stalling in it.
@export var minimum_exit_speed := 5.0

## Drag on the coasting ball. Gravity is off from the moment it comes through, so
## this is the only thing that stops it: it carries on about `exit speed / this`
## metres before settling, which is what makes a fast goal pay -- at the ring's
## own 0.7, coming through at five metres a second runs about seven metres and
## coming through at fifteen runs about twenty.
##
## Angular drag is set to match, so the spin winds down with the roll rather than
## leaving a marble turning on the spot.
@export var coast_damping := 4.0

## Seconds between coming through and the menu appearing, so the ball is seen
## clear of the ring first.
@export var menu_delay := 1.5

@export var level_complete_scene: PackedScene = preload("res://scenes/UI/level_complete.tscn")
# -------------------------------

# --- Scoring ---
# Set per level: override these on the GoalRing inside each level scene.

## Points for reaching the ring at all, whatever the time.
##
## In the same money as the gems, roughly: a level holds twenty-odd gems' worth,
## and clearing it is worth a few levels of those. Set against the gems on
## purpose -- a clear score in the thousands would bury them, and finding every
## gem in a level should be worth reading on the tally.
@export var clear_score := 125

## Points on offer for being quick. Worth its full value the instant the clock
## starts and ticking evenly down from there, so every second costs something --
## two runs a second apart never score the same.
@export var time_score := 125

## When the time score runs out. Finish at or after this and it is worth nothing;
## the clear score and gems still stand.
@export var slow_time := 60.0

## When the fast-time bonus closes, in SECONDS from the start of the clock.
## Finish inside this and the whole level is multiplied by `fast_time_multiplier`.
##
## Set outright rather than as a share of `slow_time`, because what a level is
## being tuned to is a time a player can actually roll it in -- a number in the
## same units as the clock they are watching. As a share it moved every time the
## buzzer was retuned, and getting a level to a two-and-a-bit second gold meant
## working backwards through a fraction.
##
## Held to the buzzer when it is read -- see [method fast_deadline] -- so a value
## longer than `slow_time` cannot quietly hand the bonus to every finish.
@export var fast_time := 30.0

## What the whole level is multiplied by for a fast finish.
@export var fast_time_multiplier := 2.0

## What the whole level is multiplied by when every gem in it was collected.
## 1.0 turns the bonus off.
##
## This multiplies the WHOLE tally, not just the points the gems were worth, so
## it is a far bigger prize than the number alone suggests.
@export var all_gems_multiplier := 3.0
# ---------------

# --- Smash Reaction ---
## How far the ring kicks out when the glass goes, and how long it takes to
## settle back.
##
## This replaced a breathing idle. A ring that grows and shrinks around a pane
## that cannot opens a rind of daylight at the rim on every breath -- and a
## reaction to the smash is worth more than an idle anyway.
@export var punch_scale := 1.18
@export var punch_time := 0.45
# ----------------------

var _is_triggered := false

@onready var ring: MeshInstance3D = $Ring
@onready var _glass: DestructibleSurface = $Glass
@onready var _ring_collider: CollisionShape3D = $RingCollider
@onready var _confetti: GPUParticles3D = get_node_or_null("Confetti") as GPUParticles3D


func _ready() -> void:
	# The rim is solid, and its collider is cut from the very mesh being drawn, so
	# the ring can be resized in the inspector without a hand-baked shape left
	# behind at the old size. Concave is what the level's own geometry uses.
	if _ring_collider.shape == null and ring.mesh != null:
		_ring_collider.shape = ring.mesh.create_trimesh_shape()


func _process(_delta: float) -> void:
	# The clock runs on frames, so the frame is where it has to be stopped. The
	# `body_entered` signal this used to listen on fires inside the physics
	# flush, part way through a frame that has not added its own delta yet, and
	# the time the ring reads is a frame behind the one the player is watching.
	# Now that a time is kept to the millisecond that gap is visible.
	#
	# The overlap itself still only changes on a physics tick -- that is where
	# bodies move -- so this does not catch the ball any sooner. What it fixes is
	# WHICH reading of the clock gets banked.
	_check_for_smash()


## Looks for the glass gone, once a frame.
##
## The glass decides in the physics tick, but it is read here for the reason the
## overlap used to be: a level banked mid-flush reads a clock a frame behind the
## one the player is watching, and now that the time is kept to the millisecond
## that gap shows. Waiting for the frame does not let the ball through any later
## -- the glass is already broken and the ball already through it.
func _check_for_smash() -> void:
	if _is_triggered or _glass == null or not _glass.is_broken():
		return

	var ball := get_tree().get_first_node_in_group("player") as RigidBody3D
	if ball != null:
		_catch(ball)


func _catch(body: RigidBody3D) -> void:
	_is_triggered = true

	# Stop the clock HERE, on the break. Banking the level happens after the ball
	# has coasted clear, and charging the player for that bit of cutscene would be
	# daylight robbery.
	GameState.stop_timing()

	# Which way the ball was going as it came through. Read before anything is
	# done to the body, because everything that follows is aimed along it.
	var heading := _heading_of(body)

	Audio.play(Audio.FANFARE)
	_spray_confetti(heading)
	_punch_ring()

	# Let go of gravity and put it back to straight down. Everything from here --
	# the nudge, the confetti -- is aimed at where things stand right now, and a
	# lean still easing back towards level would drag the ball off that line.
	# Taking the stick away only stops NEW input.
	var steering := get_tree().get_first_node_in_group("level_body")
	if steering != null and steering.has_method("freeze"):
		steering.freeze()

	# The stick goes too, so it neither steers a frozen level nor draws over the
	# menu later.
	var stick := get_tree().get_first_node_in_group("thumbstick") as Thumbstick
	if stick != null:
		stick.disable()

	# And the camera drag with it, so the victory orbit cannot be wrestled off
	# course from behind the menu.
	var camera_control := get_tree().get_first_node_in_group("camera_control") as CameraDrag
	if camera_control != null:
		camera_control.disable()

	_send_off(body, heading)


## The way the ball was travelling as it came through the glass.
##
## Falls back to the way the ring faces, pointed away from wherever the ball is,
## for the case that should not happen: a goal opened by a ball that is barely
## moving. Sending it nowhere would leave it sitting in the ring.
func _heading_of(player: RigidBody3D) -> Vector3:
	var travelling := player.linear_velocity
	if travelling.length_squared() > 0.01:
		return travelling.normalized()

	var through := ring.global_transform.basis.y.normalized()
	return through if through.dot(player.global_position - global_position) >= 0.0 else -through


## One burst of confetti out of the ring, thrown the way the ball went, with its
## own pop on top of the fanfare.
##
## Fired the instant the glass goes, so the celebration is already going while
## the ball is still coasting out, rather than starting after it.
func _spray_confetti(heading: Vector3) -> void:
	if _confetti == null:
		return

	# The burst is built around the emitter's own up, so standing that on the
	# heading sends the paper out after the ball. Aimed in world space rather
	# than by turning the goal, which the ring and the glass are hung off.
	var up := heading.normalized()
	var side := up.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	_confetti.global_transform = Transform3D(
			Basis(side, up, side.cross(up)), _confetti.global_position)

	Audio.play(Audio.CONFETTI)
	_confetti.restart()


## The ring's own answer to the glass going: a kick outward that settles back.
func _punch_ring() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(ring, "scale", Vector3.ONE * punch_scale, punch_time * 0.35)
	tween.tween_property(ring, "scale", Vector3.ONE, punch_time * 0.65)


## Sends the ball on out the far side and lets it run down to a stop.
##
## Everything it arrived with goes with it. A goal taken flat out should look
## taken flat out: the ball bursts out the far side still carrying its speed and
## runs a long way down before the drag settles it, while a goal crept into
## barely clears the ring. The glass has already taken its cut on the way through
## -- see [member DestructibleSurface.shatter_momentum_kept] -- and that shave is
## the whole price of the goal.
##
## The spin is left alone, because a marble that stops turning the instant it
## wins looks switched off.
func _send_off(player: RigidBody3D, heading: Vector3) -> void:
	# Pointed along the way it was already going, which is the heading read
	# before anything was done to the body. Redirecting rather than leaving the
	# velocity untouched costs nothing -- the two are the same direction -- and
	# it keeps a ball that clipped the rim on its way through flying straight.
	var carried := maxf(player.linear_velocity.length(), minimum_exit_speed)
	player.linear_velocity = heading * carried

	# The ball is nobody's to steer now, so its grip and its brake come off with
	# the steering. Left on, they would haul the send-off up short.
	if player is Player:
		player.stop_driving()

	# Gravity off and drag piled on, so the ball carries on the way it was going
	# and settles in the open rather than arcing back down through the level
	# behind the menu.
	player.gravity_scale = 0.0
	player.linear_damp = coast_damping
	player.angular_damp = coast_damping

	var camera := get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	if camera != null:
		camera.start_victory_orbit()

	var awards := _award_breakdown()
	GameState.last_award = awards

	# The gems already scored as they were picked up, so only the difference is
	# handed over -- that lands the running score exactly on the tally's total.
	#
	# The two facts alongside it are what the crowns are worked out from. Both
	# are read HERE, before the panel goes up: the deadline is this ring's own
	# tuning, and the gems have to be counted while the level is still standing.
	GameState.finish_level(
		_award_total(awards) - GameState.gem_score,
		_was_fast(),
		GameState.all_gems_collected())
	level_completed.emit()
	_show_menu()


## Whatever is left of the time score at the moment the ball reached the ring.
##
## Reads the clock frozen on the break, so coasting out costs nothing, and the
## clock itself only started when the player first steered.
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


## The fast-time deadline actually in force, in seconds. Zero for a level that is
## not offering the bonus at all.
##
## This is where [member fast_time] is held to the buzzer. A fast time set longer
## than the slow time would hand the bonus to every finish -- including one that
## ran the clock out and rolled in on momentum -- so the two numbers are reconciled
## in the one place that answers the question, rather than trusted to whoever
## typed them.
##
## Public because the HUD draws this deadline; see `time_ring.gd`.
func fast_deadline() -> float:
	if slow_time <= 0.0 or fast_time <= 0.0:
		return 0.0

	return minf(fast_time, slow_time)


## Whether the level was finished quickly enough to earn the fast-time bonus.
func _was_fast() -> bool:
	var deadline := fast_deadline()
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
