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

## The double-gems purchase went through. The shop tile listens, so the thing
## just bought stops offering itself for sale the moment it is owned.
signal double_gems_changed(active: bool)

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

## An award has been won. Carries nothing: it is won mid-level, where there is
## nothing to show for it, and the menu reads the queue when it next opens. See
## [member awards_unclaimed].
signal award_earned

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

## The ball has left the world and the level is waiting to be taken again. What
## the HUD puts its prompt up on -- the tap that answers it calls
## [method restart_level].
##
## Only ever emitted for a fall the run SURVIVES. A fall that spends the last
## life is a game over, and that screen owns what happens next.
signal fell_out

## The clock has run out. The level is NOT over: control goes, but the ball keeps
## whatever it was carrying, and a goal reached on that momentum still counts.
##
## What listens is what has to stand down -- the steering, the stick -- and what
## has to appear: the words saying so, and the two ways out. See
## [method _time_out].
signal time_ran_out

## The level has been finished, however it was reached. Emitted before the crowns
## and the bests are worked out, because what listens to this is the in-level
## furniture that has to get off the screen before the victory panel lands on it.
signal level_finished

## A level already finished has been banked again, because the ball was still
## rolling and found more. The score, the awards it is made of and the crowns
## have all just been worked out afresh -- see [method rebank_level].
##
## What listens is the victory panel, which is very likely already on screen by
## then: it goes up on its own delay rather than waiting for the ball to stop, so
## this is how it hears that the level it is showing is worth more than it said.
signal level_rebanked

## The dev tools have rewritten progress wholesale -- everything opened, or
## everything wiped. For whatever is on screen at the time to rebuild itself.
##
## Ordinary play never emits this: progress moves one level at a time, and the
## menus read it fresh whenever they come back into view. This is for the two
## buttons that move it while a page is being looked at.
signal progress_changed

## The level's clock has started, and with it the level itself: the ball is let
## go on this, and the HUD's readouts start meaning something.
##
## It comes either at the end of the camera's opening fly-round or, on a level
## with no camera to fly it, on the frame after the level loads.
signal timing_started

const SAVE_PATH := "user://progress.cfg"

## Lives are handed out per set, not per level: three of them cover all ten
## levels of a chapter. Running out means the set is attempted again.
const STARTING_LIVES := 3

## What `lives` holds in play mode. Negative rather than a huge number, so
## nothing can quietly count down to a game over from it, and so everything
## reading the count can tell "unlimited" from "three" -- see
## [method has_infinite_lives].
const INFINITE_LIVES := -1

## What the double-gems purchase multiplies a gem by ON THE WAY INTO THE BANK.
##
## The bank only. A gem is worth the same to the score either way -- see
## [method collect_gem] for why that line is drawn where it is.
const DOUBLE_GEMS_MULTIPLIER := 2

## What a level's gems have to add up to for the first extra life of a run.
## About one level's worth, so a run that keeps finding gems keeps its lives up.
const FIRST_EXTRA_LIFE := 20

## How much higher the bar goes each time a life is earned. The count starts
## over from nothing after every life, so the second of a run costs 30 gems on
## top of the first, the third 40 on top of that, and so on.
const EXTRA_LIFE_STEP := 10

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
## PLAY is the way through the game: one level at a time, as many goes at it as
## it takes, and beating it opens the next one. There is nothing to lose in it --
## no lives to run out of and no game over -- which is the whole point. Falling
## off costs the time on the clock and nothing else.
##
## CHALLENGE is one continuous attempt at a whole chapter, starting at its first
## level and carrying the same three lives all the way through. Running out ends
## the run. It unlocks NOTHING: everything the game opens is opened by playing,
## and what a finished challenge is worth is still to be decided -- for now it is
## recorded and shown, and that is all.
enum Mode { PLAY, CHALLENGE }

var run_mode := Mode.PLAY

## Which mode the level list is OFFERING -- the tab the player last put the start
## button on. Not the same thing as `run_mode`, which is how the level currently
## loaded is being played.
##
## Remembered between sessions, because coming back from a failed challenge to a
## button that has quietly turned back into Play is how a player ends up starting
## a run they did not mean to.
var preferred_mode := Mode.PLAY

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
##
## Still written on every finish, and still what `beat_best` is worked out from
## for the record stamp on the victory panel -- but no longer read back out
## anywhere. The level page used to print both; it shows the crowns now.
var best_score := {}
var best_time := {}

## Level path -> the crowns that level has given up, as a bitmask of `Crowns`.
##
## Kept for good, and cumulative: a crown earned on one run is not lost by a
## slower run afterwards. They are collectables, not a scoreboard.
var crowns := {}

## The crowns the level just finished handed over for the FIRST time, for the
## victory panel to make something of. Bits, like the rest of them -- and nothing
## at all when the run turned up no new ones.
var last_crowns_won := 0

