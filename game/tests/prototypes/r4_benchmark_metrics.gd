extends RefCounted

## Recursively totals bytes in a disposable benchmark directory.
## Returns -1 when any directory or file cannot be read.
static func directory_bytes(path: String) -> int:
	if not DirAccess.dir_exists_absolute(path):
		return 0
	var total := 0
	var pending: Array[String] = [path]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var directory := DirAccess.open(current)
		if directory == null:
			return -1
		directory.list_dir_begin()
		var entry := directory.get_next()
		while not entry.is_empty():
			if entry != "." and entry != "..":
				var child := current.path_join(entry)
				if directory.current_is_dir():
					pending.append(child)
				else:
					var file := FileAccess.open(child, FileAccess.READ)
					if file == null:
						directory.list_dir_end()
						return -1
					total += file.get_length()
					file.close()
			entry = directory.get_next()
		directory.list_dir_end()
	return total
