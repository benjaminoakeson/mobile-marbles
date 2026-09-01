class_name Awards
extends RefCounted

## What the game gives back for the crowns.
##
## Laid out the same way as `Crowns` and `MarbleSkins`: one const catalogue that
## the save file and the menus both read from. What EARNS an award is decided in
## [GameState] -- this is only what they are.
##
## Every award hands over a marble, and those marbles are award-only: they are
## kept out of the shop's stock, so the single way to come by one is to do the
## thing. See `GameState._pick_stock()`, which asks [method locks_skin].
##
## They are also invisible until they land. The picker lists only marbles the
## player owns, so an unearned award leaves no trace anywhere -- nobody goes
## looking for these, they arrive.

## The ids, which are what go in the save file, so they outlive both the display
## name and whichever marble they happen to hand over.
const CROWNED := "world_1_crowned"
const CHALLENGER := "first_challenge"
const FLAWLESS := "world_1_flawless"

## Easiest first, which is also roughly the order they will be earned in. What
## `GameState` walks when it checks whether anything has just been won.
const ORDER := [CROWNED, CHALLENGER, FLAWLESS]

## `ask` is written out for the player and is the whole of what the popup says
## the award was for. It is phrased as the thing that was done, not as a
## condition to go and meet, because it is only ever read AFTER the fact.
const CATALOG := {
	CROWNED: {
		"name": "Crowned",
		"ask": "Three crowns or more on every level in World 1.",
		"skin": "solid_green",
	},
	CHALLENGER: {
		"name": "Challenger",
		"ask": "Your first challenge run, finished.",
		"skin": "solid_gold",
	},
	FLAWLESS: {
		"name": "Flawless",
		"ask": "All five crowns on every level in World 1.",
		"skin": "glass_cats_eye",
	},
}


static func has(award_id: String) -> bool:
	return CATALOG.has(award_id)


static func name_for(award_id: String) -> String:
	return CATALOG.get(award_id, {}).get("name", "Award")


## What was done to earn it, written out. See [constant CATALOG].
static func ask_for(award_id: String) -> String:
	return CATALOG.get(award_id, {}).get("ask", "")


## The marble it hands over, as a `MarbleSkins` id.
static func skin_for(award_id: String) -> String:
	return CATALOG.get(award_id, {}).get("skin", "")


## Whether a marble is spoken for by an award, and so must never be rolled onto
## the shop's shelf.
##
## Asked of the catalogue rather than kept as a second list of ids, because two
## lists that have to agree about which marbles are award-only is one list too
## many -- adding an award here is the whole of taking its marble off sale.
static func locks_skin(skin_id: String) -> bool:
	for award_id: String in ORDER:
		if skin_for(award_id) == skin_id:
			return true

	return false
