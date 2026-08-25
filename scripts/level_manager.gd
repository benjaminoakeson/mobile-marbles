class_name LevelManager
extends RefCounted

## Where every playable level is registered.
##
## The game is laid out as ten worlds, each holding one set of levels per
## chapter, each set ten levels long. A set is what the player takes on in a
## single run: three lives to clear all ten, which unlocks the next chapter
## in that world. Clearing every chapter unlocks the next world.
##
## Only the levels that have actually been built are listed in `CATALOG`. The
## menus still draw a full set of ten tiles, showing the ones with nothing behind
## them yet as empty, so half-filled sets are visible rather than hidden.
##
## To add a level, drop its path into the right list and give it a name in
## `NAMES`. Nothing else needs touching -- the menus, the unlock rules and
## "Next Level" all read from here.

const MENU := "res://scenes/UI/main_menu.tscn"
const GAME_OVER := "res://scenes/UI/game_over.tscn"

const WORLD_COUNT := 10
const LEVELS_PER_SET := 10

## The chapters every world runs through, easiest first. Play order, and the
## order they unlock in.
##
## These strings are also half of the key a set's progress is saved under, so
## they are not free text -- renaming one here orphans everything ever cleared in
## it. The player-facing name comes from `CHAPTER_NAMES` instead, which is safe
## to change whenever.
const CHAPTERS := [
	"Super Easy",
	"Easy",
	"Medium",
	"Hard",
	"Super Hard",
	"Master",
]

## world number -> the chapter names for that world, in `CHAPTERS` order.
##
## What the chapter selector puts above the difficulty. A world with no entry, or
## a list shorter than `CHAPTERS`, falls back to the difficulty itself, so a
## chapter is never nameless while a world is still being written.
const CHAPTER_NAMES := {
	1: [
		"Rolling Meadow",
		"Garden Path",
		"Hedge Maze",
		"Timber Yard",
		"The Long Fall",
		"Meadow's End",
	],
}

## world number -> chapter -> the levels of that set, in play order.
##
## A missing world or chapter is simply an empty set. A set can hold fewer
## than `LEVELS_PER_SET` levels while it is being built out.
const CATALOG := {
	1: {
		"Super Easy": [
			"res://scenes/levels/world_1/super_easy/1-1-se.tscn",
			"res://scenes/levels/world_1/super_easy/1-2-se.tscn",
			"res://scenes/levels/world_1/super_easy/1-3-se.tscn",
			"res://scenes/levels/world_1/super_easy/1-4-se.tscn",
			"res://scenes/levels/world_1/super_easy/1-5-se.tscn",
		],
		"Easy": [
			"res://scenes/levels/world_1/easy/1-1-e.tscn",
			"res://scenes/levels/world_1/easy/1-2-e.tscn",
			"res://scenes/levels/world_1/easy/1-3-e.tscn",
			"res://scenes/levels/world_1/easy/1-4-e.tscn",
			"res://scenes/levels/world_1/easy/1-5-e.tscn",
			"res://scenes/levels/world_1/easy/1-6-e.tscn",
			"res://scenes/levels/world_1/easy/1-7-e.tscn",
			"res://scenes/levels/world_1/easy/1-8-e.tscn",
			"res://scenes/levels/world_1/easy/1-9-e.tscn",
			"res://scenes/levels/world_1/easy/1-10-e.tscn",
		]
	},
}

## What each level is called, keyed by its scene path.
##
## Every level gets its own name -- the level page shows it under the preview,
## and it is the only place a level is named. A level with nothing here falls
## back to its slot number, so a newly dropped level is never nameless.
const NAMES := {
	"res://scenes/levels/world_1/super_easy/1-1-se.tscn": "First Roll",
	"res://scenes/levels/world_1/super_easy/1-2-se.tscn": "First Turn",
	"res://scenes/levels/world_1/super_easy/1-3-se.tscn": "Round About",
	"res://scenes/levels/world_1/super_easy/1-4-se.tscn": "Tubaloob",
	"res://scenes/levels/world_1/super_easy/1-5-se.tscn": "Take it around town",
	"res://scenes/levels/world_1/easy/1-1-e.tscn": "One Long Shot",
	"res://scenes/levels/world_1/easy/1-2-e.tscn": "Crank Right",
	"res://scenes/levels/world_1/easy/1-3-e.tscn": "Split Decision",
	"res://scenes/levels/world_1/easy/1-4-e.tscn": "Hole Trap",
	"res://scenes/levels/world_1/easy/1-5-e.tscn": "Speed Trap",
	"res://scenes/levels/world_1/easy/1-6-e.tscn": "Hide and Seek",
	"res://scenes/levels/world_1/easy/1-7-e.tscn": "Switchback Central",
	"res://scenes/levels/world_1/easy/1-8-e.tscn": "U-Turn",
	"res://scenes/levels/world_1/easy/1-9-e.tscn": "The Gauntlet",
	"res://scenes/levels/world_1/easy/1-10-e.tscn": "Think Thonker",
}

