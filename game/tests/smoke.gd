extends SceneTree

# Initial L2 check only, not a world-simulation test.
func _initialize() -> void:
    var errors := 0
    var seed_a := 12345
    var seed_b := 12345
    var rng_a := RandomNumberGenerator.new()
    var rng_b := RandomNumberGenerator.new()
    rng_a.seed = seed_a
    rng_b.seed = seed_b
    for i in 10:
        if rng_a.randi() != rng_b.randi():
            errors += 1
    if errors == 0:
        print("SMOKE_PASS: seeded RNG deterministic in one process; assertions=10")
    else:
        push_error("SMOKE_FAIL: mismatched sequence")
    quit(0 if errors == 0 else 1)
