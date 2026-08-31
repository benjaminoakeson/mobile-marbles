extends Node

## Tracks the run -- score, lives, and how long the current level has taken --
## and remembers a best score and best time for every level played, along with
## how far the player has got through each set of levels.
##
## Autoloaded as `GameState`, so menus and levels read the same numbers.

signal score_changed(score: int)
signal lives_changed(lives: int)

## Gems banked, for the shop to draw on.
signal bank_changed(bank: int)

## Gems counted towards the next extra life, and what they have to add up to.
signal gem_progress_changed(collected: int, target: int)

## Out of lives. Handled here by sending the player back to the level list.
signal run_ended

## Fired when the player picks a different marble. The menu's preview listens so
## the marble on the page changes under the picker as it is tapped.
signal marble_skin_changed(skin_id: String)

## A marble has been bought. The shop repaints the tile and the picker gains a
## marble to choose from.
signal owned_skins_changed

## The shop has put fresh stock out.
signal shop_changed

## The stick has been swapped between its gated and free forms mid-level. Carries
## the new setting so a stick already on screen can change under the thumb.
signal stick_gated_changed(gated: bool)

## The player has changed which hand they hold the phone in. Carries the new
## setting, so the buttons in the bottom corners can change sides where they
## stand rather than at the next level.
signal handedness_changed(left_handed: bool)

## Either volume has moved. Carries nothing: there are only two, and whatever is
## listening is going to set them both anyway.
signal audio_levels_changed

## A level has been loaded and is about to be played. What it is worth hearing
## about is which world it belongs to, so the music can match.
signal level_started(level_path: String)

## The run's gems have paid for an extra life.
signal extra_life_earned

## The player has steered for the first time this level, so the clock is now
## running. What the ball waits on before it is allowed to move -- see
## `player.gd`.
signal timing_started

const SAVE_PATH := "user://progress.cfg"

## Lives are handed out per set, not per level: three of them cover all ten
## levels of a chapter. Running out means the set is attempted again.
const STARTING_LIVES := 3

## What a level's gems have to add up to for the first extra life of a run.
const FIRST_EXTRA_LIFE := 250

## How much higher the bar goes each time a life is earned. The count starts
## over from nothing after every life, so the second of a run costs 350 gems on
## top of the first, the third 450 on top of that, and so on.
const EXTRA_LIFE_STEP := 100

# --- The current run ---
var score := 0
var lives := STARTING_LIVES
var level_time := 0.0
var current_level := ""

## Points banked from gems this level, kept apart from the rest of the score so
## an all-gems bonus can be worked out from it.
##
## Reset by every level. The bank below is what keeps them.
var gem_score := 0

## Gems counted towards the next extra life. This one carries from level to
## level, so a run keeps climbing towards a life across the whole set -- but it
## is dropped the moment the player leaves for the menu. See `leave_run()`.
##
## Back to nothing every time a life is earned, so what it holds is always the
## gems found since the last one.
var run_gems := 0

## What `run_gems` has to reach for the next extra life. Raised with each life
## earned, and put back to `FIRST_EXTRA_LIFE` whenever the climb starts over, so
## the further into a run the player is, the dearer a life gets.
var extra_life_target := FIRST_EXTRA_LIFE

## How the current level is being played.
##
## FREE is the level list: any level of an unlocked chapter, on its own, with
## its own three lives. Nothing is unlocked by it.
##
## CHALLENGE is one continuous attempt at a whole set, starting at its first
## level and carrying the same lives all the way through. Finishing it is the
## ONLY thing that unlocks the next chapter; running out of lives part way
## fails the run and unlocks nothing.
enum Mode { FREE, CHALLENGE }

var run_mode := Mode.FREE

## The set the current level belongs to, and its place in that set. Empty for a
## level that is not registered -- see `_enter_set()`.
var run_set := ""
var run_index := 0
var run_world := 0
var run_chapter := ""

## Whether the level just finished beat a best score or a best time. Read by the
## victory panel, which is where that news is worth hearing.
var beat_best := false

## What the level just finished was worth, itemised for the victory panel to
## count up one award at a time. Filled in by the goal ring -- the shape of an
## entry is described on `goal_ring.gd::_award_breakdown()`.
var last_award: Array[Dictionary] = []