## Set id -> the level numbers beaten in it at least once, in whatever order
## they were played.
##
## This is the progress the whole game opens off: a level opens the one after it,
## a finished chapter opens the next chapter, and a finished world opens the next
## world. Either mode writes it -- a level beaten during a challenge run is
## beaten -- so a challenge is a harder way through the same door, never a
## separate one.
var cleared_levels := {}

## Set id -> true once its challenge run has been finished.
##
## A record and nothing more. It unlocks nothing and is worth nothing yet -- the
## way through the game is [member cleared_levels] -- but it is kept and shown,
## so whatever a finished challenge comes to be worth can be paid out on a
## record that was already being written.
var challenges_done := {}

## Every gem ever collected, banked for good and spent in the shop. A level's
## own gem tally resets with the level; this never does.
var bank := 0

## Whether the player has bought the double-gems modifier.
##
## Bought once with real money and kept for good, so it is saved with the rest of
## the player rather than with the run: it survives a game over, a set restarted,
## and `leave_run()`. Nothing hands it back -- see [method grant_double_gems].
##
## What it changes is the BANK, and only the bank. See [method collect_gem].
var double_gems := false

## Which marble the player is wearing, as a `MarbleSkins` id. Purely cosmetic:
## nothing about a level is gated on it. What IS gated is which marbles can be
## worn -- see [member owned_skins].
var marble_skin := MarbleSkins.DEFAULT

## Which awards have been won, as a set of `Awards` ids. Once in, never out: an
## award is a record of something that was done, and a level replayed worse does
## not undo it.
var awards_earned := {}

## The awards won but not yet shown to the player, oldest first.
##
## The marble is handed over the INSTANT the award is met, mid-level, and this is
## only the queue of things still to be announced -- so a player who wins one and
## closes the game before seeing the popup still owns the marble, and still gets
## told the next time they open the menu. See [method claim_award].
var awards_unclaimed: Array[String] = []

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
##
## Zero means the shop has never been stocked, which is the ONLY thing that asks
## for a roll ahead of the clock -- see [method shop_skins].
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

## Dev override: every world and chapter reads as open and every marble reads as
## owned, whatever has actually been finished or bought. Set from the levels
## page's dev tools and cleared by resetting.
##
## Kept apart from the real records rather than faking them, so the menus go on
## telling the truth about what has been cleared and challenged, the bank is not
## quietly handed the price of the catalogue, and turning it off puts everything
## back exactly where it was.
var dev_unlock_all := false

var _timing := false
var _timer_started := false

## How long this level gives, and whether that has been used up. Both are per
## attempt: a level taken again gets its whole clock back. See
## [method _read_time_limit].
var _time_limit := 0.0
var _timed_out := false
var _run_over := false

## Where the run stood when this attempt at the level began.
##
## A fall puts the level back to the start, gems and all -- so whatever this
## attempt banked has to go back too, or a level with a gem near the spawn is an
## endless supply of gems, and of the extra lives they buy. See
## [method restart_level].
var _attempt_bank := 0
var _attempt_run_gems := 0
var _attempt_extra_life_target := FIRST_EXTRA_LIFE
var _attempt_lives := STARTING_LIVES

## Set by `restart_level()` and cleared by the load it belongs to. An intro is
## a look at a level the player has not seen; taking the same one again after a
## fall is not that, and sitting through the fly-round on every retry would be
## the game holding the player still.
var _retrying := false


func _ready() -> void:
	# The trackers have to outlive every scene change, including the one that
	# happens the instant a level is finished.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_progress()


func _process(delta: float) -> void:
	if not _timing:
		return

	level_time += delta

	if _time_limit > 0.0 and level_time >= _time_limit:
		_time_out()


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
	last_crowns_won = 0
	_run_over = false
	set_score(0)

	_timing = false
	_timer_started = false
	_timed_out = false

	# Cleared here and read back in `_start_unless_held()`, which is deferred and
	# so runs after every node in the level has readied. Read here instead and it
	# would be a race with the goal ring that holds the number.
	_time_limit = 0.0

	# Before anything on screen has had a chance to read the stick: a level opens
	# on whatever the player asked for, not on whatever the last one ended as.
	_apply_stick_preference()

	_enter_set(level_path)

	# After the set, not before: a fresh attempt puts the climb towards an extra
	# life back to the bottom.
	gem_progress_changed.emit(run_gems, extra_life_target)

	# Taken after the set has been entered, so the lives it may just have dealt
	# are the ones this attempt is measured against.
	_attempt_bank = bank
	_attempt_run_gems = run_gems
	_attempt_extra_life_target = extra_life_target
	_attempt_lives = lives

	level_started.emit(level_path)

	# Deferred, so every node in the level has readied by the time it runs and
	# the camera has had its chance to ask for the level to be held. Which is
	# also what makes the order the level's nodes happen to be in irrelevant.
	_start_unless_held.call_deferred()


