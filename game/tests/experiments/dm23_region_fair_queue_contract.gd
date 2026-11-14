extends SceneTree

const Policy := preload("res://scripts/terrain/dm23_source_fair_queue_policy.gd")
const Probe := preload("res://scripts/diagnostics/dm23_region_lifecycle_probe.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var queue: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)
	]
	var times := {
		Vector2i(0, 0): 700_000,
		Vector2i(1, 0): 600_000,
		Vector2i(2, 0): 100_000
	}
	_check(Policy.oldest_eligible_index(queue, times, 900_000) == 2,
		"oldest eligible source behind urgent head")
	_check(Policy.oldest_eligible_index(queue, times, 300_000) == -1,
		"no aged source within threshold")
	_check(Policy.oldest_eligible_index([], times, 900_000) == -1,
		"empty source queue")
	_check(not Policy.should_repromote(100_000, 180_000, 2),
		"cooldown rejects repeated scope promotion")
	_check(Policy.should_repromote(100_000, 200_000, 2),
		"promotion allowed after 100ms")
	_check(Policy.should_repromote(-1, 100_000, 2),
		"first promotion allowed")
	_check(not Policy.should_repromote(-1, 200_000, 0),
		"front scope is not needlessly requeued")
	_check(not Policy.apply_fair_slot(0, 2), "first slot urgent")
	_check(not Policy.apply_fair_slot(1, 2), "second slot urgent")
	_check(Policy.apply_fair_slot(2, 2), "third slot old source")
	_check(not Policy.apply_fair_slot(2, -1), "no valid aged source")
	_check(not Policy.apply_fair_slot(5, 0), "already head does not preempt")

	var probe := Probe.new()
	var region := "region:5,5"
	probe.begin(region, 31, 1_000_000, false, false)
	probe.first_prepare(region, 31, 1_050_000,
		[Vector2i(5, 6), Vector2i(6, 6)], true)
	probe.source_published("region:5,6", 1_400_000,
		{"queue": 350_000, "generation": 2200, "projection": 80000})
	probe.source_published("region:6,6", 1_600_000,
		{"queue": 500_000, "generation": 2500, "projection": 82000})
	probe.first_prepare(region, 31, 1_610_000, [], false)
	probe.first_submitted(region, 31, 1_620_000)
	probe.focus_enter(region, 31, 1_650_000)
	probe.published(region, 31, 1_900_000)
	var r := probe.summary()
	_check(int(r["counts"]["started_as_neighbor"]) == 1, "stage started as neighbor")
	_check(int(r["counts"]["neighbor_became_focus"]) == 1, "focus entry observed")
	_check(int(r["counts"]["neighbor_first_chunk_already_submitted_before_focus"]) == 1,
		"neighbor first chunk already submitted")
	_check(int(r["counts"]["neighbor_published_before_focus"]) == 0,
		"published after focus")
	_check(int(r["counts"]["canonical_loads_published"]) == 1, "canonical publish")
	_check(int(r["counts"]["stage_dependency_scope_resolved"]) == 2,
		"two exact dependency notifications")
	_check(int(r["counts"]["stage_dependency_rendezvous"]) == 1,
		"last dependency resolved")
	_check(int(r["latency"]["stage_age_at_focus_ms"]["mean_ms"]) == 650,
		"neighbor age at entry")
	_check(int(r["latency"]["first_attempt_to_dispatch_ms"]["mean_ms"]) == 570,
		"first chunk waited for dependencies")
	_check(int(r["latency"]["last_source_to_first_dispatch_ms"]["mean_ms"]) == 20,
		"last publication to dispatch")
	_check(int(r["last_dependency_dominant_phase"]["queue"]) == 1,
		"queue dominates true last source")
	_check(String(r["last_dependency_scopes"][0]["scope"]) == "region:6,6",
		"critical source exact identity")
	_check(int(r["latency"]["focus_entry_to_publish_ms"]["mean_ms"]) == 250,
		"publication since focal entry")
	_check(int(r["active_stages"]) == 0, "published stage left ledger")
	probe.focus_enter(region, -1, 1_920_000)
	_check(int(probe.summary()["counts"]["focus_enter_without_active_load_stage"]) == 1,
		"focal visit without active stage safely recorded")

	probe.begin("region:4,4", 33, 2_000_000, false, false)
	probe.focus_enter("region:4,4", 33, 2_050_000)
	probe.first_prepare("region:4,4", 33, 2_055_000, [Vector2i(5, 5)], true)
	probe.source_published("region:5,5", 2_120_000,
		{"queue": 100000, "generation": 2500, "projection": 80000})
	probe.first_submitted("region:4,4", 33, 2_125_000)
	probe.published("region:4,4", 33, 2_300_000)
	var r2 := probe.summary()
	_check(int(r2["counts"]["neighbor_first_chunk_still_pending_at_focus"]) == 1,
		"neighbor entered focus before first job")
	_check(int(r2["latency"]["focus_entry_to_first_dispatch_ms"]["mean_ms"]) == 75,
		"focus-to-submit delay")
	probe.begin("region:3,3", 34, 3_000_000, false, false)
	probe.first_prepare("region:3,3", 34, 3_020_000, [Vector2i(7, 7)], true)
	probe.cancelled("region:3,3", 34, "left_window")
	_check(int(probe.summary()["counts"]["cancelled_before_first_chunk"]) == 1,
		"discarded neighbor stage")
	_check(int(probe.summary()["active_stages"]) == 0,
		"no orphan stage after cancellation")

	probe.begin("region:8,8", 35, 4_000_000, false, true)
	probe.first_submitted("region:8,8", 35, 4_010_000)
	probe.published("region:8,8", 35, 4_050_000)
	probe.focus_enter("region:8,8", -1, 4_100_000)
	_check(int(probe.summary()["counts"]["published_before_focus"]) == 1,
		"published neighbor later entered focus")
	_check(int(probe.summary()["counts"]["dm18_cache_stages"]) == 1,
		"cache history retained without changing authority")
	_check(int(probe.summary()["recent_published_stages"]) == 0,
		"recent record consumed once")

	print("DM23_CONTRACT_RESULT=" + JSON.stringify({
		"checks": checks, "failures": failures
	}))
	print("DM23_CONTRACT_%s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DM23_CONTRACT_FAILURE: " + reason)
