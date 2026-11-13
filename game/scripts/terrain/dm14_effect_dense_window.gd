extends RefCounted

## DM14: exact 5x5 retained -> 9x9 effect-source halo fast path.
## This class is pure. Irregular windows must keep using the authoritative
## runtime's original union algorithm. Output priority must match its
## Chebyshev, Manhattan, y, x comparator for every possible signed center.
const RETAIN_RADIUS := 2
const SOURCE_RADIUS := 2
const TARGET_DIAMETER := RETAIN_RADIUS * 2 + 1
const SOURCE_DIAMETER := TARGET_DIAMETER + SOURCE_RADIUS * 2

static var _ordered_offsets: Array[Vector2i] = []


static func ordered_required(targets: Array[Vector2i]) -> Dictionary:
	if targets.size() != TARGET_DIAMETER * TARGET_DIAMETER:
		return {"ok": false, "reason": "not_dense_window"}
	var minimum := targets[0]
	var maximum := targets[0]
	var unique: Dictionary = {}
	for key in targets:
		if unique.has(key):
			return {"ok": false, "reason": "duplicate_window_region"}
		unique[key] = true
		minimum.x = mini(minimum.x, key.x)
		minimum.y = mini(minimum.y, key.y)
		maximum.x = maxi(maximum.x, key.x)
		maximum.y = maxi(maximum.y, key.y)
	if maximum - minimum != Vector2i(TARGET_DIAMETER - 1, TARGET_DIAMETER - 1):
		return {"ok": false, "reason": "not_square_window"}
	# The unique count and bounds prove that all 25 cells in the rectangle
	# are present, without 625 string IDs or a per-transition 81-item sort.
	var center := minimum + Vector2i(RETAIN_RADIUS, RETAIN_RADIUS)
	var output: Array[Vector2i] = []
	for offset in _offsets():
		output.append(center + offset)
	return {"ok": true, "center": center, "regions": output}


static func _offsets() -> Array[Vector2i]:
	if not _ordered_offsets.is_empty():
		return _ordered_offsets
	var offsets: Array[Vector2i] = []
	var radius := RETAIN_RADIUS + SOURCE_RADIUS
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			offsets.append(Vector2i(x, y))
	offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x), absi(a.y))
		var db := maxi(absi(b.x), absi(b.y))
		if da != db:
			return da < db
		var ma := absi(a.x) + absi(a.y)
		var mb := absi(b.x) + absi(b.y)
		if ma != mb:
			return ma < mb
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	_ordered_offsets = offsets
	return _ordered_offsets
