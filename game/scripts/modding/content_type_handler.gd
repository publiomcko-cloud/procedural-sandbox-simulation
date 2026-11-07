class_name ContentTypeHandler
extends RefCounted

## Engine-owned descriptor for one declarative content family.
## Mods provide data only; handler code is registered by the engine/test harness.
var type_id := ""
var registration_priority := 100
var duplicate_reason := "duplicate_content_record"
var max_records := 0
var validator := Callable()
var normalizer := Callable()


func _init(
	content_type: String = "",
	priority: int = 100,
	validation_callback: Callable = Callable(),
	duplicate_failure_reason: String = "duplicate_content_record",
	record_limit: int = 0,
	normalization_callback: Callable = Callable()
) -> void:
	type_id = content_type
	registration_priority = priority
	validator = validation_callback
	duplicate_reason = duplicate_failure_reason
	max_records = record_limit
	normalizer = normalization_callback


func is_valid() -> bool:
	return (
		not type_id.is_empty()
		and registration_priority >= 0
		and not duplicate_reason.is_empty()
		and max_records >= 0
		and validator.is_valid()
	)


func prepare(record: Dictionary, mod_id: String, context: Dictionary) -> Dictionary:
	if not is_valid():
		return {"ok": false, "reason": "content_type_handler_invalid"}
	var validation: Variant = validator.call(record.duplicate(true), mod_id, context)
	if typeof(validation) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "content_type_handler_invalid_result"}
	if not validation.get("ok", false):
		return validation
	var normalized := record.duplicate(true)
	if normalizer.is_valid():
		var normalization: Variant = normalizer.call(
			record.duplicate(true), mod_id, context
		)
		if typeof(normalization) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "content_type_handler_invalid_normalization"}
		if not normalization.get("ok", false):
			return normalization
		if not normalization.get("record") is Dictionary:
			return {"ok": false, "reason": "content_type_handler_invalid_normalization"}
		normalized = (normalization["record"] as Dictionary).duplicate(true)
	return {"ok": true, "reason": "ok", "record": normalized}


func validate(record: Dictionary, mod_id: String, context: Dictionary) -> Dictionary:
	var prepared := prepare(record, mod_id, context)
	if not prepared.get("ok", false):
		return prepared
	return {"ok": true, "reason": "ok"}
