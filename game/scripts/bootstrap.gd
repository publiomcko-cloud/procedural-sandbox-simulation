extends Node3D

# Intentional: no terrain/simulation implementation yet. Visual bootstrap only.
func _ready() -> void:
    print("SANDBOX_BOOTSTRAP_READY")
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "BootstrapReferenceCube"
    mesh_instance.mesh = BoxMesh.new()
    add_child(mesh_instance)
