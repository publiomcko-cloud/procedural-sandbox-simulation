class_name SharedSurfaceWorkCache
extends RefCounted

## Thread-safe bounded cache/coalescer for immutable shared-surface CPU results.
## Duplicate X/Z pair and four-region corner requests at the same ledger state
## share one polygonization result instead of rebuilding the same volume.

const MAX_RESULTS := 96

static var _mutex := Mutex.new()
static var _cache: Dictionary = {}
static var _order: Array[String] = []
static var _inflight: Dictionary = {}


static func get_or_build(key: String, builder: Callable) -> Dictionary:
	if key.is_empty() or not builder.is_valid():
		return {"valid": false, "reason": "shared_work_cache_invalid_request"}
	while true:
		_mutex.lock()
		if _cache.has(key):
			var cached: Dictionary = _cache[key]
			_mutex.unlock()
			return cached
		if _inflight.has(key):
			var entry: Dictionary = _inflight[key]
			var semaphore: Semaphore = entry["semaphore"]
			entry["waiters"] = int(entry.get("waiters", 0)) + 1
			_inflight[key] = entry
			_mutex.unlock()
			semaphore.wait()
			continue
		var semaphore := Semaphore.new()
		_inflight[key] = {"semaphore": semaphore, "waiters": 0}
		_mutex.unlock()

		var built: Dictionary = builder.call()

		_mutex.lock()
		var completed: Dictionary = _inflight.get(key, {})
		var waiter_count := int(completed.get("waiters", 0))
		var completed_semaphore: Semaphore = completed.get("semaphore", semaphore)
		_cache[key] = built
		_order.append(key)
		while _order.size() > MAX_RESULTS:
			var oldest := _order.pop_front()
			if oldest != key:
				_cache.erase(oldest)
		_inflight.erase(key)
		_mutex.unlock()
		for _index in range(waiter_count):
			completed_semaphore.post()
		return built


static func clear() -> void:
	_mutex.lock()
	if _inflight.is_empty():
		_cache.clear()
		_order.clear()
	_mutex.unlock()


static func result_count() -> int:
	_mutex.lock()
	var count := _cache.size()
	_mutex.unlock()
	return count
