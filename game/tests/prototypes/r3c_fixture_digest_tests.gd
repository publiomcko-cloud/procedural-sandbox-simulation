extends SceneTree

const FixtureDigest := preload("res://tests/prototypes/r3c_fixture_digest.gd")
const HASH := "54a6f3a684f0d3b322a5eca491bac30d23f77c6dd56eb3fda88acd8d7fbc62c1"
const NAME := "P31.EDIT.CONCENTRATED.N0256.v1.R01.commands.json"

var _assertions := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(FixtureDigest.sidecar_matches(HASH, HASH + "  " + NAME + "\r\n", NAME, false), "sha256sum_sidecar_exact_hash_and_name")
	_expect(FixtureDigest.sidecar_matches(HASH, HASH + "\n", NAME, true), "hash_only_r3c_sidecar")
	_expect(not FixtureDigest.sidecar_matches(HASH, HASH + "  altered.json", NAME, false), "wrong_sha256sum_filename_rejected")
	_expect(not FixtureDigest.sidecar_matches(HASH, "0".repeat(64) + "  " + NAME, NAME, false), "wrong_hash_rejected")
	_expect(not FixtureDigest.sidecar_matches(HASH, HASH + "  " + NAME, NAME, true), "sha_only_contract_rejects_filename_suffix")
	_expect(not FixtureDigest.sidecar_matches(HASH.to_upper(), HASH.to_upper(), NAME, true), "uppercase_hash_rejected")
	_expect(not FixtureDigest.sidecar_matches("bad", "bad", NAME, true), "malformed_actual_digest_rejected")
	_expect(not FixtureDigest.sidecar_matches(HASH, HASH + " " + NAME, NAME, false), "noncanonical_single_space_rejected")
	if _failures.is_empty():
		print("R3C_FIXTURE_DIGEST_TESTS_PASS assertions=%d" % _assertions)
		quit(0)
	else:
		push_error("R3C_FIXTURE_DIGEST_TESTS_FAIL assertions=%d failures=%s" % [_assertions, ";".join(_failures)])
		quit(1)

func _expect(condition: bool, name: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(name)
