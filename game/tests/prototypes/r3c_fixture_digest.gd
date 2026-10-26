extends RefCounted

static func sidecar_matches(actual_sha256: String, sidecar_text: String, input_file_name: String, hash_only: bool) -> bool:
	if not _is_lower_sha256(actual_sha256):
		return false
	var normalized := sidecar_text.strip_edges()
	if hash_only:
		return normalized == actual_sha256
	return normalized == actual_sha256 + "  " + input_file_name

static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not (character >= "0" and character <= "9") and not (character >= "a" and character <= "f"):
			return false
	return true