## Starts the level unless the camera is still looking round it.
##
## The clock used to start here outright. It waited on the player's first steer
## before that, which meant the drop onto the spawn -- and any roll it turned
## into -- happened off the clock; it waits on the opening shot now, which is not
## the player's time either.
func _start_unless_held() -> void:
	# Whatever the retry flag was for, its level has loaded and readied by now --
	# and if that level had no camera to read it, it is spent all the same. It
	# lives exactly one load.
	_retrying = false

	_time_limit = _read_time_limit()

	if not is_intro_held():
		begin_timing()


## How long this level gives the player, read off its own goal ring.
##
## The ring is where every deadline in the game is tuned -- the time score, the
## fast-time share -- so the limit is that same number rather than a second one
## that could disagree with it. A level with no ring, or one with its timing
## turned off, has no limit and simply counts up.
func _read_time_limit() -> float:
	var goal := get_tree().get_first_node_in_group("goal_ring") as GoalRing
	if goal == null:
		return 0.0

	return maxf(goal.slow_time, 0.0)


## The clock has run out.
##
## The level is NOT over. Control goes and the words go up, but the ball keeps
## whatever it was carrying and a goal reached on that momentum counts in full --
## `goal_ring.gd` is told nothing about any of this and needs to be told nothing.
##
## The clock is pinned exactly ON the limit rather than left a frame past it, and
## that one line is what makes the clutch goal work: everything downstream reads
## `level_time` and already does the right thing with it. The time award comes to
## nothing, the fast-time bonus is long gone, and the best time banked is the
## limit itself -- a goal after the buzzer scores what a goal on the buzzer would.
func _time_out() -> void:
	level_time = _time_limit
	_timing = false
	_timed_out = true

	time_ran_out.emit()


## Whether this level runs on a clock at all. False for a level with its timing
## turned off, which counts up and never runs out.
func has_time_limit() -> bool:
	return _time_limit > 0.0


## Seconds left on the clock, down to nothing. Meaningless where there is no
## limit -- ask [method has_time_limit] first.
func time_left() -> float:
	return maxf(_time_limit - level_time, 0.0)


## Whether the clock has run out on this attempt.
func is_timed_out() -> bool:
	return _timed_out


## Whether the camera may play its opening shot. Asked by the camera as it
## readies, and answered no for a level being taken again after a fall: the
## player has just seen it.
func may_play_intro() -> bool:
	if _retrying:
		_retrying = false
		return false

	return true


## The opening shot is over. Everything that was waiting on it -- the clock, the
## ball, the stick -- goes on `timing_started`.
func end_intro() -> void:
	begin_timing()


## Whether the level is still waiting on its opening shot.
##
## Asked of the camera rather than kept as a flag here. The camera and the HUD
## that starts the level ready in whatever order the level scene happens to list
## them, and a flag set by one and cleared by the other answers differently from
## level to level -- which is exactly what it did: on the one level that lists
## its camera first, the clock ran through the whole opening shot.
func is_intro_held() -> bool:
	for rig in get_tree().get_nodes_in_group("camera_rig"):
		if rig.has_method("is_running_intro") and rig.is_running_intro():
			return true

	return false


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
		run_mode = Mode.PLAY
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
		run_mode = Mode.PLAY

	run_set = set_id
	run_index = place.index
	run_world = place.world
	run_chapter = place.chapter

	# Play is every level on its own, and a challenge that this level is not part
	# of has just become one.
	if not carries_on:
		_deal_lives()


## Begins a play attempt: one level, unlimited goes at it, and the next level
## opened by finishing it. Called by the level list just before it swaps to the
## level.
##
## The lives are dealt when the level loads, in `_enter_set()`.
func begin_play() -> void:
	run_mode = Mode.PLAY


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


## Hands out lives for a fresh attempt, and starts the climb towards an extra
## one over from the bottom.
##
## Play mode is handed the unlimited marker instead of a count. The climb is
## restarted either way: it costs nothing, and it means a challenge started from
## a play session begins its climb where a challenge always does.
func _deal_lives() -> void:
	lives = INFINITE_LIVES if run_mode == Mode.PLAY else STARTING_LIVES
	_restart_extra_life_climb()
	lives_changed.emit(lives)


## Whether this run can be failed at all. False only during a challenge.
func has_infinite_lives() -> bool:
	return lives == INFINITE_LIVES


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
	run_mode = Mode.PLAY

	_restart_extra_life_climb()
	save_progress()


func _restart_extra_life_climb() -> void:
	run_gems = 0
	extra_life_target = FIRST_EXTRA_LIFE
	gem_progress_changed.emit(run_gems, extra_life_target)


