extends Control

## The in-level quick menu: a disc rising out of the bottom edge of the screen.
##
## Only ever the TOP HALF of it is on screen. The box is the whole circle and its
## centre sits on the bottom edge when the menu is open, so the half below the
## edge is off-screen and costs nothing -- which is what makes the maths here
## plain circle maths instead of arc maths.
##
## This script is on the BODY, not on the scene root. The root is anchored to the
## bottom of the screen and never moves; this is what slides up and down inside
## it. Sliding the anchored node instead would mean writing to a position the
## anchors own, and the next layout pass -- a rotation, a resize -- would put it
## straight back.
##
## The disc is small on purpose -- a nub, not a tray. For the whole of a level in
## which the player never touches it, all it is is a sliver at the bottom edge
## with a chevron on it, and that is the state it is tuned for. The buttons do
## not scale with it: they orbit just off its rim at whatever size a thumb needs.
##
## Three stages, and the disc slides between two heights:
##
## - DORMANT: down by half a radius, so a quarter of the circle shows. One arrow
##   on it, pointing up. This is what the player sees for the whole level if they
##   never touch it.
## - OPEN: up to the bottom edge, so half the circle shows. The arrow turns over
##   and the two things worth doing mid-level come up beside it -- swap the
##   stick, and the way out.
## - MENU: the same disc, with retry and exit swung out along an arc on the menu
##   button's own side, exit below retry.
## - TIMEOUT: the clock has run out and there is no level left to play. The arrow,
##   the stick swap and the menu button all go -- there is nothing to collapse
##   into, nothing to steer, and nothing left under the menu button that is not
##   already on screen -- and retry and exit take the two places those last two
##   were sitting in. It cannot be shut. See [method _on_time_ran_out].
##
## Nothing here fades. Every button is hidden by being somewhere rather than by
## an alpha, and where it hides says what it belongs to: the stick and the menu
## button wait under the bottom edge and rise through it, the same trick the disc
## plays, while retry and exit wait folded inside the menu button and grow out of
## it. See [method _raise].
##
## Anything shuts it: the down arrow, one of its own buttons doing its job, or a
## press anywhere else at all. See [method _unhandled_input].
##
## It REPLACES the corner stick-swap button. That button's whole argument was
## that the stick has to be swappable mid-roll without leaving the level, and
## this keeps that -- the swap is two taps from anywhere instead of one, and the
## ball goes on rolling through both of them.
##
## Nothing here pauses the game. A menu that stopped the level would make the
## stick swap useless: the point of swapping is to feel the difference in the
## corner you are already in.

enum Stage {
	DORMANT,
	OPEN,
	MENU,
	TIMEOUT,
}

## Where each button sits: the angle round from straight up, and how far out as a
## fraction of the disc's radius. Positive angles go clockwise, so the stick
## lands left of centre and the way out lands right of it.
##
## Every reach is over 1.0 except the arrow's, because the disc is a HUB rather
## than a tray: it is small enough now that nothing but the arrow fits on it, and
## the rest orbit just off its rim. The inner pair clear it by about five pixels,
## which is what makes the cluster read as one object rather than as buttons
## scattered near a circle.
@export_group("Layout")
@export var arrow_degrees := 0.0
@export var arrow_reach := 0.76
@export var inner_degrees := 55.0
@export var inner_reach := 1.55

## Retry and exit, both on the menu button's side and further out than it, one
## above the other along the same arc. They were symmetrical about the arrow;
## hanging them off the side the menu button is on is what says they belong to
## it.
@export var retry_degrees := 34.0
@export var exit_degrees := 71.0
@export var outer_reach := 2.59

## How big each button's box is. These do NOT scale with the disc: the disc is
## decoration and can be as small as it likes, but a button has to be findable
## under a thumb, and the thumb is the size it is.
@export var arrow_size := 100.0
@export var inner_size := 110.0
@export var outer_size := 96.0

@export_group("Movement")

## How long the disc takes to slide between the two heights.
@export var slide_time := 0.28