## What the player last picked in the menu. Written by the level page, read when
## the menu is built again -- coming back from a level should land on that level,
## not at the top of the world list.
##
## Changing scenes cannot carry arguments, and these outlive the change.
static var selected_world := 0
static var selected_chapter := ""
static var selected_level := 0


## The key a set is saved and looked up under. Stable across reorderings, since
## it is built from the world number and the chapter's name.
static func set_id(world: int, chapter: String) -> String:
	return "%d/%s" % [world, chapter]


## Where a chapter sits in the run through a world, counting from 0. -1 for a
## chapter that is not one of `CHAPTERS`.
static func chapter_index(chapter: String) -> int:
	return CHAPTERS.find(chapter)


## What a chapter is called in this world. Falls back to its difficulty, so an
## unnamed chapter reads as "Easy" rather than as a blank line.
static func chapter_name(world: int, chapter: String) -> String:
	var names: Array = CHAPTER_NAMES.get(world, [])
	var index := chapter_index(chapter)

	if index >= 0 and index < names.size():
		return names[index]

	return chapter


## The levels of a set, in play order. Empty for a set nobody has filled in yet.
static func levels_in(world: int, chapter: String) -> Array:
	var chapters: Dictionary = CATALOG.get(world, {})
	return chapters.get(chapter, [])


## The level at a slot, or "" for a slot with nothing built for it yet.
static func level_at(world: int, chapter: String, index: int) -> String:
	var levels := levels_in(world, chapter)
	return levels[index] if index >= 0 and index < levels.size() else ""


## What a level is called. Falls back to its slot number for a level with no
## name of its own, and for an empty slot to the number the slot would hold.
static func name_for(path: String, index: int) -> String:
	if NAMES.has(path):
		return NAMES[path]

	return "Level %d" % (index + 1)


## A level's number and its name together, the way the level page heads the
## preview: "1 - First Roll". A slot with no name of its own is just its number,
## rather than a number printed twice.
static func numbered_name(path: String, index: int) -> String:
	if NAMES.has(path):
		return "%d - %s" % [index + 1, NAMES[path]]

	return "Level %d" % (index + 1)


## The one line the level page heads the preview with: "1:1 - First Roll" -- the
## world, the level's slot in its chapter, and its name.
##
## The world and chapter buttons that used to sit above the preview are gone, so
## this is what has to say where the player is. The chapter is deliberately not
## in it: it is picked in the selector, where the whole run through the world is
## on show, and repeating it here made the line too long to read at a glance.
static func headline(world: int, index: int, path: String) -> String:
	return "%d:%d - %s" % [world, index + 1, name_for(path, index)]


## Which slot a level scene sits in, as `{world, chapter, index}`.
##
## Empty for a level that is not registered -- the scratch test level, or one
## opened straight from the editor. Callers treat that as "not part of a set",
## which is what keeps a loose level from spending lives or banking progress.
static func locate(path: String) -> Dictionary:
	for world in CATALOG:
		for chapter in CATALOG[world]:
			var index: int = CATALOG[world][chapter].find(path)
			if index != -1:
				return {"world": world, "chapter": chapter, "index": index}
	return {}


## The level after `path` within its own set. Empty at the end of a set, or for
## a level that is not registered at all -- a run does not spill into the next
## chapter, since that one has to be unlocked by finishing this one.
static func next_after(path: String) -> String:
	var place := locate(path)
	if place.is_empty():
		return ""
	return level_at(place.world, place.chapter, place.index + 1)