## Starts the clock, once. Called the first time the player actually steers, so
## a level is not timed while they are still sizing it up.
func begin_timing() -> void:
	# A clock that has already run out does not get started again by whatever
	# was still waiting on the intro.
	if _timer_started or _run_over or _timed_out:
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
##
## The three are counted SEPARATELY, which is what lets the double-gems purchase
## touch one of them and leave the other two alone:
##
##   * The SCORE takes the gem at face value, always. A score is a claim about
##     how the level was played, and it is set against the player's own bests,
##     the crowns, and everyone else's numbers. A score that can be bought is not
##     a score, so money is not allowed anywhere near this line.
##   * The BANK takes the doubled value. The bank is a wallet, not a record --
##     it buys marbles and nothing else -- so paying to fill it faster costs
##     nobody anything.
##   * The EXTRA LIFE climb takes face value too, for the same reason as the
##     score rather than a different one: lives are how hard the game is, and
##     the item this modifier replaced on the shelf was literally infinite
##     lives. Doubling this would sell that back through the side door.
func collect_gem(points: int) -> void:
	gem_score += points
	add_score(points)

	bank += banked_value(points)
	bank_changed.emit(bank)

	run_gems += points
	_award_extra_life()
	gem_progress_changed.emit(run_gems, extra_life_target)

	# Banked the moment it is picked up, so quitting part way through a level
	# does not cost the player gems they have already collected.
	save_progress()


## What a gem worth [param points] puts in the bank, which is double what it is
## worth to everything else once the modifier is owned.
##
## Public because the shop draws the wallet and wants to be able to say what a
## gem is worth now, and because it is the one place the multiplier is applied.
func banked_value(points: int) -> int:
	return points * DOUBLE_GEMS_MULTIPLIER if double_gems else points


## Turns the double-gems modifier on for good.
##
## This is the seam a store hooks into: when the purchase clears, whatever is
## holding the receipt calls this and nothing else has to change. It is safe to
## call again -- a restore on a new device runs through here too, and a player
## who already has it must not be told they have just bought it a second time.
##
## Written to disk immediately rather than left to the next save. What was just
## paid for must survive the game being killed on the very next breath.
func grant_double_gems() -> void:
	if double_gems:
		return

	double_gems = true
	double_gems_changed.emit(double_gems)
	save_progress()


## Hands out an extra life once the run's gems have reached the bar, then puts
## the count back to nothing with the bar raised.
##
## The gems counted carry from level to level, so the count picks up where the
## last level left it. A set's first extra life comes at 20 gems, the next at 30
## more, then 40 more -- and a long run may well end before the player has found
## another.
func _award_extra_life() -> void:
	if _run_over:
		return

	# Nothing to add to. Adding one here would also turn the unlimited marker
	# into a real count, and a real count is a count that can run out.
	if has_infinite_lives():
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
## Called by the goal ring when the ball is through it.
##
## `was_fast` and `all_gems` are handed over rather than worked out here: the
## fast-time deadline is tuned per level on the goal ring itself, and only the
## ring knows it. What they MEAN -- which crowns they are worth -- is decided
## here, so the rules live in one place.
func finish_level(clear_points: int, was_fast: bool, all_gems: bool) -> void:
	_timing = false

	# Before anything is worked out, because what listens is the in-level
	# furniture clearing off ahead of the victory panel -- including, when the
	# ball rolled in after the buzzer, the timeout's own words and its two ways
	# out. A goal is a goal however late it was, so none of that is left standing.
	level_finished.emit()

	add_score(clear_points)

	_bank_level(was_fast, all_gems)


## A finished level banked again, because it turned out to be worth more than it
## was when the goal was taken.
##
## The level ends the instant the glass goes, but the ball does not: it coasts
## out the far side, and a gem it runs over on the way is as collected as one
## taken on the way in. So the tally has to be settled a second time, once the
## ball has come to rest -- see `goal_ring.gd::_watch_the_coast()`, which is the
## only thing that calls this.
##
## The whole new total is handed over rather than the difference, because the
## all-gems multiplier does not add to the old total, it replaces the sum it was
## worked out from.
##
## Nothing is undone here. The clock is not touched and `level_finished` is not
## announced again -- the level really did end back at the ring, and this is only
## the accounting catching up with a ball that was still moving.
func rebank_level(total: int, was_fast: bool, all_gems: bool) -> void:
	set_score(total)

	_bank_level(was_fast, all_gems)

	# After the banking, not before: what listens is the victory panel reading
	# all of it back out, and it has to read what was just written.
	level_rebanked.emit()


## Everything a finished level writes down: its crowns, its bests, its place in
## the set, and whatever awards that has just won.
##
## Written to be safe to run twice over the same finish, because a level whose
## last gems lie past the goal is banked once at the ring and again once the ball
## has stopped rolling. What that costs is spelled out where it is not obvious:
## the crowns won and the record both accumulate rather than being restated, so
## the second pass cannot take back what the first one found.
func _bank_level(was_fast: bool, all_gems: bool) -> void:
	if current_level.is_empty():
		return

	_award_crowns(was_fast, all_gems)

	var beat_score: bool = score > best_score.get(current_level, -1)
	if beat_score:
		best_score[current_level] = score

	var previous_best: float = best_time.get(current_level, INF)
	var beat_time := level_time < previous_best
	if beat_time:
		best_time[current_level] = level_time

	# Folded in rather than set, so a second pass cannot rub out a record the
	# first one set: the best it would be measured against by then is the one it
	# just wrote, which nothing can beat twice.
	beat_best = beat_best or beat_score or beat_time

	_bank_progress()

	# After the banking, not before: the challenge flag this run may just have
	# set is written there, and one of the awards is watching for it.
	_check_awards()

	save_progress()