## How long a button takes to come up out of the bottom of the screen, and how
## long it takes to drop back under it.
##
## The fall is quicker than the rise, and eased the other way round: things come
## up because something pushed them and land soft, and go down because nothing is
## holding them any more.
@export var rise_time := 0.30
@export var fall_time := 0.20

## The gap between one button leaving and the next. Small -- it is meant to read
## as one movement with a ripple in it, not as a queue.
@export var rise_stagger := 0.06

## How far under the bottom edge a button waits, past the point where the last of
## it has cleared. Slack, so a button is never caught peeping during the wait
## that a stagger puts in front of it.
@export var under_margin := 24.0

## How long the stick glyph takes to pop when the stick is swapped, and how far.
## Carried over from the corner button this replaces: the swap's real answer is
## under the other thumb, where the player is not looking, so the button has to
## say for itself that the tap landed.
@export var swap_pop_time := 0.18
@export var swap_pop_scale := 1.2

@export_group("Look")
@export var disc_colour := Color(0.09019608, 0.10980392, 0.12941177, 0.61176471)
@export var rim_colour := Color(1, 1, 1, 0.10)
@export var rim_thickness := 3.0

@onready var _arrow: Button = %ArrowButton
@onready var _stick: Button = %StickButton
@onready var _menu: Button = %MenuButton
@onready var _retry: Button = %RetryButton
@onready var _exit: Button = %ExitButton
@onready var _arrow_icon: RadialIcon = %ArrowIcon
@onready var _stick_icon: Control = %StickIcon

var _stage := Stage.DORMANT

## Where the disc's centre sits in local coordinates, and how big it is. Taken
## from the box rather than authored twice, so the scene is the one place the
## disc's size is written down.
var _centre := Vector2.ZERO
var _radius := 0.0

## Where the buttons rest once they are out, and where each waits while it is
## not. Both have to be worked out before anything moves -- retry and exit wait
## inside the menu button, so their hiding place is read off its resting place.
var _rest := {}
var _down := {}

## The two that come out of the MENU BUTTON rather than out of the bottom of the
## screen, and are therefore the two that shrink as well as travel. What a button
## comes out of is what it belongs to: these belong to the button that summoned
## them, not to the disc.
var _from_menu: Array[Button] = []

## Whether each button is currently up, so a stage change that does not concern
## it -- OPEN to MENU leaves the stick and the menu button exactly where they
## were -- does not restart a movement that has already finished.
var _up := {}

## The tween carrying each button up or down, one per button, so killing one on
## a fast change of mind does not touch the others.
var _risers := {}

## Set once the level has been finished. Nothing brings the menu back after that.
var _finished := false

var _slide: Tween
var _swap_pop: Tween


func _ready() -> void:
	_centre = size * 0.5
	_radius = minf(size.x, size.y) * 0.5

	_place_buttons()

	_arrow.pressed.connect(_on_arrow_pressed)
	_stick.pressed.connect(_on_stick_pressed)
	_menu.pressed.connect(_on_menu_pressed)
	_retry.pressed.connect(_on_retry_pressed)
	_exit.pressed.connect(_on_exit_pressed)

	Audio.wire_clicks(self)

	# Up only while there is a stick to swap, which is the same rule the corner
	# button followed: the end of a level takes the stick away -- see
	# `Thumbstick.disable()` -- and a quick menu left sitting over the victory
	# panel would be offering a retry for a level that has just been finished.
	var stick := get_tree().get_first_node_in_group("thumbstick") as Control
	if stick == null:
		push_warning("RadialMenu: no Thumbstick in group 'thumbstick'; the menu will never hide")
	else:
		stick.visibility_changed.connect(_follow.bind(stick))
		_follow(stick)

	# The clock running out takes the stick away, which would otherwise take this
	# with it -- and the moment the player most needs a way out of the level is
	# the moment they can no longer play it.
	GameState.time_ran_out.connect(_on_time_ran_out)
	GameState.level_finished.connect(_on_level_finished)

	_apply_stage(false)