# --- Remembered between sessions ---
## Level path -> value.
var best_score := {}
var best_time := {}

## Set id -> the level numbers beaten in it at least once, in whatever order
## they were played. Shown by the menus; nothing is gated on it, since free play
## lets the levels of an unlocked chapter be taken in any order.
var cleared_levels := {}

## Set id -> true once its challenge run has been finished. This is the only
## thing that unlocks anything.
var challenges_done := {}

## Every gem ever collected, banked for good and spent in the shop. A level's
## own gem tally resets with the level; this never does.
var bank := 0

## Which marble the player is wearing, as a `MarbleSkins` id. Purely cosmetic:
## nothing about a level is gated on it. What IS gated is which marbles can be
## worn -- see [member owned_skins].
var marble_skin := MarbleSkins.DEFAULT

## Which marbles have been bought, as a set of `MarbleSkins` ids.
##
## A set rather than a list because the only question ever asked of it is whether
## one particular marble is the player's. The default is in it from the start:
## the game has to open with something on the ball.
var owned_skins := {MarbleSkins.DEFAULT: true}

## How many marbles the shop has out at once.
const SHOP_SLOTS := 3

## And how long it keeps them out, in seconds.
const SHOP_REFRESH_SECONDS := 600

## What the shop currently has out, as `MarbleSkins` ids.
var shop_offer: Array[String] = []

## When it next changes them, as a wall-clock time in seconds since 1970.
##
## Wall clock rather than a timer, and saved, because the wait is meant to run
## while the game is SHUT. A player who closes the game with two minutes left on
## the clock should come back in ten to new stock, not to the same three marbles
## with two minutes still to go.
var shop_refresh_at := 0

## What the stick should be at the START of a level.
##
## Kept apart from [member stick_gated], which is what the stick is right now:
## the swap button moves that one every time it is tapped, and something has to
## remember what the player actually meant. LAST_USED is that memory being taken
## at its word -- carry on with whatever the last level was left on.
enum StickPreference { FREE, GATED, LAST_USED }

## Which of those the player has asked for. LAST_USED to begin with, because a
## player who has never opened the settings has only ever expressed a preference
## by tapping the swap button, and that is exactly what this honours.
var stick_preference := StickPreference.LAST_USED

## Whether the thumbstick steers through its eight-lane gate, or runs free the
## way an analogue stick does.
##
## A control preference rather than a difficulty setting: the two are the same
## physics and the same level, and neither is worth more points. It lives here so
## it is remembered between levels and between sessions, and so the button that
## swaps it does not have to be the thing that owns it.
var stick_gated := true

## Which hand the phone is held in. The stick is dynamic and turns up wherever a
## thumb lands, so this moves only the two buttons in the bottom corners -- and
## those are the whole of it, because a button under the steering thumb is a
## button that gets hit by mistake.
var left_handed := false

## The two mixes, each from silent to as loud as the game was built to be.
##
## They are a SCALE on what `default_bus_layout.tres` sets, not a replacement for
## it: the music is authored eight decibels under the effects, and a player
## pulling both sliders to the top should get the mix as it was meant to sound
## rather than a flat one.
var music_volume := 1.0
var sfx_volume := 1.0

## Dev override: every world and chapter reads as open, whatever has actually
## been finished. Set from the levels page's dev tools and cleared by resetting.
##
## Kept apart from the real records rather than faking them, so the menus go on
## telling the truth about what has been cleared and challenged, and turning it
## off puts everything back exactly where it was.
var dev_unlock_all := false

var _timing := false
var _timer_started := false
var _run_over := false


func _ready() -> void:
	# The trackers have to outlive every scene change, including the one that
	# happens the instant a level is finished.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_progress()


func _process(delta: float) -> void:
	if _timing:
		level_time += delta


