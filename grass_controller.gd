@tool
extends Node3D

const GRASS_MESH_HIGH := preload('res://grass_high.obj')
const GRASS_MESH_LOW := preload('res://grass_low.obj')
const GRASS_MAT := preload('res://grass_mat_instance.tres')

const RED_THRESHOLD := 0.5
const GRID_SIZE := 20.0
const INSTANCE_COUNT_HIGH := 100000
const INSTANCE_COUNT_LOW := 10000

# radio máximo de jitter en XZ (en metros)
const JITTER_RADIUS := 0.6

var cell_to_vertices := {}
var high_cells_instances := {}
var low_cells_instances := {}

# contenedor donde irá TODO el grass
var grass_root: Node3D

@onready var terrain := $map_fbx/map
@onready var player := $Player

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
	var p = player.global_position
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
	for cell in high_cells_instances.keys():
		if cell not in desired_high:
			for mi in high_cells_instances[cell]:
				mi.mesh = GRASS_MESH_LOW
			low_cells_instances[cell] = high_cells_instances[cell]
			high_cells_instances.erase(cell)

	# — Remove Low fuera de rango
	for cell in low_cells_instances.keys():
		if cell not in desired_low:
			for mi in low_cells_instances[cell]:
				mi.queue_free()
			low_cells_instances.erase(cell)

	# — Add High nuevos
	for cell in desired_high:
		if not high_cells_instances.has(cell):
			high_cells_instances[cell] = _instantiate_in_cell(cell, GRASS_MESH_HIGH, INSTANCE_COUNT_HIGH)

	# — Add Low nuevos (sin pisar High)
	for cell in desired_low:
		if not high_cells_instances.has(cell) and not low_cells_instances.has(cell):
			low_cells_instances[cell] = _instantiate_in_cell(cell, GRASS_MESH_LOW, INSTANCE_COUNT_LOW)

func _instantiate_in_cell(cell: Vector2, mesh: Mesh, max_count: int) -> Array:
	var res := []
	if not cell_to_vertices.has(cell):
		return res
	# duplicamos y desordenamos listas
	var verts = cell_to_vertices[cell].duplicate()
	verts.shuffle()
	var count = min(max_count, verts.size())

	for i in range(count):
		var base_pos = verts[i]
		# calculamos jitter en XZ
		var jitter = Vector3(
			randf_range(-JITTER_RADIUS, JITTER_RADIUS),
			0,
			randf_range(-JITTER_RADIUS, JITTER_RADIUS)
		)
		var final_pos = base_pos + jitter

		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = GRASS_MAT
		# lo parentamos al contenedor, luego asignamos transform local
		#grass_root.add_child(mi)
		add_child(mi)
		mi.global_transform = Transform3D(Basis(), final_pos)
		res.append(mi)
	return res
