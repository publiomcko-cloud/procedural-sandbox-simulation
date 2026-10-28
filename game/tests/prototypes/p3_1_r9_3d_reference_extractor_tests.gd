extends SceneTree

const Extractor := preload("res://tests/prototypes/p3_1_r9_3d_reference_extractor.gd")

var _assertions: int = 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for fixture_name in ["plane", "sphere", "saddle"]:
		var fixture: Dictionary = _make_fixture(String(fixture_name))
		var extractor: RefCounted = Extractor.new()
		var first: Dictionary = extractor.extract(fixture.values, fixture.dims, fixture.cells, fixture.origin, fixture.step)
		_check(bool(first.get("valid", false)), fixture_name + " first extraction valid")
		if not first.get("valid", false):
			print("R9_3D_REFERENCE_INVALID " + JSON.stringify({"fixture": fixture_name, "result": first}))
			continue
		var second: Dictionary = extractor.extract(fixture.values, fixture.dims, fixture.cells, fixture.origin, fixture.step)
		_check(first.mesh_sha256 == second.get("mesh_sha256", ""), fixture_name + " deterministic mesh hash")
		var positions: PackedVector3Array = first.mesh.positions
		var normals: PackedVector3Array = first.mesh.normals
		_check(not positions.is_empty() and positions.size() == normals.size(), fixture_name + " nonempty paired vertices")
		var max_residual: float = 0.0
		var all_finite: bool = true
		for i in range(positions.size()):
			all_finite = all_finite and positions[i].is_finite() and normals[i].is_finite()
			max_residual = maxf(max_residual, absf(_field(String(fixture_name), positions[i])))
		_check(all_finite, fixture_name + " finite positions and normals")
		_check(is_finite(max_residual), fixture_name + " finite analytic residual")
		if fixture_name == "plane":
			_check(max_residual < 0.000001, "plane vertices lie on analytic zero set")
			for normal in normals:
				_check(normal.x < -0.999 and absf(normal.y) < 0.001 and absf(normal.z) < 0.001, "plane normal orientation toward empty")
		print("R9_3D_ANALYTIC_FIXTURE " + JSON.stringify({"fixture": fixture_name, "mesh_sha256": first.mesh_sha256,
			"triangles": positions.size() / 3, "extract": first.metrics, "max_analytic_residual": max_residual,
			"topology": _topology(first.mesh, fixture.origin, fixture.origin + Vector3(fixture.cells) * fixture.step)}))
	print("R9_3D_REFERENCE_TESTS " + JSON.stringify({"assertions": _assertions, "failures": _failures.size(), "failure_details": _failures}))
	quit(1 if not _failures.is_empty() else 0)

func _make_fixture(name: String) -> Dictionary:
	var cells: Vector3i = Vector3i(8, 8, 8)
	var dims: Vector3i = cells + Vector3i.ONE
	var origin: Vector3 = Vector3(-2.0, -2.0, -2.0)
	var step: float = 0.5
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(dims.x * dims.y * dims.z)
	for y in range(dims.y):
		for z in range(dims.z):
			for x in range(dims.x):
				var p: Vector3 = origin + Vector3(x, y, z) * step
				values[_index(Vector3i(x, y, z), dims)] = _field(name, p)
	return {"cells": cells, "dims": dims, "origin": origin, "step": step, "values": values}

func _field(name: String, p: Vector3) -> float:
	match name:
		"plane": return p.x
		"sphere": return 1.5 - p.length()
		"saddle": return p.z - 0.25 * p.x * p.y
	return NAN

func _index(node: Vector3i, dims: Vector3i) -> int:
	return (node.y * dims.z + node.z) * dims.x + node.x

func _topology(mesh: Dictionary, lo: Vector3, hi: Vector3) -> Dictionary:
	const Core := preload("res://tests/prototypes/p3_1_r9_2_diagnostic_base.gd")
	return Core.topology(mesh, lo, hi)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition: _failures.append(label)