## Anything the menu's own buttons did not want shuts it.
##
## Taken as UNHANDLED input, which is the whole trick: a press that landed on one
## of these buttons was consumed by that button before it got here, so this only
## ever sees presses that missed. Nothing has to be told where the menu is or
## what counts as outside it.
##
## The stick reads its touches earlier still, in `_input`, and does not mark them
## handled -- so grabbing the stick to steer both steers AND shuts the menu,
## which is the same answer as tapping anywhere else.
func _unhandled_input(event: InputEvent) -> void:
	# Nothing to shut when it is already shut, and nothing MAY shut it once the
	# clock has run out: the two buttons it is holding are the only way off this
	# screen, so a stray tap must not put them away.
	if _stage == Stage.DORMANT or _stage == Stage.TIMEOUT:
		return

	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
	if tapped:
		_go_to(Stage.DORMANT)


## The disc. Drawn rather than styled: a StyleBoxFlat rounded to a circle would
## have to be told a corner radius that matches the box, in two places that can
## drift apart, and this is one line that cannot.
func _draw() -> void:
	draw_circle(_centre, _radius, disc_colour)
	draw_arc(_centre, _radius - rim_thickness * 0.5, 0.0, TAU, 96, rim_colour, rim_thickness, true)


# --- Layout ---

## Every button put where it belongs, once. Positions are worked out from the
## angles above rather than authored, so moving one is a number here and not a
## drag in the editor that the others have to be matched to by eye.
func _place_buttons() -> void:
	_rest[_arrow] = _seat(_arrow, arrow_degrees, arrow_reach, arrow_size)
	_rest[_stick] = _seat(_stick, -inner_degrees, inner_reach, inner_size)
	_rest[_menu] = _seat(_menu, inner_degrees, inner_reach, inner_size)
	_rest[_retry] = _seat(_retry, retry_degrees, outer_reach, outer_size)
	_rest[_exit] = _seat(_exit, exit_degrees, outer_reach, outer_size)

	# Second pass, not folded into the first: two of these hide inside the menu
	# button, and that is read off where the menu button came to rest.
	_from_menu = [_retry, _exit]

	_down[_stick] = _under(_stick)
	_down[_menu] = _under(_menu)
	_down[_retry] = _into(_menu, _retry)
	_down[_exit] = _into(_menu, _exit)

	for button: Button in _rest:
		button.position = _rest[button]


## Sizes one button and hands back the top-left corner it rests at.
##
## The angle is measured round from straight up so that the numbers above read
## the way the menu looks -- 0 is the apex, and the sign is which side of it.
func _seat(button: Button, degrees: float, reach: float, box: float) -> Vector2:
	button.size = Vector2.ONE * box
	button.pivot_offset = Vector2.ONE * box * 0.5

	var angle := deg_to_rad(degrees)
	var out := Vector2(sin(angle), -cos(angle)) * (_radius * reach)
	return _centre + out - Vector2.ONE * box * 0.5


# --- Stages ---

func _on_arrow_pressed() -> void:
	# From anywhere open, the arrow shuts the whole thing -- including the retry
	# and exit pair. One press to put it all away is what the down arrow means.
	_go_to(Stage.DORMANT if _stage != Stage.DORMANT else Stage.OPEN)


func _on_menu_pressed() -> void:
	# A toggle, so the button that popped the pair out is also what puts them
	# back. Pressing it again to shut them is the first thing anyone tries.
	_go_to(Stage.OPEN if _stage == Stage.MENU else Stage.MENU)


func _go_to(stage: Stage) -> void:
	if stage == _stage:
		return

	_stage = stage
	_apply_stage(true)


## The whole of what a stage looks like, in one place: how far down the disc sits,
## which way the arrow points, and what is on screen.
##
## `animate` is false for the first call, which happens before the player has
## seen anything -- there is nothing to animate FROM.
func _apply_stage(animate: bool) -> void:
	if _stage == Stage.TIMEOUT:
		_apply_timeout(animate)
		return

	var dormant := _stage == Stage.DORMANT

	# Down by half a radius leaves a quarter of the circle showing; up on the
	# bottom edge leaves half. Those two are the whole of the movement.
	_slide_to(_radius * 0.5 if dormant else 0.0, animate)

	_arrow_icon.kind = RadialIcon.Kind.ARROW_UP if dormant else RadialIcon.Kind.ARROW_DOWN

	# Staggered in the order they sit along the arc, out from the middle: the
	# stick and the menu button flank the arrow, and retry and exit run on round
	# from the menu button. Both pairs use the same two delays, so the pair that
	# comes out of the menu button ripples the way the disc's own pair did, even
	# though the two pairs come from different places.
	_raise(_stick, not dormant, animate, 0.0)
	_raise(_menu, not dormant, animate, rise_stagger)

	var branched := _stage == Stage.MENU
	_raise(_retry, branched, animate, 0.0)
	_raise(_exit, branched, animate, rise_stagger)


