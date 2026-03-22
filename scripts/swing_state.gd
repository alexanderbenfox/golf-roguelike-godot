class_name SwingState
extends RefCounted

## Two-phase swing timing state machine.
##
## Phase flow:
##   IDLE → press → POWER_FILL (indicator 0→100%)
##        → release → COMPLETE (result ready for GolfBall)
##
## Overshoot determines accuracy: releasing right at 100% = perfect aim,
## holding past 100% = increasing deviation the longer you hold.
## Power output follows a cubic curve so the bottom of the bar is
## fine-grained and the top ramps up sharply.

# -- Enums -------------------------------------------------------------------

enum Phase { IDLE, POWER_FILL, COMPLETE }

enum SwingResult { PERFECT, GOOD, OK, MISS }

# -- Signals ------------------------------------------------------------------

signal phase_changed(new_phase: Phase)
signal swing_complete(result: SwingOutcome)

# -- Outcome data class -------------------------------------------------------

class SwingOutcome:
	var power_percent: float       ## 0.0–1.0 (cubic-curved), actual power to apply
	var accuracy_result: int       ## SwingResult enum value (for UI feedback)
	var deviation_deg: float       ## Signed deviation in degrees (+ = right, - = left)
	var power_bonus: float         ## Multiplier (1.05 for perfect, 0.90 for miss)
	var overshoot_amount: float    ## 0.0 = none, grows continuously while holding past 100%

# -- State --------------------------------------------------------------------

var phase: Phase = Phase.IDLE
var result: SwingOutcome = null

## Club params (set before starting)
var fill_speed: float = 5.0        ## rate multiplier (fill_speed * 10 = %/sec)
var sweet_spot_scale: float = 1.0  ## multiplier on overshoot forgiveness
var player_accuracy: float = 1.0   ## from PlayerState, widens forgiveness

# Internal state
var _power_percent: float = 0.0    ## 0–100 during fill (clamped for UI)
var _overshoot: float = 0.0        ## accumulated overshoot past 100% (0–∞)
var _is_overshooting: bool = false

# -- Constants ----------------------------------------------------------------

## Maximum aim deviation at extreme overshoot (degrees).
const MAX_DEVIATION_DEG: float = 30.0

## Overshoot thresholds for UI result labels (compared against scaled overshoot).
const PERFECT_THRESHOLD: float = 0.01
const GOOD_THRESHOLD: float = 0.06
const OK_THRESHOLD: float = 0.15

## Power bonus/penalty per result
const POWER_BONUS_TABLE: Dictionary = {
	0: 1.05,   # PERFECT: +5%
	1: 1.0,    # GOOD: no change
	2: 0.95,   # OK: -5%
	3: 0.85,   # MISS: -15%
}

# -- Public API ---------------------------------------------------------------

## Configure from a ClubDefinition before starting.
func configure(club: ClubDefinition, accuracy: float, _auto_accuracy: bool = false) -> void:
	fill_speed = club.swing_fill_speed
	sweet_spot_scale = club.sweet_spot_scale
	player_accuracy = accuracy


## Call when player presses/releases the shoot button.
## Returns true if the input was consumed.
func press() -> bool:
	match phase:
		Phase.IDLE:
			_start_power_fill()
			return true
		Phase.POWER_FILL:
			_lock_power()
			return true
		Phase.COMPLETE:
			return false
	return false


## Advance the state machine by delta seconds. Call every frame while active.
func update(delta: float) -> void:
	if phase == Phase.POWER_FILL:
		_update_power_fill(delta)


## Reset to idle for next shot.
func reset() -> void:
	phase = Phase.IDLE
	result = null
	_power_percent = 0.0
	_overshoot = 0.0
	_is_overshooting = false


## Current power indicator position (0.0–1.0) for UI bar positioning.
func get_power_normalized() -> float:
	return _power_percent / 100.0


## Current overshoot amount (0.0 = none, grows continuously).
func get_overshoot() -> float:
	return _overshoot


func is_active() -> bool:
	return phase == Phase.POWER_FILL


## True when the player is holding past 100%.
func is_overshooting() -> bool:
	return _is_overshooting


# -- Internal: Power Fill -----------------------------------------------------

func _start_power_fill() -> void:
	_power_percent = 0.0
	_overshoot = 0.0
	_is_overshooting = false
	phase = Phase.POWER_FILL
	phase_changed.emit(Phase.POWER_FILL)


func _update_power_fill(delta: float) -> void:
	var rate: float = fill_speed * 10.0

	if _is_overshooting:
		# Already at 100% — accumulate overshoot over time
		_overshoot += rate * delta / 100.0
	else:
		_power_percent += rate * delta
		if _power_percent >= 100.0:
			# First frame hitting 100 — capture excess as initial overshoot
			var excess: float = _power_percent - 100.0
			_overshoot = excess / 100.0
			_power_percent = 100.0
			_is_overshooting = true


func _lock_power() -> void:
	# Scale overshoot by club forgiveness and player accuracy
	var tolerance: float = sweet_spot_scale * clampf(player_accuracy, 0.5, 2.0)
	var scaled_overshoot: float = _overshoot / maxf(tolerance, 0.01)

	# Continuous deviation — scales linearly with overshoot, capped at MAX
	var deviation: float = clampf(scaled_overshoot, 0.0, 1.0) * MAX_DEVIATION_DEG

	# Categorize for UI feedback
	var swing_result: int
	if scaled_overshoot < PERFECT_THRESHOLD:
		swing_result = SwingResult.PERFECT
	elif scaled_overshoot < GOOD_THRESHOLD:
		swing_result = SwingResult.GOOD
	elif scaled_overshoot < OK_THRESHOLD:
		swing_result = SwingResult.OK
	else:
		swing_result = SwingResult.MISS

	# Random left/right deviation direction
	var side: float = 1.0 if randf() > 0.5 else -1.0
	if _overshoot < 0.001:
		side = 0.0

	result = SwingOutcome.new()
	result.power_percent = _power_percent / 100.0
	result.accuracy_result = swing_result
	result.overshoot_amount = _overshoot
	result.deviation_deg = deviation * side
	result.power_bonus = POWER_BONUS_TABLE[swing_result]

	phase = Phase.COMPLETE
	phase_changed.emit(Phase.COMPLETE)
	swing_complete.emit(result)