## The crowns this run of the level has just given up, folded into whatever it
## had given up before.
##
## GOLD is not among them: it is the chapter's challenge and is read off
## `challenges_done`, which `_bank_progress()` writes.
##
## The green one asks for every gem in the level, so a level with no gems in it
## hands it over for nothing. That is the honest answer to the question as asked,
## and it is the same edge the diamond sits on -- the diamond is the green one
## and the red one won together.
func _award_crowns(was_fast: bool, all_gems: bool) -> void:
	var had: int = crowns.get(current_level, 0)
	var earned := had | Crowns.SILVER

	if all_gems:
		earned |= Crowns.GREEN

	if was_fast:
		earned |= Crowns.RED

	# Taking the level DURING a challenge is the whole of what this asks. The run
	# it belongs to may well die two levels later; the crown was still won here,
	# on three lives, and taking it back would be reading the player's worst
	# moment onto their best one.
	if run_mode == Mode.CHALLENGE:
		earned |= Crowns.GOLD

	if all_gems and was_fast:
		earned |= Crowns.DIAMOND

	crowns[current_level] = earned

	# Folded in, not set. A level can be banked twice -- the gems past the goal
	# are counted after the ball has stopped -- and by the second pass the crowns
	# the first one handed over are crowns the level "had", so restating this
	# would leave the victory panel with only the late ones to celebrate. Put
	# back to nothing by `start_level()`, so nothing carries between attempts.
	last_crowns_won |= earned & ~had


## Every crown a level has given up.
func crowns_for(level_path: String) -> int:
	return crowns.get(level_path, 0)


# --- Awards ---

## Everything that has just been won, handed over on the spot.
##
## Called wherever the things awards are measured on can have moved -- the end of
## a level, and the load of a save written before any of this existed. Cheap
## enough to call freely: three awards, and the two that walk a world stop at the
## first level that falls short.
##
## The marble goes into the player's hands HERE, not when the popup is claimed.
## The popup is an announcement, and a player who wins an award and shuts the
## game before seeing it has still won it.
func _check_awards() -> void:
	var won := false
	var changed := false

	for award_id: String in Awards.ORDER:
		if not awards_earned.has(award_id):
			if not _award_met(award_id):
				continue

			awards_earned[award_id] = true
			awards_unclaimed.append(award_id)
			won = true

		# Reached for awards won long ago as well as ones won just now. An award
		# is a promise of a marble, and a save holding the one without the other
		# -- written before this award handed that skin over, or parted from it
		# by a catalogue change -- is made good here rather than never. Checking
		# costs a dictionary lookup; the alternative is a player who did the
		# hardest thing in the game and cannot wear what they did it for.
		var skin := Awards.skin_for(award_id)
		if MarbleSkins.has(skin) and not owned_skins.has(skin):
			owned_skins[skin] = true
			changed = true

	if not won and not changed:
		return

	owned_skins_changed.emit()

	# Only for awards actually won. A marble quietly put back where it belonged
	# is not something to announce.
	if won:
		award_earned.emit()

	save_progress()


## Whether one award's condition is met right now.
##
## The conditions live here rather than in the catalogue for the same reason the
## crowns' do: `Awards` is what they ARE, and what it takes to win one is a fact
## about the run, which is what this tracker holds.
func _award_met(award_id: String) -> bool:
	match award_id:
		Awards.CROWNED:
			return _world_crowned(1, 3)
		Awards.CHALLENGER:
			return not challenges_done.is_empty()
		Awards.FLAWLESS:
			return _world_crowned(1, Crowns.ORDER.size())

	return false


## Whether every level built for a world has given up at least `needed` crowns.
##
## A world with nothing built in it answers NO rather than yes. Walking an empty
## list and finding no level short of the bar is true by vacancy, and it would
## hand out the award for a world that does not exist yet.
func _world_crowned(world: int, needed: int) -> bool:
	var any := false

	for chapter: String in LevelManager.built_chapters(world):
		for path: String in LevelManager.levels_in(world, chapter):
			any = true
			if Crowns.count(crowns_for(path)) < needed:
				return false

	return any


## The award the menu should be announcing, or "" when there is nothing waiting.
func next_unclaimed_award() -> String:
	return awards_unclaimed[0] if not awards_unclaimed.is_empty() else ""


## The player has seen one. Nothing is handed over here -- the marble went in the
## moment the award was won -- so this only takes it off the queue.
func claim_award(award_id: String) -> void:
	awards_unclaimed.erase(award_id)
	save_progress()


## Marks the level off, and -- when this was the last level of a challenge run
## -- marks the whole challenge done as well.
##
## The level being marked off is what opens the next one. The challenge flag
## rides alongside it and opens nothing; see [member challenges_done].
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