## Zero is open -- the body sitting square on the anchored root, disc centre on
## the bottom edge of the screen. Anything more is how far it has dropped.
func _slide_to(down: float, animate: bool) -> void:
	# The whole body moves, so nothing inside it has to know the menu is open:
	# every button stays at the local position `_place_buttons()` gave it.
	var to := Vector2(0.0, down)

	if not animate:
		position = to
		return

	if _slide != null and _slide.is_valid():
		_slide.kill()

	_slide = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide.tween_property(self, "position", to, slide_time)


## Where a disc button waits: straight down from where it belongs, far enough
## under that the last of it has cleared the bottom of the screen.
##
## `_centre.y` IS the bottom edge in local coordinates. The disc's middle sits on
## that edge -- which is the same fact that leaves only the top half of it
## showing -- so the number that hides the disc's other half hides these too, and
## there is no screen height to look up.
func _under(button: Button) -> Vector2:
	return Vector2(_rest[button].x, _centre.y + under_margin)


## Where a menu button's button waits: dead centre of the button that summons it.
##
## Squared off the two boxes rather than assumed equal, because they are not --
## the outer pair are smaller than the button they come out of.
func _into(host: Button, button: Button) -> Vector2:
	return _rest[host] + (host.size - button.size) * 0.5


## One button arriving, or going back where it came from.
##
## There are two answers to "where from", and which one a button gets is which
## thing it belongs to. The stick and the menu button belong to the DISC, and the
## disc comes up through the bottom edge of the screen -- so they wait under that
## edge and rise through it the same way. Retry and exit belong to the MENU
## BUTTON, so they wait folded into the middle of it and grow out of it.
##
## Only the second pair scale. Travelling out from under a screen edge needs no
## scaling -- the edge does the hiding -- but sliding out from behind a button at
## full size would read as something hiding behind it rather than as something it
## contained, so those shrink to nothing as well as travel.
##
## Nothing here knows about stages. It is told whether the button belongs up, and
## the bookkeeping of what is already up is what keeps OPEN -> MENU from
## restarting the two buttons that were not asked to move.
func _raise(button: Button, out: bool, animate: bool, delay: float) -> void:
	if _up.get(button) == out:
		return

	_up[button] = out

	var running: Tween = _risers.get(button)
	if running != null and running.is_valid():
		running.kill()

	var folds := button in _from_menu
	var away: Vector2 = _down[button]

	if not animate:
		button.visible = out
		button.position = _rest[button] if out else away
		button.scale = Vector2.ONE if out or not folds else Vector2.ZERO
		return

	var rise := create_tween()

	if delay > 0.0:
		rise.tween_interval(delay)

	if out:
		# Put where it comes from and shown BEFORE the wait, not after it: there
		# is nothing to see at either hiding place -- under the edge, or at no
		# size at all -- and a `show()` on the far side of the delay is one more
		# thing that has to happen in the right order.
		button.position = away
		button.scale = Vector2.ZERO if folds else Vector2.ONE
		button.show()

		rise.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		rise.tween_property(button, "position", _rest[button], rise_time)
		if folds:
			rise.parallel().tween_property(button, "scale", Vector2.ONE, rise_time)
	else:
		rise.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		rise.tween_property(button, "position", away, fall_time)
		if folds:
			rise.parallel().tween_property(button, "scale", Vector2.ZERO, fall_time)

		# Hidden only once it is down, or it would blink out mid-fall. Chained
		# rather than timed, so a change of mind that kills the tween takes this
		# with it and cannot hide a button that is on its way back up.
		rise.chain().tween_callback(button.hide)

	_risers[button] = rise


