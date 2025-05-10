@tool
extends Node3D

# Recursos de pasto
const GRASS_MESH_HIGH := preload('res://grass_high.obj')
const GRASS_MESH_LOW := preload('res://grass_low.obj')
const GRASS_MAT := preload('res://grass_mat_instance.tres')

# Parámetros globales
const RED_THRESHOLD := 0.5
const GRID_SIZE := 40.0
const JITTER_RADIUS := 0.6

# Configuración centralizada de niveles LOD
# radius: hasta cuántas celdas en “manhattan” consideramos
# blend: punto (en celdas) donde sube a este LOD (e.g. 0.5 = justo mitad)
var LOD_LEVELS := [
	{"mesh": GRASS_MESH_HIGH, "density": 6000, "radius": 0, "blend": 1.5},
	{"mesh": GRASS_MESH_HIGH, "density": 1000, "radius": 1, "blend": 2.5},
	{"mesh": GRASS_MESH_HIGH, "density": 500, "radius": 2, "blend": 3.5},
	{"mesh": GRASS_MESH_LOW, "density": 300, "radius": 3, "blend": 4.5},
	{"mesh": GRASS_MESH_LOW, "density": 200, "radius": 4, "blend": 5.5},
]

var cell_to_triangles := {} # Vector2 → Array de triángulos [[v0,v1,v2],…]
var cell_instances := {} # Vector2 → MultiMeshInstance3D
var grass_root: Node3D

@onready var terrain := $TestMap/Blend/map
@onready var player := $Player

func _ready() -> void:
	grass_root = Node3D.new()
	grass_root.name = "GrassContainer"
	terrain.add_child(grass_root)
	_group_triangles_by_cell()
	set_process(true)

func _group_triangles_by_cell() -> void:
	var mdt = MeshDataTool.new()
	if mdt.create_from_surface(terrain.mesh, 0) != OK:
		push_error("No pude extraer la superficie 0")
		return

	cell_to_triangles.clear()
	for f in range(mdt.get_face_count()):
		var ia = mdt.get_face_vertex(f, 0)
		var ib = mdt.get_face_vertex(f, 1)
		var ic = mdt.get_face_vertex(f, 2)
		var avg_r = (mdt.get_vertex_color(ia).r + mdt.get_vertex_color(ib).r + mdt.get_vertex_color(ic).r) / 3.0
		if avg_r < RED_THRESHOLD:
			continue
		var a = terrain.to_global(mdt.get_vertex(ia))
		var b = terrain.to_global(mdt.get_vertex(ib))
		var c = terrain.to_global(mdt.get_vertex(ic))
		var center = (a + b + c) / 3.0
		var key = Vector2(floor(center.x / GRID_SIZE), floor(center.z / GRID_SIZE))
		if not cell_to_triangles.has(key):
			cell_to_triangles[key] = []
		cell_to_triangles[key].append([a, b, c])
	mdt.clear()

func _process(delta: float) -> void:
	if not player.is_inside_tree():
		return

	var pc = Vector2(floor(player.global_position.x / GRID_SIZE),
					 floor(player.global_position.z / GRID_SIZE))

	# 1) Determinar desired[cell] → lod_index
	var desired := {}
	# Para cada celda alrededor de pc:
	var max_rad = LOD_LEVELS.back()["radius"]
	for dx in range(-max_rad, max_rad + 1):
		for dz in range(-max_rad, max_rad + 1):
			var cell = pc + Vector2(dx, dz)
			var center = Vector3((cell.x + 0.5) * GRID_SIZE, 0, (cell.y + 0.5) * GRID_SIZE)
			var dist = player.global_position.distance_to(center)
			# Itera LODs de más detallado a más lejano y asigna el primero que cumpla
			for lod_i in range(LOD_LEVELS.size()):
				var cfg = LOD_LEVELS[lod_i]
				var blend_dist = cfg["blend"] * GRID_SIZE
				if dist < blend_dist:
					desired[cell] = lod_i
					break

	# 2) Eliminar instancias fuera de desired
	for cell in cell_instances.keys():
		if not desired.has(cell):
			cell_instances[cell].queue_free()
			cell_instances.erase(cell)

	# 3) Actualizar LOD en existentes
	for cell in desired.keys():
		if cell_instances.has(cell):
			var mmi = cell_instances[cell]
			var old = mmi.get_meta("lod_level")
			var nw = desired[cell]
			if old != nw:
				_update_cell_lod(cell, mmi, nw)

	# 4) Crear nuevas
	for cell in desired.keys():
		if not cell_instances.has(cell):
			cell_instances[cell] = _instantiate_cell_multimesh(cell, desired[cell])

func _instantiate_cell_multimesh(cell: Vector2, lod_i: int) -> MultiMeshInstance3D:
	var cfg = LOD_LEVELS[lod_i]
	var mmi = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cfg["mesh"]
	mm.instance_count = cfg["density"]
	mmi.multimesh = mm
	mmi.material_override = GRASS_MAT
	mmi.set_meta("lod_level", lod_i)
	grass_root.add_child(mmi)
	_fill_multimesh(mm, cell, cfg["density"])
	return mmi

func _update_cell_lod(cell: Vector2, mmi: MultiMeshInstance3D, lod_i: int) -> void:
	var cfg = LOD_LEVELS[lod_i]
	var mm = mmi.multimesh
	mm.mesh = cfg["mesh"]
	mm.instance_count = cfg["density"]
	mmi.set_meta("lod_level", lod_i)
	# cast shadow en true para lods más cercanos
	if lod_i == 0:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# desactivar casteo de sombras para evitar flickering
	_fill_multimesh(mm, cell, cfg["density"])

func _fill_multimesh(mm: MultiMesh, cell: Vector2, count: int) -> void:
	var tris = cell_to_triangles.get(cell, [])
	var tcnt = tris.size()
	for i in range(count):
		if tcnt == 0:
			mm.set_instance_transform(i, Transform3D())
		else:
			var tri = tris[randi() % tcnt]
			var p = _sample_point_in_triangle(tri[0], tri[1], tri[2])
			var jitter = Vector3(randf_range(-JITTER_RADIUS, JITTER_RADIUS), 5.0,
								 randf_range(-JITTER_RADIUS, JITTER_RADIUS))
			mm.set_instance_transform(i, Transform3D(Basis(), p + jitter))

func _sample_point_in_triangle(v0: Vector3, v1: Vector3, v2: Vector3) -> Vector3:
	var u = randf(); var v = randf()
	if u + v > 1.0:
		u = 1.0 - u; v = 1.0 - v
	return v0 * (1 - u - v) + v1 * u + v2 * v
