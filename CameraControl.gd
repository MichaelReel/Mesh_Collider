extends ViewportContainer

# export var speed = 1.0

var cameras                     # Camera node - the first person view
var camera_holders              # Spatial node holding all we want to rotate on the X (vert) axis
# This is coupled to the grid and chunk sizes in TerrainManager
export (Array, float) var movement_ratio
var cam_ref
var bodies

const MOUSE_SENSITIVITY = 0.10  # May need to adjust depending on mouse sensitivity

# Intern variables.
var vel = Vector3()
const NORMAL_GRAVITY = -24.8    # Strength of gravity while walking
const TERMINAL_VELOCITY = 50    # If we're falling this fast, something isn't right
const UNSTICK_SPEED = 4         # Hack "jump" speed to unstick camera off the terrain
const MAX_SPEED = 20            # Fastest player can reach
const JUMP_SPEED = 18           # Affects how high we can jump
const ACCEL = 3.5               # How fast we get to top speed
const DEACCEL = 16              # How fast we come to a complete stop
const MAX_SLOPE_ANGLE = 89      # Steepest angle we can climb

var status_output

func _ready():
	status_output  = $"/root/Root/HUD/Panel/PlayerLabel"
	bodies         = [ $Near/PlayerBody, $Far/BodyMount ]
	camera_holders = [ $Near/PlayerBody/CameraMount, $Far/BodyMount/CameraMount ]
	cameras        = [ $Near/PlayerBody/CameraMount/Camera, $Far/BodyMount/CameraMount/Camera ]

	cam_ref = weakref(cameras[0])

	# Keep the mouse in the current window
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process_input(true)

func _physics_process(delta):

	var status = "vel      : " + str(vel) + "\n"

	# Intended direction of movement
	var dir = Vector3()

	# Check camera hasn't been freed
	if not cam_ref.get_ref():
		cameras = [ $Near/PlayerBody/CameraMount/Camera, $Far/CameraMount/Camera ]
		cam_ref = weakref(cameras[0])
		return

	# Global camera transform
	var cam_xform = cameras[0].get_global_transform()

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

	# Accelerate by normal gravity downwards
	vel.y += delta * NORMAL_GRAVITY

	# Check we're falling before we can jump
	if vel.y <= 0:
		if Input.is_action_just_pressed("up"):
			vel.y = JUMP_SPEED

	# If we fall off the map, fall back onto it
	if bodies[0].translation.y < -200:
		for body in bodies:
			body.translation.y = 200
	
	# Remove any extra vertical movement from the direction
	dir.y = 0
	dir = dir.normalized()
	
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
	# Slide the first body (kinematic) then move the other bodies to match the movement
	vel = bodies[0].move_and_slide(vel, Vector3(0,1,0), 5.0, 4, deg2rad(MAX_SLOPE_ANGLE))
	for body_ind in range(len(bodies)):
		if body_ind == 0: continue
		var body_tran = Vector3()
		body_tran.x = bodies[0].translation.x * movement_ratio[body_ind]
		body_tran.y = bodies[0].translation.y
		body_tran.z = bodies[0].translation.z
		bodies[body_ind].translation = body_tran

	status += "dir         : " + str(dir) + "\n"
	status += "cam_xform   : " + str(cam_xform) + "\n"
	status += "grav        : " + str(NORMAL_GRAVITY) + "\n"
	status += "hvel        : " + str(hvel) + "\n"
	status += "target      : " + str(target) + "\n"
	status += "accel       : " + str(accel) + "\n"
	status += "translation : " + str(bodies[0].translation) + "\n"
	status += "rotation    : " + str(bodies[0].rotation) + "\n"

	status_output.text = status


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseMotion && Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate camera holder on the X plane given changes to the Y mouse position (Vertical)
		for camera_holder in camera_holders:
			camera_holder.rotate_x(deg2rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		
		# Rotate cameras on the Y plane given changes to the X mouse position (Horizontal)
		for body in bodies:
			body.rotate_y(deg2rad(event.relative.x * MOUSE_SENSITIVITY * -1))
	
		# Clamp the vertical look to +- 70 because we don't do back flips or tumbles
		for camera_holder in camera_holders:
			var camera_rot = camera_holder.rotation_degrees
			camera_rot.x = clamp(camera_rot.x, -70, 70)
			camera_holder.rotation_degrees = camera_rot