## Starts a fresh attempt at a level.
##
## Called once per level load, from the HUD. Replaying the level you just failed
## or finished is a new attempt like any other, so this deliberately does NOT
## skip the reset when the path is unchanged -- doing so carried the last run's
## clock and score straight into the next one.
func start_level(level_path: String) -> void:
	current_level = level_path
	level_time = 0.0
	gem_score = 0
	beat_best = false
	last_award = []
	_run_over = false
	set_score(0)

	# Armed, not running. The clock waits for the player -- see `begin_timing()`.
	_timing = false
	_timer_started = false

	# Before anything on screen has had a chance to read the stick: a level opens
	# on whatever the player asked for, not on whatever the last one ended as.
	_apply_stick_preference()

	_enter_set(level_path)

	# After the set, not before: a fresh attempt puts the climb towards an extra
	# life back to the bottom.
	gem_progress_changed.emit(run_gems, extra_life_target)

	level_started.emit(level_path)


## Works out where the level sits: which set it belongs to, and whether it is
## carrying on a challenge run already under way.
##
## Done from the level's own path rather than handed over by the menu, so a
## level opened straight from the editor lands somewhere sensible too.
func _enter_set(level_path: String) -> void:
	var place := LevelManager.locate(level_path)
	if place.is_empty():
		# Not part of any set -- the scratch test level, or one built but not
		# registered yet. Nothing to unlock, and no run for it to belong to, but
		# it still gets lives so it can be played like anything else.
		run_set = ""
		run_index = 0
		run_world = 0
		run_chapter = ""
		run_mode = Mode.FREE
		_deal_lives()
		return

	var set_id := LevelManager.set_id(place.world, place.chapter)

	# A challenge run keeps its lives, and its climb towards the next extra one,
	# for as long as it is running -- that is what makes it one attempt at the
	# whole set rather than a set of separate levels.
	#
	# Belonging to the run is decided by the SET, not by the level number. An
	# earlier version asked whether this level was the one straight after the
	# last, which quietly broke the moment anything reached a level by another
	# route, and handed out a fresh three lives mid-run.
	#
	# The lives are dealt by `begin_challenge()` when the run starts, so there is
	# nothing to deal here.
	var carries_on: bool = run_mode == Mode.CHALLENGE and set_id == run_set

	if run_mode == Mode.CHALLENGE and not carries_on:
		# A level outside the set the challenge was running in. Whatever that run
		# was, it is not this, so it does not get to bank a challenge on the way
		# past.
		run_mode = Mode.FREE

	run_set = set_id
	run_index = place.index
	run_world = place.world
	run_chapter = place.chapter

	# Free play is every level on its own, with its own three lives.
	if not carries_on:
		_deal_lives()


## Begins a free-play attempt. One level, three lives, nothing riding on it.
## Called by the level list just before it swaps to the level.
func begin_free_play() -> void:
	run_mode = Mode.FREE


## Begins a challenge run at the top of a set. The caller is expected to send
## the player to its first level -- a challenge cannot be joined part way
## through.
##
## The lives are dealt HERE, once, rather than when the first level loads. That
## is what lets every level of the run leave them alone.
func begin_challenge(world: int, chapter: String) -> void:
	run_mode = Mode.CHALLENGE
	run_world = world
	run_chapter = chapter
	run_set = LevelManager.set_id(world, chapter)
	_deal_lives()


## Whether a challenge run is under way, so the game-over screen knows whether
## it is reporting a failed run or just a spent level.
func is_challenge_run() -> bool:
	return run_mode == Mode.CHALLENGE


## Hands out a full set of lives for a fresh attempt, and starts the climb
## towards an extra life over from the bottom.
func _deal_lives() -> void:
	lives = STARTING_LIVES
	_restart_extra_life_climb()
	lives_changed.emit(lives)


## The player has left a level for the menu. Whatever they had built up towards
## the next extra life goes with it: a run is climbed in one sitting.
##
## Called by the menu itself rather than by whatever sent them there, so every
## way back -- the button on the victory panel, a game over, or closing the game
## part way through a level -- lands on the same reset.
##
## The bank is untouched. Those gems are spent, not staked.
func leave_run() -> void:
	# Walking out on a challenge abandons it. Without this the mode would still
	# be set the next time a level loaded, and a single level picked from the
	# list would quietly count as carrying on a run that was already given up.
	run_mode = Mode.FREE

	_restart_extra_life_climb()
	save_progress()


