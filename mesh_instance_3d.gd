extends MeshInstance3D

func _process(_delta):
    # actualizar shader global player position
    RenderingServer.global_shader_parameter_set("player_position", global_transform.origin)


func _physics_process(_delta: float) -> void:
    if Input.is_action_pressed('ui_left'):
        # mover
        global_transform.origin.x -= 1
    if Input.is_action_pressed('ui_right'):
        # mover
        global_transform.origin.x += 1
    if Input.is_action_pressed('ui_up'):
        # mover
        global_transform.origin.z -= 1
    if Input.is_action_pressed('ui_down'):
        # mover
        global_transform.origin.z += 1
