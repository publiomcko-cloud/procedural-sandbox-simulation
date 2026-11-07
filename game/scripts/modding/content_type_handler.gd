class_name ContentTypeHandler
extends RefCounted

## Engine-owned descriptor for one declarative content family.
## Mods provide data only; handler code is registered by the engine/test harness.
var type_id := ""
var registration_priority := 100
var duplicate_reason := "duplicate_content_record"
var max_records := 0
var validator := Callable()


func _init(
	content_type: String = "",
	priority: int = 100,
	validation_callback: Callable = Callable(),
	duplicate_failure_reason: String = "duplicate_content_record",
	record_limit: int = 0
) -> void:
	type_id = content_type
	registration_priority = priority
	validator = validation_callback
	duplicate_reason = duplicate_failure_reason
	max_records = record_limit


func is_valid() -> bool:
	return (
		not type_id.is_empty()
		and registration_priority >= 0
		and not duplicate_reason.is_empty()
		and max_records >= 0
		and validator.is_valid()
	)


func validate(record: Dictionary, mod_id: String, context: Dictionary) -> Dictionary:
	if not is_valid():
		return {"ok": false, "reason": "content_type_handler_invalid"}
	var result: Variant = validator.call(record, mod_id, context)
	if typeof(result) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "content_type_handler_invalid_result"}
	return result