## The ball has left the alive zone.
##
## Everything a fall COSTS is decided here; what it looks like belongs to the
## level -- see `alive_zone.gd`. Answers whether the level should go on to show
## the fall and wait to be taken again, which it should not if that was the last
## life: the game-over screen owns the level from there.
func fall_out() -> bool:
	if _run_over:
		return false

	# The clock stops where the ball left the world. Nothing that happens while
	# the fall is being watched is the player's time.
	stop_timing()

	lose_life()
	if _run_over:
		return false

	fell_out.emit()
	return true


## Whether the run is over and the game-over screen has the level.
func is_run_over() -> bool:
	return _run_over


## Takes the level again from the top, as though this attempt had not happened.
##
## The scene is RELOADED rather than the ball put back on its spawn: a level that
## resets is a level with its gems back, its broken floor whole and its clock at
## zero, and reloading is the only way to be sure of all of it at once.
##
## What the reload cannot undo is what the attempt paid into the run, because
## none of that lives in the level: gems are banked the moment they are picked
## up. So the bank, the climb towards the next life, and any life that climb
## bought are all put back to where this attempt found them. The life spent
## FALLING is the one thing that stands -- that is the cost, and in play mode
## there is nothing to spend.
func restart_level() -> void:
	bank = _attempt_bank
	run_gems = _attempt_run_gems
	extra_life_target = _attempt_extra_life_target

	if not has_infinite_lives():
		lives = maxi(_attempt_lives - 1, 0)
		lives_changed.emit(lives)

	bank_changed.emit(bank)
	gem_progress_changed.emit(run_gems, extra_life_target)
	save_progress()

	# The level is about to be taken again, not seen for the first time. Read and
	# cleared by `hold_for_intro()` on the way back in.
	_retrying = true

	# `start_level()` on the way back in resets the clock, the score and the
	# level's own gem tally, so there is nothing here to put back by hand.
	get_tree().reload_current_scene()


## Called when the ball falls off the stage.
func lose_life() -> void:
	# Once the run is over it stays over. A ball still tumbling behind the
	# game-over screen would otherwise keep spending lives it does not have, and
	# stack up a fresh game-over screen for each one.
	if _run_over:
		return

	# Play mode has nothing to spend. The ball has already been put back on the
	# spawn by the alive zone, which is the whole of what falling off costs.
	if has_infinite_lives():
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
## simply never wrote its done flag, and the levels it did beat on the way are
## beaten either way.
func reset_run() -> void:
	_run_over = false
	run_mode = Mode.PLAY
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
## attempt without running out of lives. A record only; nothing waits on it.
func is_challenge_complete(world: int, chapter: String) -> bool:
	if LevelManager.levels_in(world, chapter).is_empty():
		return false

	return challenges_done.get(LevelManager.set_id(world, chapter), false)


## Whether every level built for a chapter has been beaten, in any order and in
## either mode. This is what opens the chapter after it.
##
## A chapter with nothing built for it never counts, so an empty one cannot open
## the rest of the world behind it.
func is_set_complete(world: int, chapter: String) -> bool:
	var built := LevelManager.levels_in(world, chapter)
	if built.is_empty():
		return false

	return cleared_in(world, chapter) >= built.size()


## Whether a chapter can be played at all. The easiest one opens as soon as its
## world does; every one after it waits on the chapter before it being finished
## -- every level in it beaten.
func is_set_unlocked(world: int, chapter: String) -> bool:
	if dev_unlock_all:
		return true

	# Counted among the chapters this world actually HAS. Waiting on a chapter
	# that was planned but never built would lock the rest of the world behind
	# levels nobody can play.
	var built := LevelManager.built_chapters(world)
	var step := built.find(chapter)
	if step > 0:
		return is_set_complete(world, built[step - 1])

	return is_world_unlocked(world)


## Whether a level can be opened from the list.
##
## One at a time: the first level of an open chapter is open, and every level
## after it waits on the one before it being beaten. That is the whole of the
## progression -- play a level, open the next.
##
## Beaten, not beaten in any particular mode. A level cleared on the way through
## a challenge run opens the next one exactly as playing it would.
func is_level_unlocked(world: int, chapter: String, index: int) -> bool:
	if LevelManager.level_at(world, chapter, index).is_empty():
		return false

	if not is_set_unlocked(world, chapter):
		return false

	if dev_unlock_all or index <= 0:
		return true

	return is_level_cleared(world, chapter, index - 1)


## Whether a challenge run can be started.
##
## The chapter has to be open, have something in it to run, and -- this is what
## makes it a challenge rather than a first attempt -- be FINISHED: every level in
## it beaten at least once, in any order and in either mode.
##
## Taking a whole chapter on three lives is not something to be walked into
## blind. By the time it opens, the player has been round every level in it and
## knows what the run is asking of them.
func can_start_challenge(world: int, chapter: String) -> bool:
	if LevelManager.levels_in(world, chapter).is_empty():
		return false

	if not is_set_unlocked(world, chapter):
		return false

	return dev_unlock_all or is_set_complete(world, chapter)


