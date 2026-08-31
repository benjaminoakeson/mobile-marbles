class_name HandCorner

## Where the two in-level corner buttons sit, and the one place that decides it.
##
## The stick is dynamic -- it appears under whichever thumb lands in its box --
## so handedness is not about the stick at all. It is about the two buttons: a
## button on the same side as the steering thumb is a button caught by the heel
## of it, mid-corner, at the worst possible moment. So they swap sides together
## and stay out of the way.
##
## Both buttons are the same size in the same corner and differ only in which
## one, which is why this is shared rather than written twice with one sign
## changed. See `stick_mode_button.gd` and `camera_drag.gd`.

## The gap to the screen edge, and the button's box, matching what the two
## buttons are authored at.
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
