extends Control

## In-level readout: the lives as marbles in the top left with the climb towards
## the next one under them, and the clock in a circle at the top centre.
##
## No score. It is not something the player can act on mid-level, and the tally
## on the victory panel is where it actually means something -- see
## `level_complete.gd`.
##
## Also what starts the level's clock, so tracking works however the level was
## entered -- from the menus, or straight from the editor.

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
@onready var _stick: Thumbstick = get_tree().get_first_node_in_group("thumbstick") as Thumbstick

## The marbles on screen, left to right. Their order in the tree is the reverse
## of this -- see `_add_marble()`.
var _marbles: Array[Control] = []


func _ready() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		GameState.start_level(scene.scene_file_path)

	GameState.lives_changed.connect(_on_lives_changed)
	GameState.gem_progress_changed.connect(_on_gem_progress_changed)

	# Seeded by hand as well as connected: starting the level above emitted both
	# of these before there was anything listening.
	_on_lives_changed(GameState.lives)
	_on_gem_progress_changed(GameState.run_gems, GameState.extra_life_target)


func _process(_delta: float) -> void:
	# Both ends of the clock are read on the frame, not the physics tick: the
	# start here, the stop in `goal_ring.gd`. The clock itself counts frames, so
	# a check that runs anywhere else banks a reading from a different moment
	# than the one on screen. The tilt and the ball stay on physics.
	#
	# The clock starts the moment the stick actually asks for movement -- not on
	# load, and not on a touch that never leaves the dead zone.
	if _stick != null and _stick.value != Vector2.ZERO:
		GameState.begin_timing()

	# Polled rather than signalled: it changes every frame anyway.
	_time_label.text = GameState.format_time(GameState.level_time)


## Brings the row of marbles to the number of SPARE lives, one at a time, so a
## life won or lost is a marble arriving or leaving rather than the whole row
## being rebuilt.
##
## Spares, not lives: the one being played is not in the row, so what is on
## screen is how many more goes are left after this one. An empty row means you
## are on your last life, which is the moment the row most needs to say
## something -- with the count itself shown, an empty row meant you were already
## dead and had never been seen.
func _on_lives_changed(lives: int) -> void:
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
