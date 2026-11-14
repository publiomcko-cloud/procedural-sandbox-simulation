class_name DM23SourceFairQueuePolicy
extends RefCounted

## A bounded fair slot: keep two dispatches in the original urgent order,
## then let the oldest queued source pass if it waited >= 700ms.
## No additional worker tasks, source residency or projection work.
const AGING_THRESHOLD_USEC := 700_000
const URGENT_REORDER_COOLDOWN_USEC := 100_000
const FAIR_SLOT_PERIOD := 3


static func should_repromote(
		last_promoted_usec: int, now_usec: int, queue_index: int) -> bool:
	if queue_index <= 0:
		return false
	if last_promoted_usec < 0:
		return true
	return now_usec - last_promoted_usec >= URGENT_REORDER_COOLDOWN_USEC


static func oldest_eligible_index(
		queue: Array[Vector2i], admitted_usec: Dictionary,
		now_usec: int) -> int:
	if queue.size() <= 1:
		return -1
	var earliest := now_usec
	var winner := -1
	for i in queue.size():
		var coordinate: Vector2i = queue[i]
		if not admitted_usec.has(coordinate):
			continue
		var queued_at := int(admitted_usec[coordinate])
		if queued_at < earliest:
			earliest = queued_at
			winner = i
	return winner if winner >= 0 and now_usec - earliest >= AGING_THRESHOLD_USEC else -1


static func apply_fair_slot(dispatch_sequence: int, eligible_index: int) -> bool:
	return eligible_index > 0 and dispatch_sequence % FAIR_SLOT_PERIOD == FAIR_SLOT_PERIOD - 1
