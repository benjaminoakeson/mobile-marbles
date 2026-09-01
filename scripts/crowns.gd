class_name Crowns
extends RefCounted

## The five crowns a level can give up.
##
## Laid out the same way as `LevelManager` and `MarbleSkins`: one const catalogue
## that the menus and the save file both read from. What EARNS a crown is decided
## in [GameState] when a level is finished -- this is only what they are.
##
## All five are facts about one level, written down against that level. GOLD is
## the one that asks anything of the run around it: the level has to have been
## beaten during a challenge, though the challenge itself need not be finished.
## A run that dies two levels later leaves the crowns it won standing.

## Bits, not an enum. What a level has given up is one number in the save, and
## these are the bits of it -- so a crown added later costs a bit, not a
## migration.
const SILVER := 1
const GREEN := 2
const RED := 4
const GOLD := 8
const DIAMOND := 16

## Left to right on the level page, easiest first. That order is also roughly the
## order a player earns them in: everyone gets the silver, the diamond asks for
## every gem AND the fast time in the same run.
const ORDER := [SILVER, GREEN, RED, GOLD, DIAMOND]

## What each crown is called. One name, used everywhere: shouted by the victory
## panel as it lands, and heading the card the level page shows when one is
## tapped. There were two sets of these -- a terse one for tooltips and a loud
## one for the panel -- which is one more way to name five things than the game
## needs.
const NAMES := {
	SILVER: "Level Finished",
	GREEN: "No Gems",
	RED: "Fast Time",
	GOLD: "Challenge",
	DIAMOND: "Perfect",
}

## And what it takes to win one, written out. The level page shows this when a
## crown is tapped -- for the ones already won as much as the ones still to go,
## since "what was that one for again?" is the same question.
const ASKS := {
	SILVER: "Reach the goal ring. However long it takes, however many tries.",
	GREEN: "Reach the goal ring without picking up a single gem.",
	RED: "Reach the goal ring before the clock passes the red mark.",
	GOLD: "Beat the level during a challenge run. The run itself does not have to survive.",
	DIAMOND: "Take every gem in the level AND still beat the red mark, in the same run.",
}

## What to tint the badge. The art is flat white, so these are the crowns.
const COLOURS := {
	SILVER: Color(0.83, 0.87, 0.91),
	GREEN: Color(0.36, 0.81, 0.42),
	RED: Color(0.91, 0.31, 0.31),
	GOLD: Color(1.0, 0.79, 0.24),
	DIAMOND: Color(0.6, 0.93, 1.0),
}

## An empty slot. Dark enough to sit back on the page, light enough that the
## shape still reads -- an unearned crown has to look like something to go and
## get, not like a gap where a crown might one day be.
const UNEARNED := Color(0.27, 0.29, 0.32)


static func name_for(crown: int) -> String:
	return NAMES.get(crown, "Crown")


## What it takes to win this one. See [constant ASKS].
static func ask_for(crown: int) -> String:
	return ASKS.get(crown, "")


## The crowns in `earned`, commonest first. What the victory panel walks to
## celebrate them one at a time.
static func won_in(earned: int) -> Array:
	return ORDER.filter(func(crown: int) -> bool: return bool(earned & crown))


static func colour_for(crown: int) -> Color:
	return COLOURS.get(crown, Color.WHITE)


## How many of the five one level has given up.
static func count(earned: int) -> int:
	var total := 0

	for crown: int in ORDER:
		if earned & crown:
			total += 1

	return total
