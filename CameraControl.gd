extends KinematicBody

export var speed = 1.0

var camera                      # Camera node - the first person view
var camera_holder               # Spatial node holding all we want to rotate on the X (vert) axis

const MOUSE_SENSITIVITY = 0.10  # May need to adjust depending on mouse sensitivity

# Intern variables.
var vel = Vector3()
const NORMAL_GRAVITY = -24.8    # Strength of gravity while walking
const MAX_SPEED = 20            # Fastest player can reach
const JUMP_SPEED = 18           # Affects how high we can jump
const ACCEL = 3.5               # How fast we get to top speed
const DEACCEL = 16              # How fast we come to a complete stop
const MAX_SLOPE_ANGLE = 40      # Steepest angle we can climb


func _ready():
	camera = $CameraMount/Camera
	camera_holder = $CameraMount
	
	set_physics_process(true)

	# Keep the mouse in the current window
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process_input(true)

func _physics_process(delta):
	# Intended direction of movement
	var dir = Vector3()
	# Global camera transform
	var cam_xform = camera.get_global_transform()

	# Check the directional input and
	# get the direction orientated to the camera in the global coords
	# NB: The camera's Z axis faces backwards to the player
	if Input.is_action_pressed("forward"):
		dir += -cam_xform.basis.z.normalized()
	if Input.is_action_pressed("backward"):
		dir += cam_xform.basis.z.normalized()
	if Input.is_action_pressed("left"):
		dir += -cam_xform.basis.x.normalized()
	if Input.is_action_pressed("right"):
		dir += cam_xform.basis.x.normalized()
	
	# Check we're on the floor before we can jump
	if is_on_floor():
		if Input.is_action_just_pressed("up"):
			vel.y = JUMP_SPEED
	
	# Remove any extra vertical movement from the direction
	dir.y = 0
	dir = dir.normalized()

	# Accelerate by normal gravity downwards
	var grav = NORMAL_GRAVITY
	vel.y += delta * grav
	
	# Get the current horizontal only movement
	var hvel = vel
	hvel.y = 0

	# Get how far we can move horizontally
	var target = dir
	target *= MAX_SPEED

	# Set ac(de)celeration depending on input direction 
	var accel
	if dir.dot(hvel) > 0:
		accel = ACCEL
	else:
		accel = DEACCEL
	
	# Interpolate between the current (horizontal) velocity and the intended velocity
	hvel = hvel.linear_interpolate(target, accel*delta)
	vel.x = hvel.x
	vel.z = hvel.z

	# Use the KinematicBody to control physics movement
	move_and_slide(vel, Vector3(0,1,0), 0.05, 4, deg2rad(MAX_SLOPE_ANGLE))

	## This was only for "Flying" mode - need to turn off gravity to work again
	# dir = Vector3()

	# if Input.is_action_pressed("down"):
	# 	dir.y -= 1.0
	# if Input.is_action_pressed("up"):
	# 	dir.y += 1.0
	
	# translate(dir * speed * delta)


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseMotion && Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate camera holder on the X plane given changes to the Y mouse position (Vertical)
		camera_holder.rotate_x(deg2rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		# Rotate camera on the Y plane given changes to the X mouse position (Horizontal)
		self.rotate_y(deg2rad(event.relative.x * MOUSE_SENSITIVITY * -1))

		# Clamp the vertical look to +- 70 because we don't do back flips or tumbles
		var camera_rot = camera_holder.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, -70, 70)
		camera_holder.rotation_degrees = camera_rot