func _restart_extra_life_climb() -> void:
	run_gems = 0
	extra_life_target = FIRST_EXTRA_LIFE
	gem_progress_changed.emit(run_gems, extra_life_target)


## Starts the clock, once. Called the first time the player actually steers, so
## a level is not timed while they are still sizing it up.
func begin_timing() -> void:
	if _timer_started or _run_over:
		return

	_timer_started = true
	_timing = true
	timing_started.emit()


## Whether the clock has been started yet this level.
func is_timing_started() -> bool:
	return _timer_started


func stop_timing() -> void:
	_timing = false


## A gem was picked up. It counts three times over: towards this level's score,
## towards the bank the shop spends, and towards the next extra life.
func collect_gem(points: int) -> void:
	gem_score += points
	add_score(points)

	bank += points
	bank_changed.emit(bank)

	run_gems += points
	_award_extra_life()
	gem_progress_changed.emit(run_gems, extra_life_target)

	# Banked the moment it is picked up, so quitting part way through a level
	# does not cost the player gems they have already collected.
	save_progress()


## Hands out an extra life once the run's gems have reached the bar, then puts
## the count back to nothing with the bar raised.
##
## The gems counted carry from level to level, so the count picks up where the
## last level left it. A set's first extra life comes at 250 gems, the next at
## 350 more, then 450 more -- and a long run may well end before the player has
## found another.
func _award_extra_life() -> void:
	if _run_over:
		return

	if run_gems < extra_life_target:
		return

	lives += 1
	extra_life_target += EXTRA_LIFE_STEP

	# Back to nothing rather than down by the bar: what the counter holds is
	# always the gems found since the last life, which is what it reads as.
	run_gems = 0

	lives_changed.emit(lives)
	extra_life_earned.emit()


## Whether every gem in the level has been taken.
##
## Counted from what is still lying around rather than from a tally gems register
## at startup -- that would depend on whether the gems or the HUD happen to be
## readied first, and would break silently the day someone reorders the scene.
func all_gems_collected() -> bool:
	for gem in get_tree().get_nodes_in_group("gem"):
		if gem.has_method("is_taken") and not gem.is_taken():
			return false
	return true


func add_score(points: int) -> void:
	set_score(score + points)


func set_score(value: int) -> void:
	score = value
	score_changed.emit(score)


## Called when the ball reaches the goal. Banks the run's bests and its place in
## the set, then saves.
##
## The points for clearing are worked out by the goal ring, not here -- what a
## level is worth, and how much a fast run multiplies it, is a property of that
## level rather than of the tracker.
func finish_level(clear_points: int) -> void:
	_timing = false

	add_score(clear_points)

	if current_level.is_empty():
		return

	var beat_score: bool = score > best_score.get(current_level, -1)
	if beat_score:
		best_score[current_level] = score

	var previous_best: float = best_time.get(current_level, INF)
	var beat_time := level_time < previous_best
	if beat_time:
		best_time[current_level] = level_time

	beat_best = beat_score or beat_time

	_bank_progress()
	save_progress()


## Marks the level off, and -- when this was the last level of a challenge run
## -- marks the whole challenge done. That flag is what opens the next
## chapter, so it is the one piece of progress free play can never write.
func _bank_progress() -> void:
	if run_set.is_empty():
		return

	var cleared: Array = cleared_levels.get(run_set, [])
	if not cleared.has(run_index):
		cleared.append(run_index)
		cleared_levels[run_set] = cleared

	if run_mode != Mode.CHALLENGE:
		return

	var length := LevelManager.levels_in(run_world, run_chapter).size()
	if length > 0 and run_index >= length - 1:
		challenges_done[run_set] = true


## Called when the ball falls off the stage.
func lose_life() -> void:
	# Once the run is over it stays over. A ball still tumbling behind the
	# game-over screen would otherwise keep spending lives it does not have, and
	# stack up a fresh game-over screen for each one.
	if _run_over:
		return

	lives -= 1
	lives_changed.emit(lives)

	if lives <= 0:
		# Lives stay at zero while the game-over screen is up, so the HUD behind
		# it reads honestly. They are handed back when the player leaves, in
		# `reset_run()`.
		_run_over = true
		_timing = false
		save_progress()
		run_ended.emit()
		_show_game_over()
		return

	save_progress()


