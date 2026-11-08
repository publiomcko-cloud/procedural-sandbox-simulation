class_name ContentTypeHandler
extends RefCounted

## Engine-owned descriptor for one declarative content family.
## Mods provide data only; handler code is registered by the engine/test harness.
##
## Callback targets are held weakly. A registry may own handlers whose built-in
## callbacks point back to that same registry without creating a RefCounted
## ownership cycle.
var type_id := ""
var registration_priority := 100
var duplicate_reason := "duplicate_content_record"
var max_records := 0

var _validator_target: WeakRef
var _validator_method := ""
var _normalizer_target: WeakRef
var _normalizer_method := ""


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
	duplicate_reason = duplicate_failure_reason
	max_records = record_limit
	_capture_validator(validation_callback)
	_capture_normalizer(normalization_callback)


func _capture_validator(callback: Callable) -> void:
	if not callback.is_valid():
		return
	var target: Object = callback.get_object()
	if target == null:
		return
	_validator_target = weakref(target)
	_validator_method = String(callback.get_method())


func _capture_normalizer(callback: Callable) -> void:
	if not callback.is_valid():
		return
	var target: Object = callback.get_object()
	if target == null:
		return
	_normalizer_target = weakref(target)
	_normalizer_method = String(callback.get_method())


func is_valid() -> bool:
	return (
		not type_id.is_empty()
		and registration_priority >= 0
		and not duplicate_reason.is_empty()
		and max_records >= 0
		and _validator_target != null
		and _validator_target.get_ref() != null
		and not _validator_method.is_empty()
	)


func prepare(record: Dictionary, mod_id: String, context: Dictionary) -> Dictionary:
	if not is_valid():
		return {"ok": false, "reason": "content_type_handler_invalid"}
	var validator_target: Object = _validator_target.get_ref()
	if validator_target == null:
		return {"ok": false, "reason": "content_type_handler_target_released"}
	var validation_value: Variant = validator_target.call(
		_validator_method, record.duplicate(true), mod_id, context
	)
	if typeof(validation_value) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "content_type_handler_invalid_result"}
	var validation: Dictionary = validation_value
	if not validation.get("ok", false):
		return validation

	var normalized: Dictionary = record.duplicate(true)
	if _normalizer_target != null and not _normalizer_method.is_empty():
		var normalizer_target: Object = _normalizer_target.get_ref()
		if normalizer_target == null:
			return {"ok": false, "reason": "content_type_handler_target_released"}
		var normalization_value: Variant = normalizer_target.call(
			_normalizer_method, record.duplicate(true), mod_id, context
		)
		if typeof(normalization_value) != TYPE_DICTIONARY:
			return {
				"ok": false,
				"reason": "content_type_handler_invalid_normalization",
			}
		var normalization: Dictionary = normalization_value
		if not normalization.get("ok", false):
			return normalization
		if not normalization.get("record") is Dictionary:
			return {
				"ok": false,
				"reason": "content_type_handler_invalid_normalization",
			}
		var normalized_record: Dictionary = normalization["record"]
		normalized = normalized_record.duplicate(true)
		if (
			String(normalized.get("type", "")) != String(record.get("type", ""))
			or String(normalized.get("id", "")) != String(record.get("id", ""))
			or int(normalized.get("schema_version", -1))
				!= int(record.get("schema_version", -2))
		):
			return {
				"ok": false,
				"reason": "content_type_handler_normalization_changed_identity",
			}
		var normalized_validation_value: Variant = validator_target.call(
			_validator_method, normalized.duplicate(true), mod_id, context
		)
		if typeof(normalized_validation_value) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "content_type_handler_invalid_result"}
		var normalized_validation: Dictionary = normalized_validation_value
		if not normalized_validation.get("ok", false):
			return normalized_validation
	return {"ok": true, "reason": "ok", "record": normalized}


func validate(record: Dictionary, mod_id: String, context: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare(record, mod_id, context)
	if not prepared.get("ok", false):
		return prepared
	return {"ok": true, "reason": "ok"}
