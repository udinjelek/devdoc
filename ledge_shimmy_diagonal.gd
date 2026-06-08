extends CharacterBody3D
# =============================================================================
# DIAGONAL LEDGE SHIMMY — detection helper
# -----------------------------------------------------------------------------
# Drop-in piece for a ledge-hang state. Focuses on ONE thing:
# while shimmying sideways, reuse the down-facing LEDGE probe to read how much
# the edge rises/falls per step. Within MAX_DIAGONAL -> shimmy across AND move
# the character vertically to follow the edge. Beyond it -> too steep, stop
# (treated as the same "blocked" outcome as Case 2 / Case 3).
#
# No extra ray is needed for the slope: the LEDGE probe's hit height does both
# jobs (presence + slope), exactly like the stair snap re-finds the floor.
# =============================================================================

# ─── Settings ────────────────────────────────────────────────────────────────
@export var SHIMMY_SPEED   : float = 1.5   # sideways metres per second while hanging
@export var SHIMMY_STEP    : float = 0.30  # how far ahead the probe looks sideways (~one step)
@export var GRIP_REACH     : float = 0.40  # how far in front of the body the edge sits
@export var GRIP_HEIGHT    : float = 1.30  # distance from body origin up to the grip/hands
@export var PROBE_UP       : float = 0.50  # start the down-probe this far above expected edge

# The important one you asked for: max vertical change per shimmy step before
# the ledge counts as "too steep" and we stop. (metres)
@export var MAX_DIAGONAL   : float = 0.25

@export var DEBUG_SHIMMY   : bool = false


# ─── Result enum so the caller knows what happened ───────────────────────────
enum ShimmyResult { CONTINUE, BLOCKED }


# =============================================================================
# Call this every physics frame while in the ledge-hang state.
#   dir   : +1 = shimmy right, -1 = shimmy left
#   delta : physics delta
# Returns CONTINUE (moved) or BLOCKED (too steep / no edge -> stop, play idle).
# =============================================================================
func shimmy_step(dir: int, delta: float) -> ShimmyResult:
	if dir == 0:
		return ShimmyResult.CONTINUE   # not moving, nothing to do

	# Current grip height = where the hands are right now.
	var current_grip_y : float = global_position.y + GRIP_HEIGHT

	# Sideways + forward basis from the character's facing.
	var side    : Vector3 = global_transform.basis.x * float(dir)
	var forward : Vector3 = -global_transform.basis.z

	# --- LEDGE probe (ray 3): down-cast at the NEXT sideways position ---------
	# Offset sideways by one step and forward to where the edge sits, start a
	# bit above the expected grip, and look down past the diagonal limit.
	var probe_origin : Vector3 = global_position \
		+ side * SHIMMY_STEP \
		+ forward * GRIP_REACH \
		+ Vector3.UP * (GRIP_HEIGHT + PROBE_UP)
	var probe_end : Vector3 = probe_origin \
		+ Vector3.DOWN * (PROBE_UP + MAX_DIAGONAL * 2.0)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(probe_origin, probe_end)
	query.exclude = [self]
	var hit := space.intersect_ray(query)

	# No edge ahead at all -> nothing to grab -> blocked (cut / dead end).
	if hit.is_empty():
		if DEBUG_SHIMMY: print("[SHIMMY] no edge ahead -> BLOCKED")
		return ShimmyResult.BLOCKED

	# --- slope test -----------------------------------------------------------
	var new_edge_y : float = hit.position.y
	var step_dy : float = new_edge_y - current_grip_y   # +up / -down
	var slope : float = abs(step_dy)

	if DEBUG_SHIMMY:
		print("[SHIMMY] edge y=", new_edge_y, "  step_dy=", step_dy,
			"  slope=", slope, "  (max=", MAX_DIAGONAL, ")")

	# Too steep -> the edge effectively rises/drops into a wall or gap.
	# Fold into the existing stop outcome (Case 2 / Case 3).
	if slope > MAX_DIAGONAL:
		if DEBUG_SHIMMY: print("[SHIMMY] too steep -> BLOCKED (case 2/3)")
		return ShimmyResult.BLOCKED

	# --- CONTINUE: move sideways AND follow the edge vertically ---------------
	# Horizontal slide this frame.
	global_position += side * SHIMMY_SPEED * delta
	# Vertical follow: shift Y by the measured diagonal so the hands stay on
	# the edge. Scaled to how far we actually moved sideways this frame, so a
	# gentle slope feels smooth instead of snapping the whole step at once.
	var moved_frac : float = (SHIMMY_SPEED * delta) / SHIMMY_STEP
	global_position.y += step_dy * clamp(moved_frac, 0.0, 1.0)

	if DEBUG_SHIMMY: print("[SHIMMY] CONTINUE  new y=", global_position.y)
	return ShimmyResult.CONTINUE


# =============================================================================
# Example usage inside your hang state:
#
#   func _physics_process(delta):
#       var dir := 0
#       if Input.is_action_pressed("shimmy_right"): dir = 1
#       elif Input.is_action_pressed("shimmy_left"): dir = -1
#
#       var result := shimmy_step(dir, delta)
#       if result == ShimmyResult.BLOCKED:
#           # ── ANIMATION HOOK ──
#           # _anim.play("hang_idle")        # reached and stopped
#           pass
#       else:
#           # ── ANIMATION HOOK ──
#           # _anim.play("shimmy_" + ("right" if dir > 0 else "left"))
#           pass
# =============================================================================
