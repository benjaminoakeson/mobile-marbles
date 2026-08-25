extends Control

## The level's two scoring deadlines, drawn as laps round the clock.
##
## Red fills first, closing its loop exactly as the fast-time window shuts: a
## complete red ring means the fast-time multiplier has gone. Blue then fills
## over the top of it and closes as the time score reaches nothing, so a
## complete blue ring means the level is worth its clear and its gems and no
## more.
##
## Both deadlines are read off the level's own goal ring, so a level tuned to a
## three second run and one tuned to thirty draw the same two laps at their own
## pace -- there is nothing to set here per level.

## Twelve o'clock. Godot measures angles clockwise from three, so this fills the
## way a clock hand sweeps.
const START := -PI * 0.5

const WIDTH := 12.0

## Segments in a whole turn. Enough that a lap reads as a curve rather than as a
## polygon at the size the circle is drawn.
const SEGMENTS := 96

const TRACK_COLOR := Color(1, 1, 1, 0.12)
const FAST_COLOR := Color(0.9019608, 0.21960784, 0.21960784, 0.95)
const SLOW_COLOR := Color(0.24705882, 0.54901963, 0.9490196, 0.95)

var _fast_time := 0.0
var _slow_time := 0.0

## Set once both laps are closed and there is nothing left to animate. The last
## drawing stands, so the ring stops asking to be redrawn every frame.
var _settled := false


func _ready() -> void:
	# Every level carries one goal ring, and it is what holds the tuning. A
	# level opened without one -- or with the time score turned off -- has no
	# deadlines to draw.
	var goal := get_tree().get_first_node_in_group("goal_ring")
	if goal == null or not goal.has_method("fast_time"):
		hide()
		return

	_slow_time = goal.slow_time
	_fast_time = goal.fast_time()

	if _slow_time <= 0.0:
		hide()


func _process(_delta: float) -> void:
	if _settled:
		return

	# Queued before the check, not after, so the frame the clock crosses the
	# slow time still gets drawn -- otherwise the ring settles a frame short of
	# closed.
	queue_redraw()

	if _slow_time <= 0.0 or GameState.level_time >= _slow_time:
		_settled = true


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

	# Red is drawn first and left alone. Blue goes over the top of a closed red
	# lap rather than replacing it, so a ring part way through its second lap
	# still shows that the first one is spent.
	var elapsed := GameState.level_time
	_draw_lap(centre, radius, _share(elapsed, 0.0, _fast_time), FAST_COLOR)
	_draw_lap(centre, radius, _share(elapsed, _fast_time, _slow_time), SLOW_COLOR)


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
