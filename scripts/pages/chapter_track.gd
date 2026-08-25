extends Control

## The run through a world, drawn as a line of dots joined end to end.
##
## Reads like the map between worlds in a platformer: the road behind you is
## solid, the road ahead is dashed, and every stop on it is visible from the
## start whether or not you can play it yet. That is the whole point of drawing
## it this way -- a list of six buttons says what is open, a track says how far
## through the world you are and what is left.
##
## Dots, by what the player has done with the chapter:
##
##   green   its challenge run is finished
##   yellow  open, and part way through
##   grey    not unlocked yet -- still tappable, so the rest of the world can be
##           looked at, just not played
##
## Everything is drawn rather than built out of nodes. Six buttons with circular
## styleboxes would need the joining lines drawn behind them anyway, and then the
## lines would have to chase the buttons' positions around; one `_draw()` that
## owns both keeps them in step by construction.

## Fired when a dot is tapped, including a locked one -- browsing ahead is
## allowed, and the page decides what a locked chapter is allowed to do.
signal chapter_picked(index: int)

const DOT_RADIUS := 26.0
## The ring around the chapter being looked at.
const SELECTED_RING := 40.0
const SELECTED_RING_WIDTH := 6.0

const LINE_WIDTH := 6.0
## Length of a dash and of the gap after it, on the road not yet travelled.
const DASH := 16.0

## How near a tap has to land. Generously bigger than the dot: these are small
## targets on a phone, and the dots are far enough apart that a wide catchment
## still cannot reach the wrong one.
const TAP_RADIUS := 78.0

const DONE_COLOUR := Color(0.29, 0.78, 0.36)
const OPEN_COLOUR := Color(0.98, 0.79, 0.16)
const LOCKED_COLOUR := Color(0.29, 0.31, 0.34)
const ROAD_AHEAD_COLOUR := Color(0.38, 0.41, 0.45)
const RING_COLOUR := Color(1, 1, 1)

## The world being shown, and which of its chapters is being looked at. Held so a
## resize can redraw without the page having to say it all again.
var _world := 0
var _selected := 0


func _ready() -> void:
	resized.connect(queue_redraw)


## Points the track at a world and marks one chapter as the one being looked at.
func show_world(world: int, selected_chapter: String) -> void:
	_world = world
	_selected = maxi(LevelManager.chapter_index(selected_chapter), 0)
	queue_redraw()


func _draw() -> void:
	var count: int = LevelManager.CHAPTERS.size()
	if count == 0:
		return

	# The road first, so the dots sit on top of it rather than being cut by it.
	for i in count - 1:
		var travelled := _is_done(i)
		if travelled:
			draw_line(_dot_at(i), _dot_at(i + 1), DONE_COLOUR, LINE_WIDTH)
		else:
			draw_dashed_line(
				_dot_at(i), _dot_at(i + 1), ROAD_AHEAD_COLOUR, LINE_WIDTH, DASH)

	for i in count:
		var centre := _dot_at(i)
		draw_circle(centre, DOT_RADIUS, _colour_for(i))

		if i == _selected:
			draw_arc(centre, SELECTED_RING, 0.0, TAU, 48, RING_COLOUR,
				SELECTED_RING_WIDTH, true)


func _gui_input(event: InputEvent) -> void:
	var at := Vector2.ZERO

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		at = touch.position
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		at = click.position
	else:
		return

	var hit := _nearest_dot(at)
	if hit >= 0:
		accept_event()
		chapter_picked.emit(hit)


## Where a chapter's dot sits. Spread across the full width with half a gap at
## each end, so the first and last dots are inset rather than hard against the
## edges where a ring would be clipped.
func _dot_at(index: int) -> Vector2:
	var count: int = LevelManager.CHAPTERS.size()
	var step := size.x / float(count)
	return Vector2(step * (float(index) + 0.5), size.y * 0.5)


## The chapter nearest a tap, or -1 if the tap was not near any of them.
func _nearest_dot(at: Vector2) -> int:
	var best := -1
	var best_distance := TAP_RADIUS

	for i in LevelManager.CHAPTERS.size():
		var distance := at.distance_to(_dot_at(i))
		if distance <= best_distance:
			best = i
			best_distance = distance

	return best


func _colour_for(index: int) -> Color:
	if _is_done(index):
		return DONE_COLOUR

	var chapter: String = LevelManager.CHAPTERS[index]
	if GameState.is_set_unlocked(_world, chapter):
		return OPEN_COLOUR

	return LOCKED_COLOUR


## Whether a chapter counts as beaten. The challenge run is the thing that
## finishes a chapter and opens the next, so it is what the road is drawn from --
## free play through every level in it does not join the dots up.
func _is_done(index: int) -> bool:
	var chapter: String = LevelManager.CHAPTERS[index]
	return GameState.is_challenge_complete(_world, chapter)