## Puts the player back on their feet after a game over.
##
## Progress is left alone. There is nothing to take away: a failed challenge
## simply never wrote its done flag, and free play was never risking anything in
## the first place.
func reset_run() -> void:
	_run_over = false
	run_mode = Mode.FREE
	_deal_lives()
	save_progress()


## Takes the same challenge on again from the top of its set, and hands back the
## level to load. Empty if there is nothing to go back to.
func restart_challenge() -> String:
	var first := LevelManager.level_at(run_world, run_chapter, 0)
	if first.is_empty():
		return ""

	_run_over = false
	run_mode = Mode.CHALLENGE

	# Dealt here for the same reason as `begin_challenge()`: loading the first
	# level will not do it, because that level belongs to the run.
	_deal_lives()

	return first


func _show_game_over() -> void:
	var scene := load(LevelManager.GAME_OVER) as PackedScene
	if scene == null:
		push_error("GameState: could not load '%s'" % LevelManager.GAME_OVER)
		return

	var current := get_tree().current_scene
	if current != null:
		current.add_child(scene.instantiate())


# --- Progress through the sets ---

## How many of a set's levels have been beaten, in any order and either mode.
## For the menus to show; nothing is gated on it.
func cleared_in(world: int, chapter: String) -> int:
	var cleared: Array = cleared_levels.get(LevelManager.set_id(world, chapter), [])
	return cleared.size()


## Whether one level has been beaten at least once.
func is_level_cleared(world: int, chapter: String, index: int) -> bool:
	var cleared: Array = cleared_levels.get(LevelManager.set_id(world, chapter), [])
	return cleared.has(index)


## Whether this set's challenge run has been finished -- the whole set in one
## attempt without running out of lives.
##
## A set with nothing built for it never counts, so an empty chapter cannot
## unlock the one after it.
func is_challenge_complete(world: int, chapter: String) -> bool:
	if LevelManager.levels_in(world, chapter).is_empty():
		return false

	return challenges_done.get(LevelManager.set_id(world, chapter), false)


## Whether a chapter can be played at all. The easiest one opens as soon as
## its world does; every one after it waits on the CHALLENGE of the chapter
## before it, which is the only thing that unlocks anything.
func is_set_unlocked(world: int, chapter: String) -> bool:
	if dev_unlock_all:
		return true

	# Counted among the chapters this world actually HAS. Waiting on a chapter
	# that was planned but never built would lock the rest of the world behind a
	# challenge nobody can run.
	var built := LevelManager.built_chapters(world)
	var step := built.find(chapter)
	if step > 0:
		return is_challenge_complete(world, built[step - 1])

	return is_world_unlocked(world)


## Whether a level can be opened from the list. Once a chapter is unlocked
## every level in it is, in any order -- the run that has to be done in order is
## the challenge, and that one starts itself at the top.
func is_level_unlocked(world: int, chapter: String, index: int) -> bool:
	if LevelManager.level_at(world, chapter, index).is_empty():
		return false

	return is_set_unlocked(world, chapter)


## Whether a challenge run can be started: the chapter is open and there is
## something in it to run.
func can_start_challenge(world: int, chapter: String) -> bool:
	if LevelManager.levels_in(world, chapter).is_empty():
		return false

	return is_set_unlocked(world, chapter)


## World 1 is always open. Every world after it waits on the whole of the world
## before it -- every chapter's challenge finished. A chapter with no
## levels in it never counts as done, so this stays shut until a world is
## actually built out.
func is_world_unlocked(world: int) -> bool:
	if dev_unlock_all or world <= 1:
		return true

	# Every chapter the world before this one actually has. A world with nothing
	# in it has no challenges to finish, so it never opens the next -- which is
	# what stops the whole game unlocking itself down an unbuilt chain.
	var built := LevelManager.built_chapters(world - 1)
	if built.is_empty():
		return false

	for chapter in built:
		if not is_challenge_complete(world - 1, chapter):
			return false

	return true


func best_time_for(level_path: String) -> float:
	return best_time.get(level_path, INF)


