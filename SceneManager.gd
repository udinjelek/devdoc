extends Node

# =============================================================================
# SceneManager.gd
# =============================================================================
# This is the ROOT of the game. It is never destroyed. It owns one child slot,
# "CurrentScene", where the active screen lives (title, stage select, a level).
# Switching screens = free the old child, add the new one.
#
# Scene structure (set this as your Main Scene in Project Settings):
#
#   Main (Node)              <- attach this script, this is the root
#   └── CurrentScene (Node)  <- the active screen is added here as a child
#
# Each LEVEL scene is expected to contain its own Player node, and one or more
# Marker3D spawn points named per entrance (e.g. "from_castle", "from_select").
# Title / menu scenes simply have no Player — the spawn step is skipped.
#
# USAGE (call from anywhere):
#   SceneManager.go_to("res://screens/title.tscn")               # no spawn
#   SceneManager.go_to("res://levels/town.tscn", "from_castle")  # spawn at marker
# =============================================================================

# --- CONFIG -----------------------------------------------------------------
@export var FIRST_SCENE   : String = "res://screens/title.tscn"
@export var PLAYER_GROUP  : String = "player"   # Player node must join this group
# ----------------------------------------------------------------------------

@onready var _slot : Node = $CurrentScene

# Remembered between calls
var _current_path : String = ""


func _ready() -> void:
	# Load the very first screen on startup
	if FIRST_SCENE != "":
		go_to(FIRST_SCENE)


# =============================================================================
# PUBLIC API
# =============================================================================
# path       : res:// path to the .tscn to load
# spawn_name : optional name of a Marker3D in the new scene to place the player.
#              Leave empty ("") to just load the scene as-is (title, menus, or
#              a level where you don't care where the player starts).
func go_to(path: String, spawn_name: String = "") -> void:

	# ----------------------------------------------------------------------
	# TRANSITION HOOK (OUT)
	# When you wire up the shatter / fade transition, trigger the "cover the
	# screen" half HERE, await it, THEN continue to the swap below. e.g.:
	#
	#   await Transition.play_out()
	#
	# Leaving it inline (instant) for now.
	# ----------------------------------------------------------------------

	_swap_scene(path, spawn_name)

	# ----------------------------------------------------------------------
	# TRANSITION HOOK (IN)
	# After the new scene is in and the player is positioned, trigger the
	# "reveal" half of the transition here. e.g.:
	#
	#   await Transition.play_in()
	# ----------------------------------------------------------------------


# =============================================================================
# INTERNAL
# =============================================================================
func _swap_scene(path: String, spawn_name: String) -> void:

	# --- Remove the old screen --------------------------------------------
	# remove_child + queue_free (instead of queue_free alone) so the old
	# scene's nodes leave the tree THIS frame. Otherwise a stale player from
	# the previous scene could still be found by the group lookup below.
	for child in _slot.get_children():
		_slot.remove_child(child)
		child.queue_free()

	# --- Load the new scene -----------------------------------------------
	# INSTANT LOAD (current). Fine for prototyping; small freeze on big levels.
	var packed : PackedScene = load(path)
	if packed == null:
		push_error("SceneManager: could not load scene at " + path)
		return

	# ----------------------------------------------------------------------
	# BACKGROUND / THREADED LOAD (DO LATER)
	# When levels get big and the instant load causes a noticeable freeze,
	# come back here and replace the load() above with threaded loading so a
	# loading screen can show while it works. Rough shape:
	#
	#   ResourceLoader.load_threaded_request(path)
	#   while true:
	#       var status = ResourceLoader.load_threaded_get_status(path)
	#       if status == ResourceLoader.THREAD_LOAD_LOADED:
	#           packed = ResourceLoader.load_threaded_get(path)
	#           break
	#       # update a progress bar with the status array here
	#       await get_tree().process_frame
	#
	# Keep the instant version for now.
	# ----------------------------------------------------------------------

	var instance : Node = packed.instantiate()
	_slot.add_child(instance)
	_current_path = path

	# --- Position the player (only if a spawn name was given) -------------
	if spawn_name != "":
		_place_player_at_spawn(instance, spawn_name)


# Find the player (already inside the level) and move it to the named marker.
# Skips silently if there is no player or no matching marker — this is what
# makes title/menu screens "just load" with no errors.
func _place_player_at_spawn(scene_root: Node, spawn_name: String) -> void:

	# Find the player via group. Each level's Player node should be added to
	# the group set in PLAYER_GROUP (Node > Groups tab in the editor).
	var players := get_tree().get_nodes_in_group(PLAYER_GROUP)
	if players.is_empty():
		# No player in this scene (e.g. a menu) — nothing to place.
		return
	var player : Node3D = players[0]

	# Find the spawn marker by name anywhere under the loaded scene.
	var marker := scene_root.find_child(spawn_name, true, false)
	if marker == null or not (marker is Node3D):
		push_warning("SceneManager: spawn marker '" + spawn_name + "' not found in " + _current_path)
		return

	# Move the player onto the marker.
	player.global_transform = (marker as Node3D).global_transform


# Optional helper: reload the current scene (handy for "restart level").
func reload_current(spawn_name: String = "") -> void:
	if _current_path != "":
		go_to(_current_path, spawn_name)
