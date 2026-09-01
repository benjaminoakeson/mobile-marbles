extends Control

## The level's fast-time deadline, drawn as a lap round the clock.
##
## Red fills once, closing its loop exactly as the fast-time window shuts -- and
## then goes. It flares white-hot on the instant it closes and dissolves off the
## clock, so the bonus expiring is something the player SEES happen rather than
## something they have to notice has finished. A complete red ring left standing
## says the same thing as a bare one to anybody who was not watching at the
## moment it closed; the flash is the moment, and the bare ring afterwards is the
## honest readout of what is left to play for.
##
## There was a second, blue lap over the top of it, running on to the slow time.
## The clock inside the ring counts DOWN to that same moment now, so the blue lap
## was the number said twice. What is left is the one deadline the number does
## NOT say: the ring is the bonus, the number is the buzzer.
##
## The deadline is read off the level's own goal ring, so a level tuned to a
## three second run and one tuned to thirty draw the same lap at their own pace
## -- there is nothing to set here per level.

## Twelve o'clock. Godot measures angles clockwise from three, so this fills the
## way a clock hand sweeps.
const START := -PI * 0.5

const WIDTH := 12.0

## Segments in a whole turn. Enough that a lap reads as a curve rather than as a
## polygon at the size the circle is drawn.
const SEGMENTS := 96

const TRACK_COLOR := Color(1, 1, 1, 0.12)
const FAST_COLOR := Color(0.9019608, 0.21960784, 0.21960784, 0.95)

## What the lap flares to on the instant it closes. Red still, but lifted most of
## the way to white so it reads as the same ring catching light rather than as a
## different colour arriving.
@export var flash_colour := Color(1.0, 0.72, 0.68, 1.0)

## The flare, the beat it is held for, and how long it takes to dissolve. Quick,
## held briefly, gone slowly -- a bang and a wisp, not a pulse.
@export var flash_in := 0.09
@export var flash_hold := 0.12
@export var fade_out := 0.55

var _fast_time := 0.0
var _slow_time := 0.0

## How far into the flare the lap is, 0 to 1, and how much of it is left to draw.
## Driven by the one tween in [method _flash_out] and read by [method _draw].
##
## The flare is NOT wound back down before the fade. Holding it at full while the
## alpha goes means the ring dissolves while it is still white-hot, which is what
## something burning out looks like.
var _flare := 0.0
var _fade := 1.0

## Set once the lap is closed, faded, and there is nothing left to animate. The
## last drawing stands, so the ring stops asking to be redrawn every frame.
var _settled := false

## Set when the flare is started, so the frame after cannot start it again.
var _flashing := false


func _ready() -> void:
	# Every level carries one goal ring, and it is what holds the tuning. A
	# level opened without one -- or with the time score turned off -- has no
	# deadlines to draw.
	var goal := get_tree().get_first_node_in_group("goal_ring") as GoalRing
	if goal == null:
		hide()
		return

	_slow_time = goal.slow_time
	_fast_time = goal.fast_deadline()

	if _slow_time <= 0.0:
		hide()
		return

	# A level offering no fast-time bonus at all has no window to close and
	# nothing to flare about. Its lap is over before it starts, so it is never
	# drawn rather than flashed away on the first frame.
	if _fast_time <= 0.0:
		_fade = 0.0
		_settled = true


func _process(_delta: float) -> void:
	if _settled:
		return

	# Queued before the check, not after, so the frame the clock crosses the
	# deadline still gets drawn -- otherwise the lap flares a frame short of
	# closed.
	queue_redraw()

	if not _flashing and GameState.level_time >= _fast_time:
		_flash_out()


## The lap closing: a flare, a held beat, and then it dissolves.
##
## One tween in sequence rather than a state machine, because that is all this
## is -- and `_settled` is set from its far end rather than from a timer, so the
## ring goes on redrawing for exactly as long as there is something moving and
## stops the frame there is not.
func _flash_out() -> void:
	_flashing = true

	var flash := create_tween()
	flash.tween_property(self, "_flare", 1.0, flash_in).set_ease(Tween.EASE_OUT)
	flash.tween_interval(flash_hold)
	flash.tween_property(self, "_fade", 0.0, fade_out).set_ease(Tween.EASE_IN)
	flash.tween_callback(func() -> void:
		# One last frame at nothing before the redraws stop, or whatever the
		# second-to-last frame happened to be drawn at would be left on screen.
		queue_redraw()
		_settled = true)


func _draw() -> void:
	if _slow_time <= 0.0:
		return

	# This node is anchored to the whole of the circle behind it, so its own box
	# is the rim to trace. That only holds while the circle stays a fixed square
	# -- see the note on `TimeCircle` in `hud.tscn` for what happens when it is
	# allowed to size itself to the clock's text.
	var radius := minf(size.x, size.y) * 0.5 - WIDTH * 0.5
	if radius <= 0.0:
		return

	var centre := size * 0.5
	draw_arc(centre, radius, 0.0, TAU, SEGMENTS, TRACK_COLOR, WIDTH, true)

	# The bare track is what is left once the lap has burnt off. Nothing red
	# survives it, which is the point -- the clock's own number is the only
	# deadline still running by then.
	if _fade <= 0.0:
		return

	var colour := FAST_COLOR.lerp(flash_colour, _flare)
	colour.a *= _fade

	_draw_lap(centre, radius, _share(GameState.level_time, 0.0, _fast_time), colour)


## How far through one window the clock has got, 0 to 1.
##
## A window with no width -- a level offering no fast-time bonus at all -- is
## over before it starts rather than dividing by nothing.
func _share(elapsed: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0 if elapsed >= to else 0.0

	return clampf((elapsed - from) / (to - from), 0.0, 1.0)


func _draw_lap(centre: Vector2, radius: float, share: float, color: Color) -> void:
	if share <= 0.0:
		return

	draw_arc(centre, radius, START, START + TAU * share, SEGMENTS, color, WIDTH, true)
