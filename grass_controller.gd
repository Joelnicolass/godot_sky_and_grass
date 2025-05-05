@tool
extends Node3D

const GRASS_MESH_HIGH := preload('res://grass_high.obj')
const GRASS_MESH_LOW := preload('res://grass_low.obj')
const GRASS_MAT := preload('res://grass_mat_instance.tres')

const RED_THRESHOLD := 0.5
const GRID_SIZE := 10.0
const INSTANCE_COUNT_HIGH := 100000
const INSTANCE_COUNT_LOW := 10000

var cell_to_vertices := {}
var high_cells_instances := {}
var low_cells_instances := {}

@onready var terrain := $map_fbx/map
@onready var player := $Player

func _ready() -> void:
    _group_vertices_by_cell()

func _group_vertices_by_cell() -> void:
    var mesh = terrain.mesh
    var mdt = MeshDataTool.new()
    mdt.create_from_surface(mesh, 0)
    for i in range(mdt.get_vertex_count()):
        if mdt.get_vertex_color(i).r < RED_THRESHOLD: continue
        var wp = terrain.to_global(mdt.get_vertex(i))
        var key = Vector2(floor(wp.x / GRID_SIZE), floor(wp.z / GRID_SIZE))
        if not cell_to_vertices.has(key): cell_to_vertices[key] = []
        cell_to_vertices[key].append(wp)
    mdt.clear()

func _process(delta):
    var p = player.global_position
    var pc = Vector2(floor(p.x / GRID_SIZE), floor(p.z / GRID_SIZE))

    # Determinar qué celdas deben estar en High y Low
    var desired_high = [pc]
    var desired_low = []
    for dx in range(-2, 3):
        for dz in range(-2, 3):
            var c = pc + Vector2(dx, dz)
            if c != pc:
                desired_low.append(c)

    # — REMOVE / DEMOTE High → Low
    for cell in high_cells_instances.keys():
        if cell not in desired_high:
            # mover instancias de High a Low
            var arr = high_cells_instances[cell]
            for mi in arr:
                mi.mesh = GRASS_MESH_LOW
            low_cells_instances[cell] = arr
            high_cells_instances.erase(cell)

    # — REMOVE Low entirely
    for cell in low_cells_instances.keys():
        if cell not in desired_low:
            for mi in low_cells_instances[cell]:
                mi.queue_free()
            low_cells_instances.erase(cell)

    # — ADD new High
    for cell in desired_high:
        if not high_cells_instances.has(cell):
            high_cells_instances[cell] = _instantiate_in_cell(cell, GRASS_MESH_HIGH, INSTANCE_COUNT_HIGH)

    # — ADD new Low (excluyendo las que son High)
    for cell in desired_low:
        if not high_cells_instances.has(cell) and not low_cells_instances.has(cell):
            low_cells_instances[cell] = _instantiate_in_cell(cell, GRASS_MESH_LOW, INSTANCE_COUNT_LOW)

func _instantiate_in_cell(cell: Vector2, mesh: Mesh, max_count: int) -> Array:
    var res := []
    if not cell_to_vertices.has(cell):
        return res
    var verts = cell_to_vertices[cell].duplicate()
    verts.shuffle()
    var count = min(max_count, verts.size())
    for i in range(count):
        var mi = MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = GRASS_MAT
        # 1) Primero lo agregamos a la escena
        add_child(mi)
        # 2) Ahora sí podemos modificar su global_transform
        mi.global_transform = Transform3D(Basis(), verts[i])
        res.append(mi)
    return res
