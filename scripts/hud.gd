extends Control

## In-level readout: the lives as marbles in the top left with the climb towards
## the next one under them, and the clock in a circle at the top centre.
##
## No score. It is not something the player can act on mid-level, and the tally
## on the victory panel is where it actually means something -- see
## `level_complete.gd`.
##
## Also what registers the level with [GameState], so tracking works however the
## level was entered -- from the menus, or straight from the editor. The clock
## starts itself from there; this used to watch the stick for the first steer and
## start it then.
##
## And when the ball goes over the edge, this is what asks for the level back:
## the fall is watched by the camera, and the tap that ends it is taken here.

const MARBLE_MATERIAL := preload("res://materials/ui/life_marble.tres")

## How big one life is, and how far apart they sit. The step is smaller than the
## marble on purpose: that difference is the overlap.
const MARBLE_SIZE := 84.0
const MARBLE_STEP := 58.0

## How long a marble takes to pop in when a life is won, or shrink away when one
## is lost. Short enough not to lie about how many lives are left.
const MARBLE_POP := 0.22

@onready var _time_label: Label = %TimeValue
@onready var _next_life_label: Label = %NextLifeValue
@onready var _lives_box: Control = %Lives
@onready var _unlimited: Label = %Unlimited
@onready var _next_life_row: Control = %NextLifeRow
@onready var _fall_prompt: Label = %FallPrompt

## The marbles on screen, left to right. Their order in the tree is the reverse
## of this -- see `_add_marble()`.
var _marbles: Array[Control] = []

## Set while the ball is falling and the level is waiting to be taken again.
## What makes a tap mean "again" rather than nothing at all.
var _awaiting_restart := false


func _ready() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		GameState.start_level(scene.scene_file_path)

	GameState.lives_changed.connect(_on_lives_changed)
	GameState.gem_progress_changed.connect(_on_gem_progress_changed)
	GameState.fell_out.connect(_on_fell_out)

	# Seeded by hand as well as connected: starting the level above emitted both
	# of these before there was anything listening.
	_on_lives_changed(GameState.lives)
	_on_gem_progress_changed(GameState.run_gems, GameState.extra_life_target)


func _process(_delta: float) -> void:
	# Polled rather than signalled: it changes every frame anyway. The clock is
	# read on the frame and not the physics tick, because the clock itself counts
	# frames -- a reading taken anywhere else is from a different moment than the
	# one on screen.
	_time_label.text = GameState.format_time(GameState.level_time)


## The ball is gone and the camera is watching it go. All this adds is the line
## saying what to do about it.
func _on_fell_out() -> void:
	_awaiting_restart = true
	_fall_prompt.show()


## The two taps the level itself answers: one that hurries the opening shot along,
## and one that takes the level again after a fall.
##
## Unhandled, so they count anywhere on the screen that nothing else wanted --
## and the stick, the one thing that would have wanted the second, was put away
## when the ball went over the edge.
func _unhandled_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
	if not tapped:
		return

	# A thumb on the screen during the opening shot says the player would rather
	# get on with it. The shot is wound on faster from there -- it still turns the
	# whole way round and still comes down behind the ball, so nobody is dropped
	# into a level they were shown half of.
	if GameState.is_intro_held():
		var camera := get_tree().get_first_node_in_group("camera_rig") as CameraFollow
		if camera != null:
			camera.hurry_intro()
		return

	if not _awaiting_restart:
		return

	# Once. The reload takes a moment to come round, and a second tap in the
	# meantime would ask for another one on top of it.
	_awaiting_restart = false
	_fall_prompt.hide()

	GameState.restart_level()


## Brings the row of marbles to the number of SPARE lives, one at a time, so a
## life won or lost is a marble arriving or leaving rather than the whole row
## being rebuilt.
##
## Spares, not lives: the one being played is not in the row, so what is on
## screen is how many more goes are left after this one. An empty row means you
## are on your last life, which is the moment the row most needs to say
## something -- with the count itself shown, an empty row meant you were already
## dead and had never been seen.
##
## Play mode has no count to show. The marbles and the climb towards another life
## both give way to a single infinity, which is the honest readout: there is
## nothing here to run out of and nothing to earn.
func _on_lives_changed(lives: int) -> void:
	var unlimited := lives < 0

	_unlimited.visible = unlimited
	_lives_box.visible = not unlimited
	_next_life_row.visible = not unlimited

	if unlimited:
		return

	var wanted := maxi(lives - 1, 0)

	while _marbles.size() < wanted:
		_add_marble(_marbles.size())

	while _marbles.size() > wanted:
		_remove_marble()


func _on_gem_progress_changed(collected: int, target: int) -> void:
	_next_life_label.text = "%d / %d" % [collected, target]


func _add_marble(index: int) -> void:
	var marble := ColorRect.new()
	marble.material = MARBLE_MATERIAL
	marble.custom_minimum_size = Vector2(MARBLE_SIZE, MARBLE_SIZE)
	marble.size = Vector2(MARBLE_SIZE, MARBLE_SIZE)
	marble.position = Vector2(index * MARBLE_STEP, 0.0)
	marble.pivot_offset = Vector2(MARBLE_SIZE, MARBLE_SIZE) * 0.5
	marble.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_lives_box.add_child(marble)

	# Pushed to the front of the tree so it draws FIRST, and therefore behind
	# everything already there. Children are drawn in order, so without this the
	# newest marble on the right would sit on top of its neighbour and the row
	# would look like it was stacked the wrong way round.
	_lives_box.move_child(marble, 0)
	_marbles.append(marble)

	marble.scale = Vector2.ZERO
	var pop := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	pop.tween_property(marble, "scale", Vector2.ONE, MARBLE_POP)


func _remove_marble() -> void:
	var marble := _marbles.pop_back() as Control
	if marble == null:
		return

	# Dropped out of the list above before the tween starts, so the count is
	# honest straight away even while the marble is still shrinking.
	var lost := create_tween().set_parallel(true).set_ease(Tween.EASE_IN)
	lost.tween_property(marble, "scale", Vector2.ZERO, MARBLE_POP)
	lost.tween_property(marble, "modulate:a", 0.0, MARBLE_POP)
	lost.chain().tween_callback(marble.queue_free)
