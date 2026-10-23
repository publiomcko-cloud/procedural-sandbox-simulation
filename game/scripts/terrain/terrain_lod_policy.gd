class_name TerrainLodPolicy
extends RefCounted

## Camera-distance policy for the bounded playable LOD 0/1 slice.
## Thresholds are prototype defaults, not product performance acceptance values.
const COARSE_ENTER_DISTANCE := 56.0
const FINE_RETURN_DISTANCE := 46.0


static func select_lod(distance: float, current_lod: int, enabled: bool = true) -> int:
	if not enabled or not is_finite(distance) or distance < 0.0:
		return 0
	if current_lod == 1:
		return 0 if distance <= FINE_RETURN_DISTANCE else 1
	return 1 if distance >= COARSE_ENTER_DISTANCE else 0