## World 1 is always open. Every world after it waits on the whole of the world
## before it -- every level of every chapter beaten.
func is_world_unlocked(world: int) -> bool:
	if dev_unlock_all or world <= 1:
		return true

	# Every chapter the world before this one actually has. A world with nothing
	# in it has nothing to finish, so it never opens the next -- which is what
	# stops the whole game unlocking itself down an unbuilt chain.
	var built := LevelManager.built_chapters(world - 1)
	if built.is_empty():
		return false

	for chapter: String in built:
		if not is_set_complete(world - 1, chapter):
			return false

	return true


## Seconds down to the hundredth, and only ever seconds. Used by the HUD and the
## menus so a time always reads the same way.
##
## It used to turn over to minutes at sixty. It does not now, because the clock
## counts DOWN and a minute boundary in a countdown is a readout that changes
## SHAPE while the player is watching it -- "1:00.25" one moment and "59.90s" the
## next, four glyphs becoming three, the decimal point jumping sideways. A number
## that has to be read at a glance mid-roll should not move about, and seconds
## alone never do.
##
## Nothing here is worth setting a level to past a few hundred seconds, so the
## width this gives up is width nothing was going to use.
##
## Only the display is rounded. `level_time` and every best time kept in
## `best_time` are full-precision floats, so two runs a millisecond apart are
## still ranked apart even where they read the same.
static func format_time(seconds: float) -> String:
	if is_inf(seconds):
		return "--"

	return "%.2fs" % seconds


## A gem count with its thousands split up, so a full bank stays readable.
static func format_gems(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""

	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)

	grouped = digits + grouped
	return "-" + grouped if value < 0 else grouped


## Whether a marble can be worn. The dev unlock answers yes to all of them
## without writing any of them down -- see [member dev_unlock_all] -- so the
## shelf, the picker and `buy_skin()` all follow from this one question.
func owns_skin(skin_id: String) -> bool:
	# Every id resolves to something in the catalogue, so there is nothing left
	# for the override to say no to.
	if dev_unlock_all:
		return true

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
##
## The CLOCK is what asks for a roll, never an empty shelf. An empty shelf is a
## real answer -- it is what a player who owns every marble is shown -- and
## rolling on it is a loop: the restock tells the shop page, the page asks what
## is out, there is still nothing to sell, and it rolls again until the stack
## gives out. `shop_refresh_at` of zero is the one shelf that has never been
## stocked, and the only thing that rolls early.
func shop_skins() -> Array[String]:
	if shop_refresh_at == 0 or _now() >= shop_refresh_at:
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
## The first slot always holds the cheapest marble left in the game, so there is
## something affordable on the shelf beside the things that are not -- a shop
## that rolled three legendary ones would be showing a player with four hundred
## gems nothing they could buy. The other two are rolled by rarity.
##
## Fewer than three come back only when there are fewer than three left to sell,
## and an empty shelf is what a player who owns every marble is shown.
func _pick_stock() -> Array[String]:
	var picked: Array[String] = []

	# What is left, tier by tier. A tier with nothing unowned in it is left OUT
	# rather than left empty: that is what hands its odds to the tiers that do
	# have something, so a player who owns every common marble starts being
	# offered uncommon ones in that slot rather than an empty shelf.
	#
	# Built in `RARITIES` order, which a Dictionary keeps, so the first key is
	# always the commonest tier still holding stock.
	var stock := {}
	for rarity: String in MarbleSkins.RARITIES:
		# Award marbles are never stock, owned or not. They are the whole payment
		# for the hardest things in the game, and one of them turning up on the
		# shelf for gems would be the shop selling somebody else's trophy.
		var left := MarbleSkins.ids_in(rarity).filter(func(id: String) -> bool:
			return not owns_skin(id) and not Awards.locks_skin(id))

		if not left.is_empty():
			stock[rarity] = left

	if stock.is_empty():
		return picked

	picked.append(_take_stock(stock, stock.keys()[0]))

	while picked.size() < SHOP_SLOTS and not stock.is_empty():
		picked.append(_take_stock(stock, _roll_rarity(stock)))

	return picked


## Takes one marble out of a tier, and the tier itself once that empties it. The
## same shelf must never offer the same marble twice, and neither three slots nor
## eight tiers are enough for chance to be trusted with that.
func _take_stock(stock: Dictionary, rarity: String) -> String:
	var left: Array = stock[rarity]
	var id: String = left.pop_at(randi() % left.size())

	if left.is_empty():
		stock.erase(rarity)

	return id