func best_score_for(level_path: String) -> int:
	return best_score.get(level_path, 0)


## Minutes and seconds, or just seconds under a minute, down to the hundredth.
## Used by the HUD and the menus so a time always reads the same way.
##
## Only the display is rounded. `level_time` and every best time kept in
## `best_time` are full-precision floats, so two runs a millisecond apart are
## still ranked apart even where they read the same.
static func format_time(seconds: float) -> String:
	if is_inf(seconds):
		return "--"

	# Rounded BEFORE the minute is decided. Asking the raw value whether it is
	# under a minute, then rounding it, prints a time a hair short of the minute
	# as "60.00s" instead of turning it over to "1:00.00".
	var rounded := snappedf(seconds, 0.01)

	if rounded < 60.0:
		return "%.2fs" % rounded

	return "%d:%05.2f" % [int(rounded) / 60, fmod(rounded, 60.0)]


## A gem count with its thousands split up, so a full bank stays readable.
static func format_gems(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""

	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)

	grouped = digits + grouped
	return "-" + grouped if value < 0 else grouped


func owns_skin(skin_id: String) -> bool:
	return owned_skins.has(MarbleSkins.resolve(skin_id))


## Buys one, and says whether it went through.
##
## Everything it can refuse is checked here rather than trusted to the shop:
## a marble already owned, and one that cannot be afforded. The shop greys those
## tiles out anyway, but a price is the sort of thing that must be enforced where
## the gems actually live.
func buy_skin(skin_id: String) -> bool:
	var id := MarbleSkins.resolve(skin_id)
	if owns_skin(id):
		return false

	var price := MarbleSkins.price_for(id)
	if price > bank:
		return false

	bank -= price
	owned_skins[id] = true

	bank_changed.emit(bank)
	owned_skins_changed.emit()

	# Straight to disk. Gems spent and a marble gained is exactly the kind of
	# thing a player would be furious to lose to a crash.
	save_progress()
	return true


## The marbles the shop has out.
##
## The restock happens HERE, when the shelf is looked at, rather than on a timer
## running in the shop page. A timer only runs while the game does, and the whole
## point of the ten minutes is that it passes while the game is shut.
func shop_skins() -> Array[String]:
	if shop_offer.is_empty() or _now() >= shop_refresh_at:
		_restock_shop()

	return shop_offer


## How long the current stock has left, in seconds.
func shop_seconds_left() -> int:
	return maxi(shop_refresh_at - _now(), 0)


func _restock_shop() -> void:
	shop_offer = _pick_stock()
	shop_refresh_at = _now() + SHOP_REFRESH_SECONDS

	shop_changed.emit()
	save_progress()


## Three marbles the player does not already own.
##
## One of each kind first, so there is always something affordable on the shelf
## beside the things that are not -- a shop that rolled three animated marbles
## would be showing a player with eight hundred gems nothing they could buy.
## Then whatever is left over, wherever it comes from, for the case where a kind
## has been bought out.
func _pick_stock() -> Array[String]:
	var picked: Array[String] = []

	for family: String in MarbleSkins.FAMILIES:
		var choices := MarbleSkins.ids().filter(func(id: String) -> bool:
			return MarbleSkins.family_for(id) == family and not owns_skin(id))

		if not choices.is_empty():
			picked.append(choices.pick_random())

		if picked.size() == SHOP_SLOTS:
			return picked

	var rest := MarbleSkins.ids().filter(func(id: String) -> bool:
		return not owns_skin(id) and not picked.has(id))
	rest.shuffle()

	while picked.size() < SHOP_SLOTS and not rest.is_empty():
		picked.append(rest.pop_back())

	return picked


## The wall clock, in whole seconds. The shop is the only thing in the game that
## cares what time it is rather than how long something took.
func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Picks a marble. Saved straight away: a skin chosen and then never followed by
## a finished level would otherwise be forgotten on quit, and picking one is the
## sort of thing a player expects to stick the moment they do it.
func select_marble_skin(skin_id: String) -> void:
	var resolved := MarbleSkins.resolve(skin_id)
	if resolved == marble_skin:
		return

	marble_skin = resolved
	marble_skin_changed.emit(marble_skin)
	save_progress()


