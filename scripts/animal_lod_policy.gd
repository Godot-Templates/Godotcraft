class_name AnimalLodPolicy
extends RefCounted

## Shared distance tiers for passive animal simulation.

enum Tier { FULL, THROTTLED, SLEEPING }

const FULL_SIM_DISTANCE: float = 24.0
const SLEEP_DISTANCE: float = 48.0
const MID_SIM_INTERVAL: float = 0.125  # 8 Hz


static func tier_for_distance_squared(distance_squared: float) -> Tier:
	if distance_squared > SLEEP_DISTANCE * SLEEP_DISTANCE:
		return Tier.SLEEPING
	if distance_squared > FULL_SIM_DISTANCE * FULL_SIM_DISTANCE:
		return Tier.THROTTLED
	return Tier.FULL
