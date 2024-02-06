extends CharacterBody3D

@onready var camera = $PlayerCamera
@onready var characterModel = $CharacterModel
@onready var subViewPortCont = $PlayerCamera/SubViewportContainer
@onready var hud = $PlayerCamera/SubViewportContainer/HUD
@onready var subViewPort = $PlayerCamera/SubViewportContainer/SubViewport
@onready var subViewPortCamera = $PlayerCamera/SubViewportContainer/SubViewport/Camera3D
@onready var weaponManager = $PlayerCamera/SubViewportContainer/SubViewport/Camera3D/WeaponManager
@onready var audio_player = $PlayerCamera/Camera3D/SoundQueue
@onready var animation_tree: AnimationTree = $AnimationTree

var current_speed = 5.0
const WALKING_SPEED = 5.0
const SPRINTING_SPEED = 8.0
const CROUCHING_SPEED = 3.0

const JUMP_VELOCITY = 4.5

var direction = Vector3.ZERO
var movement_acceleration = 10.0

var cam_rotation_amount = 0.05
var weapon_rotation_amount = 0.005
var defaultWeaponManagerPosition: Vector3

var health = 20

@export var mouse_sens = 0.2

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _on_tree_entered():
	set_multiplayer_authority(str(name).to_int())	

func _ready():
	if is_multiplayer_authority():
		characterModel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		camera.camera.current = true
		defaultWeaponManagerPosition = weaponManager.position
		_on_weapon_manager_weapon_changed()
		
	else:
		hide_subviewport()

func _unhandled_input(event):
	if not str(name).to_int() == multiplayer.get_unique_id(): return
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sens))
		camera.rotate_x(deg_to_rad(-event.relative.y * mouse_sens))
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		subViewPortCont.sway(Vector2(event.relative.x, event.relative.y))
		
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _physics_process(delta):
	rotation.z = 0
	if not str(name).to_int() == multiplayer.get_unique_id(): return
	
	if Input.is_action_pressed("crouch"):
		current_speed = CROUCHING_SPEED
	else:
		if Input.is_action_pressed("sprint"):
			current_speed = SPRINTING_SPEED
		else:
			current_speed = WALKING_SPEED
	
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var anim_blend = Vector3(input_dir.x, 0, input_dir.y).normalized()
	direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * movement_acceleration)
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	
	rpc("update_animation_tree_parameter", "parameters/Moving/movement_blend/blend_position", Vector2(anim_blend.x, anim_blend.z))

	camera_tilt(input_dir.x, delta)
	weapon_tilt(input_dir.x, delta)
	weapon_bob(velocity.length(), delta)
	move_and_slide()
	
func camera_tilt(input_x, delta):
	if camera:
		camera.rotation.z = lerp(camera.rotation.z, -input_x * cam_rotation_amount, 5 * delta)
	
func weapon_tilt(input_x, delta):
	if weaponManager:
		weaponManager.rotation.z = lerp(weaponManager.rotation.z, -input_x * weapon_rotation_amount * 5, 10 * delta)
		
func weapon_bob(vel: float, delta):
	if weaponManager:
		if int(vel) > 0:
			
			var bob_amount: float
			var bob_freq: float
			
			if current_speed == 5:
				bob_freq = 0.01
				bob_amount = 0.01
			elif current_speed == 8:
				bob_freq = 0.02
				bob_amount = 0.02
			else:
				bob_freq = 0.005
				bob_amount = 0.01
			
			weaponManager.position.y = lerp(weaponManager.position.y, 
					defaultWeaponManagerPosition.y + sin(Time.get_ticks_msec() * bob_freq) * bob_amount, 10 * delta)
					
			weaponManager.position.x = lerp(weaponManager.position.x, 
					defaultWeaponManagerPosition.x + sin(Time.get_ticks_msec() * bob_freq * 0.5) * bob_amount, 10 * delta)
	
		else:
			weaponManager.position.y = lerp(weaponManager.position.y, defaultWeaponManagerPosition.y, 10 * delta)
			weaponManager.position.x = lerp(weaponManager.position.x, defaultWeaponManagerPosition.x, 10 * delta)
			
func hide_subviewport():
	subViewPortCont.visible = false
	hud.visible = false
	subViewPortCamera.visible = false
	weaponManager.visible = false
	
func _on_weapon_manager_weapon_changed():
	if is_multiplayer_authority():
		rpc("update_animation_weapon", weaponManager.currentWeapon.WeaponName)

@rpc("any_peer", "call_remote")
func update_animation_weapon(weapon_name):
	animation_tree.get_tree_root().get_node("Moving").get_node(
		"weapon_anim").animation = weapon_name + "_idle"
		
@rpc("any_peer", "call_remote")
func update_animation_tree_parameter(parameter: String, value):
	animation_tree.set(parameter, value)

@rpc("any_peer", "call_local")
func receive_damage(damage):
	health -= damage
	if health <= 0:
		health = 20
		position = Vector3(randf_range(-10, 10), 1.0, 0.0)
	
func play_weapon_sound(sound, peer, max_distance):
	var sound_to_play = load(sound)
	audio_player.play_sound(sound_to_play)
	