## Swaps the stick between gated and free, and says so at once: the swap is meant
## to be felt in the same roll it is asked for, not at the next level.
func toggle_stick_gate() -> void:
	set_stick_gated(not stick_gated)


func set_stick_gated(gated: bool) -> void:
	if gated == stick_gated:
		return

	stick_gated = gated
	stick_gated_changed.emit(stick_gated)

	# Saved on the spot, for the same reason picking a marble is: it is a setting
	# the player expects to stick from the moment they touch it, and a session
	# that ends in a quit rather than a finished level would otherwise lose it.
	save_progress()


## Puts the stick back to what the player asked levels to start on. LAST_USED
## asks for nothing, which is the point of it.
func _apply_stick_preference() -> void:
	match stick_preference:
		StickPreference.FREE:
			_set_stick_gated_quietly(false)
		StickPreference.GATED:
			_set_stick_gated_quietly(true)


## Moves the stick without writing to disk. A level opening is not the player
## changing their mind -- the preference is the record, and `stick_gated` is only
## ever the note of where the last swap left it.
func _set_stick_gated_quietly(gated: bool) -> void:
	if gated == stick_gated:
		return

	stick_gated = gated
	stick_gated_changed.emit(stick_gated)


## Takes a [enum StickPreference] value. Typed as a plain int so the settings
## sheet can hand over a button's place in its row without casting.
func set_stick_preference(preference: int) -> void:
	if preference == stick_preference:
		return

	stick_preference = preference

	# Asked for and answered at once: a player picking "free" in the settings
	# means the stick under their thumb, not the one two levels from now.
	_apply_stick_preference()
	save_progress()


func set_left_handed(left: bool) -> void:
	if left == left_handed:
		return

	left_handed = left
	handedness_changed.emit(left_handed)
	save_progress()


func set_music_volume(level: float) -> void:
	_set_volumes(level, sfx_volume)


func set_sfx_volume(level: float) -> void:
	_set_volumes(music_volume, level)


func _set_volumes(music: float, sfx: float) -> void:
	var wanted_music := clampf(music, 0.0, 1.0)
	var wanted_sfx := clampf(sfx, 0.0, 1.0)
	if is_equal_approx(wanted_music, music_volume) and is_equal_approx(wanted_sfx, sfx_volume):
		return

	music_volume = wanted_music
	sfx_volume = wanted_sfx
	audio_levels_changed.emit()

	# Not saved here. A slider being dragged is dozens of these a second, and the
	# panel writes it once when the finger comes off -- see `ProfilePanel`.


func save_progress() -> void:
	var file := ConfigFile.new()
	file.set_value("run", "lives", lives)
	file.set_value("run", "extra_life_target", extra_life_target)
	file.set_value("bank", "gems", bank)
	file.set_value("best", "score", best_score)
	file.set_value("best", "time", best_time)
	file.set_value("progress", "cleared", cleared_levels)
	file.set_value("progress", "challenges", challenges_done)
	file.set_value("marble", "skin", marble_skin)
	file.set_value("marble", "owned", owned_skins.keys())
	file.set_value("shop", "offer", shop_offer)
	file.set_value("shop", "refresh_at", shop_refresh_at)
	file.set_value("controls", "stick_gated", stick_gated)
	file.set_value("controls", "stick_preference", stick_preference)
	file.set_value("controls", "left_handed", left_handed)
	file.set_value("audio", "music", music_volume)
	file.set_value("audio", "sfx", sfx_volume)
	file.set_value("dev", "unlock_all", dev_unlock_all)

	var result := file.save(SAVE_PATH)
	if result != OK:
		push_error("GameState: could not save to '%s' (error %d)" % [SAVE_PATH, result])