# --- What the buttons do ---

func _on_stick_pressed() -> void:
	GameState.toggle_stick_gate()

	if _swap_pop != null and _swap_pop.is_valid():
		_swap_pop.kill()

	_stick_icon.pivot_offset = _stick_icon.size * 0.5

	_swap_pop = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_swap_pop.tween_property(_stick_icon, "scale", Vector2.ONE * swap_pop_scale, swap_pop_time * 0.4)
	_swap_pop.tween_property(_stick_icon, "scale", Vector2.ONE, swap_pop_time * 0.6)


## The level from the top, at the price of a fall. `restart_level()` is the path
## the alive zone takes when the ball goes over the edge, and walking back to the
## start on purpose costs the same as being put there.
func _on_retry_pressed() -> void:
	_lock()
	GameState.restart_level()


## Out to the menu. The run is dropped by the menu itself on the way in -- see
## `GameState.leave_run()`, which every way out of a level lands on -- so there
## is nothing to tear down here.
func _on_exit_pressed() -> void:
	_lock()

	if get_tree().change_scene_to_file(LevelManager.MENU) != OK:
		push_error("RadialMenu: could not load '%s'" % LevelManager.MENU)
		_unlock()


## Both ways out go dead together. They sit next to each other and a fat finger
## can land on the pair before the scene swaps.
func _lock() -> void:
	_retry.disabled = true
	_exit.disabled = true


func _unlock() -> void:
	_retry.disabled = false
	_exit.disabled = false


## The clock has run out. The menu stops being a menu and becomes the only thing
## on screen the player can still press.
##
## Retry and exit move to the two seats the stick swap and the menu button were
## in -- the inner ring, flanking the disc, at the inner size. They were hanging
## off the side of a button that is about to be gone, and two big buttons either
## side of the disc is what a screen with exactly two choices on it should look
## like.
##
## Moving them also changes where they come FROM: nothing summons them now, so
## they rise out of the bottom edge like the pair they are replacing rather than
## growing out of a button that is not there. Emptying `_from_menu` is the whole
## of saying that -- see [method _raise].
func _on_time_ran_out() -> void:
	_rest[_retry] = _seat(_retry, -inner_degrees, inner_reach, inner_size)
	_rest[_exit] = _seat(_exit, inner_degrees, inner_reach, inner_size)

	_from_menu = []
	_down[_retry] = _under(_retry)
	_down[_exit] = _under(_exit)

	# Forgotten rather than left standing, so a pair already out on the arc is
	# raised again into its new seat instead of being taken for already arrived.
	_up.erase(_retry)
	_up.erase(_exit)

	_go_to(Stage.TIMEOUT)


## What a timed-out menu looks like: the disc up, the arrow and the two buttons
## it opened onto gone, and the two ways out standing where they were.
func _apply_timeout(animate: bool) -> void:
	_slide_to(0.0, animate)

	# Hidden outright rather than lowered. It is not managed by `_raise()` -- it
	# is the one button that is normally always up -- and there is nothing left
	# for it to collapse the menu into.
	_arrow.hide()

	_raise(_stick, false, animate, 0.0)
	_raise(_menu, false, animate, 0.0)
	_raise(_retry, true, animate, 0.0)
	_raise(_exit, true, animate, rise_stagger)


## The level was finished, which after a timeout means the ball rolled in on its
## own. Everything here gets off the screen ahead of the victory panel.
func _on_level_finished() -> void:
	_finished = true
	hide()


func _follow(stick: Control) -> void:
	# The level is over; nothing brings this back.
	if _finished:
		return

	# The clock running out hides the stick, and normally that would hide this
	# with it. Read off GameState rather than off the stage, because the flag is
	# set before the signal goes out and the stage may not have turned over yet
	# -- whichever of us hears about the timeout first, this answers the same.
	visible = stick.is_visible_in_tree() or GameState.is_timed_out()

	# Put away rather than left open behind whatever took the stick off screen,
	# so it is shut again if the level comes back.
	if not visible and _stage != Stage.DORMANT:
		_stage = Stage.DORMANT
		_apply_stage(false)
