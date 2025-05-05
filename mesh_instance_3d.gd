extends CharacterBody3D

var GRAVITY = 9.8
var speed = 5.0
var jump_velocity = 5.0

func _process(_delta):
	# Actualizar shader global player position
	RenderingServer.global_shader_parameter_set("player_position", global_transform.origin)

func _physics_process(_delta: float) -> void:
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= GRAVITY * _delta
	else:
		# Permitir saltar
		if Input.is_action_just_pressed("ui_accept"):
			velocity.y = jump_velocity

	# Calcular dirección horizontal
	var direction = Vector3.ZERO
	direction.x = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	direction.z = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	direction = direction.normalized()

	# Aplicar movimiento horizontal
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Mover al personaje
	move_and_slide()