func load_progress() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		# No save yet, which is the normal state on a first run.
		return

	lives = file.get_value("run", "lives", STARTING_LIVES)
	extra_life_target = file.get_value("run", "extra_life_target", FIRST_EXTRA_LIFE)
	if lives <= 0:
		# Saved part way through a game over. Start the next session playable.
		lives = STARTING_LIVES
	bank = file.get_value("bank", "gems", 0)
	best_score = file.get_value("best", "score", {})
	best_time = file.get_value("best", "time", {})
	cleared_levels = file.get_value("progress", "cleared", {})
	challenges_done = file.get_value("progress", "challenges", {})
	# Resolved on the way in, so a save naming a skin that no longer exists comes
	# back as the default instead of as a marble with no material at all.
	marble_skin = MarbleSkins.resolve(file.get_value("marble", "skin", MarbleSkins.DEFAULT))

	# Skins the catalogue no longer knows about are dropped on the way in, the
	# same as the worn one is resolved. The marble being worn is always owned,
	# whatever the save says: a save written before the shop existed has a skin
	# in it that was picked freely, and taking it off the player now would be a
	# theft they never agreed to.
	owned_skins = {MarbleSkins.DEFAULT: true, marble_skin: true}
	for id: String in file.get_value("marble", "owned", []) as Array:
		if MarbleSkins.has(id):
			owned_skins[id] = true

	# Only marbles the catalogue no longer knows are dropped. One already bought
	# stays where it is: the three on show are what this stretch of ten minutes
	# is offering, and taking a sold tile away would leave a hole in the shelf.
	shop_offer.assign((file.get_value("shop", "offer", []) as Array).filter(
			func(id: String) -> bool: return MarbleSkins.has(id)))
	shop_refresh_at = file.get_value("shop", "refresh_at", 0)
	stick_gated = file.get_value("controls", "stick_gated", true)
	stick_preference = file.get_value("controls", "stick_preference", StickPreference.LAST_USED)
	left_handed = file.get_value("controls", "left_handed", false)
	music_volume = clampf(file.get_value("audio", "music", 1.0), 0.0, 1.0)
	sfx_volume = clampf(file.get_value("audio", "sfx", 1.0), 0.0, 1.0)
	dev_unlock_all = file.get_value("dev", "unlock_all", false)

	# Saves written before challenge runs existed kept one running count
	# per set instead. Carried over so nobody is sent back to the start.
	var legacy: Dictionary = file.get_value("progress", "sets", {})
	if not legacy.is_empty() and cleared_levels.is_empty():
		_adopt_legacy_progress(legacy)
	lives_changed.emit(lives)
	bank_changed.emit(bank)


## Turns the old "how many cleared, in order" count into the level list the
## menus now read, and credits the challenge to any set that count had finished.
func _adopt_legacy_progress(legacy: Dictionary) -> void:
	for set_id: String in legacy:
		var count := int(legacy[set_id])

		var cleared: Array = []
		for index in count:
			cleared.append(index)
		cleared_levels[set_id] = cleared

		var parts := set_id.split("/", true, 1)
		if parts.size() != 2:
			continue

		var length := LevelManager.levels_in(int(parts[0]), parts[1]).size()
		if length > 0 and count >= length:
			challenges_done[set_id] = true


# --- Dev tools ---
# Driven by the dev popup on the levels page, which only opens in a debug build.

## Wipes the save back to a first run: nothing cleared, no challenges, no best
## times or scores, an empty bank, the marble back to the default one, and the
## dev unlock off again.
##
## Written to disk straight away rather than left for the next save, so quitting
## immediately afterwards cannot resurrect the old progress.
func dev_reset_progress() -> void:
	cleared_levels = {}
	challenges_done = {}
	best_score = {}
	best_time = {}
	bank = 0
	dev_unlock_all = false
	marble_skin = MarbleSkins.DEFAULT
	owned_skins = {MarbleSkins.DEFAULT: true}

	# Cleared rather than rolled again: the next look at the shelf restocks it,
	# and doing it here would put stock out that nobody has asked to see.
	shop_offer.clear()
	shop_refresh_at = 0

	_run_over = false
	run_mode = Mode.FREE
	_deal_lives()

	bank_changed.emit(bank)
	marble_skin_changed.emit(marble_skin)
	owned_skins_changed.emit()
	shop_changed.emit()
	save_progress()


## Opens every world and chapter at once. Nothing is marked as finished --
## see `dev_unlock_all` for why -- so `dev_reset_progress()` is the way back off.
func dev_unlock_everything() -> void:
	dev_unlock_all = true
	save_progress()