## Which tier the next slot is rolled from.
##
## Each tier is half as likely as the one below it, which is what makes a rare
## marble on the shelf worth stopping for. The weights are over the TIERS and not
## over the marbles in them, so a tier holding twenty skins is no likelier to
## come up than one holding eight -- how many marbles happen to be drawn for a
## tier is not meant to be how often it is offered.
func _roll_rarity(stock: Dictionary) -> String:
	var weights := {}
	var total := 0

	for rarity: String in stock:
		var steps := MarbleSkins.RARITIES.size() - 1 - MarbleSkins.RARITIES.find(rarity)
		weights[rarity] = 1 << steps
		total += weights[rarity]

	var roll := randi() % total
	var last := ""

	for rarity: String in stock:
		last = rarity
		roll -= weights[rarity]
		if roll < 0:
			return rarity

	# Only reachable if the weights above did not add up to `total`, which they
	# always do. The commonest tier left is the safe answer either way.
	return last


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
	file.set_value("purchases", "double_gems", double_gems)
	file.set_value("best", "score", best_score)
	file.set_value("best", "time", best_time)
	file.set_value("best", "crowns", crowns)
	file.set_value("progress", "cleared", cleared_levels)
	file.set_value("progress", "challenges", challenges_done)
	file.set_value("awards", "earned", awards_earned.keys())
	file.set_value("awards", "unclaimed", awards_unclaimed)
	file.set_value("marble", "skin", marble_skin)
	file.set_value("marble", "owned", owned_skins.keys())
	file.set_value("shop", "offer", shop_offer)
	file.set_value("shop", "refresh_at", shop_refresh_at)
	file.set_value("menu", "mode", preferred_mode)
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
	double_gems = file.get_value("purchases", "double_gems", false)
	best_score = file.get_value("best", "score", {})
	best_time = file.get_value("best", "time", {})
	crowns = file.get_value("best", "crowns", {})
	cleared_levels = file.get_value("progress", "cleared", {})
	challenges_done = file.get_value("progress", "challenges", {})

	# Awards the catalogue no longer knows are dropped on the way in, the same as
	# skins are. An id that has been retired is not an award any more, and one
	# left in the unclaimed queue would be a popup with nothing to show.
	awards_earned = {}
	for id: String in file.get_value("awards", "earned", []) as Array:
		if Awards.has(id):
			awards_earned[id] = true

	awards_unclaimed.assign((file.get_value("awards", "unclaimed", []) as Array).filter(
			func(id: String) -> bool: return Awards.has(id)))
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
	# Clamped to a mode that exists: a save written by a build with a different
	# set of modes in it must not leave the start button pointing at nothing.
	preferred_mode = clampi(int(file.get_value("menu", "mode", Mode.PLAY)),
			Mode.PLAY, Mode.CHALLENGE) as Mode

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

	# Checked on the way in as well as at the end of a level, so a save that
	# already meets one of these -- every save written before awards existed --
	# is paid what it is owed rather than made to go and win the crowns again.
	_check_awards()

	lives_changed.emit(lives)
	bank_changed.emit(bank)
	double_gems_changed.emit(double_gems)


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
## times or scores, an empty bank, the marble back to the default one, the dev
## unlock off again, and the double-gems purchase gone with the rest of it.
##
## That last one is the only thing here that was ever paid for. It goes because
## this is a first run and a first run has not bought anything -- and on a real
## device the store is what puts a purchase back, not the save file.
##
## Written to disk straight away rather than left for the next save, so quitting
## immediately afterwards cannot resurrect the old progress.
func dev_reset_progress() -> void:
	cleared_levels = {}
	challenges_done = {}
	best_score = {}
	best_time = {}
	crowns = {}
	bank = 0
	dev_unlock_all = false
	double_gems = false
	marble_skin = MarbleSkins.DEFAULT
	owned_skins = {MarbleSkins.DEFAULT: true}

	# Cleared rather than rolled again: the next look at the shelf restocks it,
	# and doing it here would put stock out that nobody has asked to see.
	shop_offer.clear()
	shop_refresh_at = 0

	_run_over = false
	run_mode = Mode.PLAY
	preferred_mode = Mode.PLAY
	_deal_lives()

	bank_changed.emit(bank)
	double_gems_changed.emit(double_gems)
	marble_skin_changed.emit(marble_skin)
	owned_skins_changed.emit()
	shop_changed.emit()
	progress_changed.emit()
	save_progress()


## Opens every world and chapter at once, and hands over every marble in the
## catalogue with it. Nothing is marked as finished and nothing is written into
## the owned set -- see `dev_unlock_all` for why -- so `dev_reset_progress()` is
## the way back off.
##
## The double-gems modifier is the one exception, and it IS written down. There
## is no store in the build to buy it from, so without this there is no way to
## see the thing working at all; and it is on the same way back off as the rest.
func dev_unlock_everything() -> void:
	dev_unlock_all = true
	grant_double_gems()

	# The marble picker and the shop shelf are both built from `owns_skin()`,
	# and neither is listening for a world opening -- so the skins have to say
	# so themselves, or a page already on screen goes on showing the old stock.
	owned_skins_changed.emit()
	progress_changed.emit()

	save_progress()
