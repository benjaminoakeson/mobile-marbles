class_name HandCorner

## Where an in-level corner button sits, and the one place that decides it.
##
## The stick is dynamic -- it appears under whichever thumb lands in its box --
## so handedness is not about the stick at all. It is about the corner button: a
## button on the same side as the steering thumb is a button caught by the heel
## of it, mid-corner, at the worst possible moment. So it takes the far corner
## and stays out of the way.
##
## There were two of these, the camera reset and the stick swap, one corner each.
## The stick swap moved to the quick menu in the middle of the bottom edge -- see
## `radial_menu.gd` -- where there is no near side to be on and nothing to place.
## So the camera reset is the last caller; this stays shared rather than folded
## into it because what it knows is the rule, not the button. See `camera_drag.gd`.

## The gap to the screen edge, and the button's box, matching what the corner
## button is authored at.
const MARGIN := 48.0
const BOX := 160.0


## Puts a button in the bottom left or the bottom right, whatever it was
## authored as. Anchors and offsets both, so the move survives a rotation and a
## screen of any size.
static func place(button: Control, on_left: bool) -> void:
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_top = -(MARGIN + BOX)
	button.offset_bottom = -MARGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN

	button.anchor_left = 0.0 if on_left else 1.0
	button.anchor_right = 0.0 if on_left else 1.0

	if on_left:
		button.offset_left = MARGIN
		button.offset_right = MARGIN + BOX
		button.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		button.offset_left = -(MARGIN + BOX)
		button.offset_right = -MARGIN
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
