class_name PerformanceTrace
extends RefCounted

## Structured opt-in performance tracing for local/owner diagnostics.
## Enable before launching Godot:
##   SANDBOX_PERF_TRACE=1
## Optional threshold for duration-gated events:
##   SANDBOX_PERF_TRACE_MIN_MS=2.0

const ENABLE_ENV := "SANDBOX_PERF_TRACE"
const MIN_MS_ENV := "SANDBOX_PERF_TRACE_MIN_MS"
const DEFAULT_MIN_MS := 2.0


static func is_enabled() -> bool:
	var value := OS.get_environment(ENABLE_ENV).strip_edges().to_lower()
	return value in ["1", "true", "yes", "on"]


static func min_usec() -> int:
	var raw := OS.get_environment(MIN_MS_ENV).strip_edges()
	if raw.is_empty() or not raw.is_valid_float():
		return roundi(DEFAULT_MIN_MS * 1000.0)
	return maxi(0, roundi(raw.to_float() * 1000.0))


static func emit(event: String, payload: Dictionary = {}) -> void:
	var record := payload.duplicate(true)
	record["event"] = event
	record["t_usec"] = Time.get_ticks_usec()
	print("PERF_TRACE " + JSON.stringify(record, "", true, true))


static func emit_duration(
	event: String,
	started_usec: int,
	payload: Dictionary = {},
	force: bool = false
) -> int:
	var duration_usec := Time.get_ticks_usec() - started_usec
	if force or duration_usec >= min_usec():
		var record := payload.duplicate(true)
		record["duration_usec"] = duration_usec
		emit(event, record)
	return duration_usec
