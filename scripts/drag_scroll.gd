extends ScrollContainer

## A scrolling list that also scrolls when the finger comes down on something in
## it, rather than only on the gaps between them.
##
## A button swallows the touch that lands on it, so the list underneath never
## learns the finger is moving -- which is why a grid of tiles scrolls only when
## a swipe happens to start on empty space. The drag is read here in `_input`,
## which runs ahead of the buttons, and the button under the finger is told to
## give up its press as soon as the finger has moved far enough to mean a scroll
## rather than a tap.
##
## Only the touch events are taken, and they are taken whole: the buttons run on
## the mouse events the engine makes from the same touch, so taps go on working
## while the touch stream is this script's alone. Taking the whole stream is
## also what keeps the container's own touch scrolling from moving the list a
## second time over the gaps.
##
## Vertical only -- the lists this is on have their horizontal scrolling turned
## off.

## How far the finger has to travel before it counts as a scroll. Under this a
## touch is left alone to become a tap on whatever it came down on.
const DEADZONE := 16.0

## What fraction of a flick's speed is left a second after the finger lifts.
const FLICK_DECAY := 0.05

## The speed, in pixels a second, under which a flick is treated as finished.
const FLICK_STOP := 24.0

## The touch being followed, or -1 while there is none.
var _touch := -1

## Whether that touch has passed the deadzone and become a scroll.
var _dragging := false

## Where the touch came down, to measure the deadzone from.
var _from := Vector2.ZERO

## The scroll position carried at full precision. The container itself holds a
## whole number of pixels, and a slow drag is made of steps smaller than one --
## rounding each of them away on its own would stall it.
var _offset := 0.0

## What the list is still travelling at after a flick, in pixels a second.
var _speed := 0.0


func _process(delta: float) -> void:
	if _dragging or is_zero_approx(_speed):
		return

	_scroll_by(-_speed * delta)

	_speed *= pow(FLICK_DECAY, delta)
	if absf(_speed) < FLICK_STOP:
		_speed = 0.0


func _input(event: InputEvent) -> void:
	# A page that is not on screen still has its lists in the tree, and they
	# would otherwise fight over a touch meant for the page that is.
	if not is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _touch != -1 or not get_global_rect().has_point(touch.position):
			return

		_touch = touch.index
		_from = touch.position
		_dragging = false

		# A finger put down on a list still coasting stops it where it is.
		_speed = 0.0
		_offset = float(scroll_vertical)
	elif touch.index == _touch:
		if _dragging:
			propagate_notification(NOTIFICATION_SCROLL_END)
		_touch = -1
		_dragging = false
	else:
		return

	get_viewport().set_input_as_handled()


func _on_drag(drag: InputEventScreenDrag) -> void:
	if drag.index != _touch:
		return

	get_viewport().set_input_as_handled()

	if not _dragging:
		if absf(drag.position.y - _from.y) < DEADZONE:
			return

		_dragging = true

		# The finger is scrolling rather than tapping, so whatever it came down
		# on lets go of its press instead of firing when the finger lifts.
		propagate_notification(NOTIFICATION_SCROLL_BEGIN)

	_speed = drag.velocity.y
	_scroll_by(-drag.relative.y)


## Moves the list by `amount` pixels, stopping dead at either end -- a flick that
## runs into the top or the bottom has nowhere left to go.
func _scroll_by(amount: float) -> void:
	var bar := get_v_scroll_bar()
	var limit := maxf(0.0, bar.max_value - bar.page)

	_offset = clampf(_offset + amount, 0.0, limit)
	scroll_vertical = int(round(_offset))

	if _offset <= 0.0 or _offset >= limit:
		_speed = 0.0
