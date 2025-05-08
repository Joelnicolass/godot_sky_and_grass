@tool
extends Node3D

const GRASS_MESH_HIGH := preload('res://grass_high.obj')
const GRASS_MESH_LOW := preload('res://grass_low.obj')
const GRASS_MAT := preload('res://grass_mat_instance.tres')

const RED_THRESHOLD := 0.5
const GRID_SIZE := 20.0
const INSTANCE_COUNT_HIGH := 5000
const INSTANCE_COUNT_LOW := 1000

# radio máximo de jitter en XZ (en metros)
const JITTER_RADIUS := 0.6

var cell_to_vertices := {}
var high_cells_multimesh := {}
var low_cells_multimesh := {}

# contenedor donde irá TODO el grass
var grass_root: Node3D

@onready var terrain := $map_fbx/map
@onready var player: CharacterBody3D = $Player

func _ready() -> void:
	# 1) Creamos el nodo contenedor y lo parentamos al terreno
	grass_root = Node3D.new()
	grass_root.name = "GrassContainer"
	terrain.add_child(grass_root)

	# 2) Agrupamos vértices rojos
	_group_vertices_by_cell()

func _group_vertices_by_cell() -> void:
	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(terrain.mesh, 0) != OK:
		push_error("No pude extraer superficie 0")
		return

	for i in range(mdt.get_vertex_count()):
		if mdt.get_vertex_color(i).r < RED_THRESHOLD:
			continue
		var world_pos = terrain.to_global(mdt.get_vertex(i))
		var key = Vector2(floor(world_pos.x / GRID_SIZE), floor(world_pos.z / GRID_SIZE))
		if not cell_to_vertices.has(key):
			cell_to_vertices[key] = []
		cell_to_vertices[key].append(world_pos)
	mdt.clear()

func _process(delta: float) -> void:
	if not player.is_inside_tree():
		return
	var p := player.global_position
	var pc = Vector2(floor(p.x / GRID_SIZE), floor(p.z / GRID_SIZE))

	# calculamos sets deseados
	var desired_high = [pc]
	var desired_low = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var c = pc + Vector2(dx, dz)
			if c != pc:
				desired_low.append(c)

		# — Demote High → Low
	for cell in high_cells_multimesh.keys():
		if cell not in desired_high:
			var mmi = high_cells_multimesh[cell]
			mmi.multimesh.mesh = GRASS_MESH_LOW
			low_cells_multimesh[cell] = mmi
			high_cells_multimesh.erase(cell)

	# — Remove Low fuera de rango
	for cell in low_cells_multimesh.keys():
		if cell not in desired_low:
			low_cells_multimesh[cell].queue_free()
			low_cells_multimesh.erase(cell)

	# — Add High nuevos
	for cell in desired_high:
		if not high_cells_multimesh.has(cell):
			high_cells_multimesh[cell] = _instantiate_in_cell_multimesh(cell, GRASS_MESH_HIGH, INSTANCE_COUNT_HIGH)

	# — Add Low nuevos (sin pisar High)
	for cell in desired_low:
		if not high_cells_multimesh.has(cell) and not low_cells_multimesh.has(cell):
			low_cells_multimesh[cell] = _instantiate_in_cell_multimesh(cell, GRASS_MESH_LOW, INSTANCE_COUNT_LOW)


func _instantiate_in_cell_multimesh(cell: Vector2, mesh: Mesh, max_count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = max_count
	mmi.multimesh = mm
	mmi.material_override = GRASS_MAT
	# desactivar proyección de sombras
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	if not cell_to_vertices.has(cell):
		return mmi

	var verts = cell_to_vertices[cell]
	var n = verts.size()
	for i in range(max_count):
		var base_pos = verts[randi() % n]
		var jitter = Vector3(
			randf_range(-JITTER_RADIUS, JITTER_RADIUS),
			0,
			randf_range(-JITTER_RADIUS, JITTER_RADIUS)
		)
		var final_pos = base_pos + jitter
		var xform = Transform3D(Basis(), final_pos)
		mm.set_instance_transform(i, xform)
	return mmi
