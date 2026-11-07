class_name ProceduralObjectBatchPreparationJob
extends RefCounted

## D.7.2 worker-only regional render preparation. It transforms and concatenates
## immutable CPU geometry into final regional vertex/normal arrays. It never
## creates ArrayMesh, Material, Node, RenderingServer or other render resources.
const StaticBatchBuilder := preload(
	"res://scripts/objects/procedural_object_static_batch.gd"
)

var static_items: Array[Dictionary] = []
var mutable_groups: Dictionary = {}
var result: Dictionary = {}
var worker_started_usec := 0
var worker_finished_usec := 0
var worker_thread_id := 0


func _init(
	static_values: Array[Dictionary],
	mutable_values: Dictionary
) -> void:
	for value in static_values:
		static_items.append(value.duplicate(false))
	for group_key_value in mutable_values:
		var group_key := String(group_key_value)
		var copied: Array[Dictionary] = []
		for item_value in (mutable_values[group_key_value] as Array):
			copied.append((item_value as Dictionary).duplicate(false))
		mutable_groups[group_key] = copied


func run() -> void:
	worker_started_usec = Time.get_ticks_usec()
	worker_thread_id = OS.get_thread_caller_id()
	if not _all_cpu_backed(static_items):
		result = {
			"ok": false,
			"reason": "batch_prepare_static_cpu_source_missing",
		}
		_finish()
		return
	var static_prepared := StaticBatchBuilder.prepare(static_items)
	if not static_prepared.get("ok", false):
		result = {
			"ok": false,
			"reason": "batch_prepare_static_failed:%s"
				% static_prepared.get("reason", "unknown"),
		}
		_finish()
		return

	var mutable_prepared: Dictionary = {}
	var mutable_keys: Array[String] = []
	for key_value in mutable_groups:
		mutable_keys.append(String(key_value))
	mutable_keys.sort()
	for group_key in mutable_keys:
		var items: Array[Dictionary] = []
		for item_value in (mutable_groups[group_key] as Array):
			items.append(item_value as Dictionary)
		if not _all_cpu_backed(items):
			result = {
				"ok": false,
				"reason": "batch_prepare_mutable_cpu_source_missing",
				"group_key": group_key,
			}
			_finish()
			return
		var prepared := StaticBatchBuilder.prepare(items)
		if not prepared.get("ok", false):
			result = {
				"ok": false,
				"reason": "batch_prepare_mutable_failed:%s"
					% prepared.get("reason", "unknown"),
				"group_key": group_key,
			}
			_finish()
			return
		mutable_prepared[group_key] = prepared

	result = {
		"ok": true,
		"reason": "ok",
		"static": static_prepared,
		"mutable": mutable_prepared,
		"static_instance_count": static_items.size(),
		"mutable_group_count": mutable_prepared.size(),
	}
	_finish()


func _all_cpu_backed(items: Array[Dictionary]) -> bool:
	for item in items:
		var cpu_value: Variant = item.get("cpu_data", {})
		if (
			typeof(cpu_value) != TYPE_DICTIONARY
			or not (cpu_value as Dictionary).get("ok", false)
		):
			return false
	return true


func _finish() -> void:
	worker_finished_usec = Time.get_ticks_usec()
	result["worker_usec"] = worker_finished_usec - worker_started_usec
	result["worker_thread_id"] = worker_thread_id
