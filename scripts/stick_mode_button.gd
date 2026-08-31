extends Button

## The stick-swap button, in the corner opposite the camera reset.
##
## Which corner that is, is the player's: a right-hander steers with the right
## thumb, so this sits under the left. See [HandCorner].
##
## It is on screen DURING PLAY on purpose. Which stick suits a player is not
## something they can answer from a menu -- it is answered by taking the same
## corner twice, once each way, and the only way to do that is to be able to swap
## without leaving the level. So the swap lands on the thumb already holding the
## stick, mid-roll, and the ball goes on rolling through it.
##
## The button owns none of the setting: it asks [GameState] to turn it over and
## everything that cares hears about it from there.

## How long the glyph takes to pop when the stick is swapped, and how far.
@export var pop_time := 0.18
@export var pop_scale := 1.2

@onready var _glyph: Control = $Icon

var _pop: Tween


func _ready() -> void:
	pressed.connect(_on_pressed)
	Audio.wire_clicks(self)

	# Opposite the steering thumb: left corner for a right-hander.
	GameState.handedness_changed.connect(_on_handedness_changed)
	_on_handedness_changed(GameState.left_handed)

	# Up only while there is a stick to swap. The end of a level takes the stick
	# away -- see `Thumbstick.disable()` -- and this goes with it rather than
	# being left sitting over the victory panel. Followed rather than switched
	# off from those places directly, so nothing else has to know this exists.
	var stick := get_tree().get_first_node_in_group("thumbstick") as Control
	if stick == null:
		push_warning("StickModeButton: no Thumbstick in group 'thumbstick'; the swap will do nothing visible")
		return

	stick.visibility_changed.connect(_follow.bind(stick))
	_follow(stick)


func _on_handedness_changed(left_handed: bool) -> void:
	HandCorner.place(self, not left_handed)


func _follow(stick: Control) -> void:
	visible = stick.is_visible_in_tree()


func _on_pressed() -> void:
	GameState.toggle_stick_gate()

	# The glyph has already redrawn itself into the other track by now, so the
	# pop is what says the tap landed. Worth having: the swap's real answer is
	# under the other thumb, where the player is not looking.
	if _pop != null and _pop.is_valid():
		_pop.kill()

	# Set here rather than at load: the box is laid out by the time anything can
	# be pressed, and a pivot taken before that would be half a button out.
	_glyph.pivot_offset = _glyph.size * 0.5

	_pop = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_pop.tween_property(_glyph, "scale", Vector2.ONE * pop_scale, pop_time * 0.4)
	_pop.tween_property(_glyph, "scale", Vector2.ONE, pop_time * 0.6)
